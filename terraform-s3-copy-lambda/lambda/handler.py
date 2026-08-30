"""SQS-triggered S3 copy worker.

Expected trigger message body (JSON):
{
  "source_bucket": "optional-overrides-env",
  "source_key": "path/to/file.csv",
  "dest_bucket": "optional-overrides-env",
  "new_prefix": "copied/"   // or "processed_" for a filename prefix
}

Destination key rules:
  - If new_prefix ends with "/", dest_key = new_prefix + basename(source_key)
    e.g. prefix "archive/2026/" + "dir/file.csv" -> "archive/2026/file.csv"
  - Otherwise dest_key = new_prefix + basename(source_key)
    e.g. prefix "processed_" + "dir/file.csv" -> "processed_file.csv"

On success a JSON message is sent to COMPLETE_QUEUE_URL.
On handled copy/validation errors a JSON message is sent to ERROR_QUEUE_URL
and the trigger message is deleted (not retried). Unexpected infrastructure
errors are raised so SQS can retry / DLQ.
"""

from __future__ import annotations

import json
import logging
import os
import traceback
from typing import Any
from urllib.parse import unquote_plus

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
sqs = boto3.client("sqs")

COMPLETE_QUEUE_URL = os.environ["COMPLETE_QUEUE_URL"]
ERROR_QUEUE_URL = os.environ["ERROR_QUEUE_URL"]
DEFAULT_DEST_BUCKET = os.environ.get("DEST_BUCKET", "")
DEFAULT_SOURCE_BUCKET = os.environ.get("SOURCE_BUCKET", "")
DEFAULT_PREFIX = os.environ.get("NEW_PREFIX", "copied/")


class JobError(Exception):
    """Expected, non-retryable job failure (bad payload, missing object, etc.)."""


def _parse_body(raw: str) -> dict[str, Any]:
    try:
        body = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise JobError(f"Trigger message is not valid JSON: {exc}") from exc

    # Unwrap common SNS -> SQS envelope
    if isinstance(body, dict) and "Message" in body and "Type" in body:
        try:
            body = json.loads(body["Message"])
        except (TypeError, json.JSONDecodeError) as exc:
            raise JobError(f"SNS Message is not valid JSON: {exc}") from exc

    if not isinstance(body, dict):
        raise JobError("Trigger message JSON must be an object")
    return body


def _require_str(body: dict[str, Any], key: str, fallback: str = "") -> str:
    value = body.get(key, fallback)
    if value is None or str(value).strip() == "":
        raise JobError(f"Missing required field: {key}")
    return str(value).strip()


def build_dest_key(source_key: str, new_prefix: str) -> str:
    filename = source_key.rstrip("/").split("/")[-1]
    if not filename:
        raise JobError(f"Cannot derive filename from source_key={source_key!r}")
    return f"{new_prefix}{filename}"


def send_queue(queue_url: str, payload: dict[str, Any]) -> None:
    sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(payload, default=str))


def copy_object(source_bucket: str, source_key: str, dest_bucket: str, dest_key: str) -> dict[str, Any]:
    try:
        result = s3.copy_object(
            CopySource={"Bucket": source_bucket, "Key": source_key},
            Bucket=dest_bucket,
            Key=dest_key,
            MetadataDirective="COPY",
            TaggingDirective="COPY",
        )
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "ClientError")
        message = exc.response.get("Error", {}).get("Message", str(exc))
        raise JobError(f"S3 copy failed ({code}): {message}") from exc

    etag = result.get("CopyObjectResult", {}).get("ETag")
    return {"etag": etag, "version_id": result.get("VersionId")}


def process_record(record: dict[str, Any]) -> dict[str, Any]:
    message_id = record.get("messageId")
    body = _parse_body(record.get("body") or "")

    source_bucket = _require_str(body, "source_bucket", DEFAULT_SOURCE_BUCKET)
    source_key = unquote_plus(_require_str(body, "source_key"))
    dest_bucket = _require_str(body, "dest_bucket", DEFAULT_DEST_BUCKET)
    new_prefix = str(body.get("new_prefix") or DEFAULT_PREFIX)

    dest_key = build_dest_key(source_key, new_prefix)
    copy_meta = copy_object(source_bucket, source_key, dest_bucket, dest_key)

    result = {
        "status": "completed",
        "message_id": message_id,
        "source_bucket": source_bucket,
        "source_key": source_key,
        "dest_bucket": dest_bucket,
        "dest_key": dest_key,
        "etag": copy_meta.get("etag"),
        "version_id": copy_meta.get("version_id"),
    }
    send_queue(COMPLETE_QUEUE_URL, result)
    logger.info("Copied s3://%s/%s -> s3://%s/%s", source_bucket, source_key, dest_bucket, dest_key)
    return result


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    batch_failures: list[dict[str, str]] = []

    for record in event.get("Records", []):
        message_id = record.get("messageId", "unknown")
        try:
            process_record(record)
        except JobError as exc:
            logger.warning("Job error for message %s: %s", message_id, exc)
            send_queue(
                ERROR_QUEUE_URL,
                {
                    "status": "error",
                    "message_id": message_id,
                    "error": str(exc),
                    "error_type": "JobError",
                    "original_message": record.get("body"),
                },
            )
        except Exception as exc:  # noqa: BLE001 — retry unexpected failures
            logger.exception("Unexpected error for message %s", message_id)
            try:
                send_queue(
                    ERROR_QUEUE_URL,
                    {
                        "status": "error",
                        "message_id": message_id,
                        "error": str(exc),
                        "error_type": type(exc).__name__,
                        "traceback": traceback.format_exc(),
                        "original_message": record.get("body"),
                    },
                )
            except Exception:
                logger.exception("Failed to publish error message for %s", message_id)
            batch_failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": batch_failures}
