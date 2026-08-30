# SQS-triggered S3 copy Lambda

Terraform stack that deploys:

- Optional source and destination S3 buckets
- Trigger SQS queue (Lambda event source) plus a DLQ for poison messages
- Complete SQS queue
- Error SQS queue
- Python 3.12 Lambda that copies an object and rewrites the destination key with a new prefix

```
SQS trigger  -->  Lambda  -->  S3 Copy (src -> dst with new prefix)
                    |-- success --> SQS complete
                    |-- job error --> SQS error  (message consumed)
                    |-- unexpected error --> SQS error + retry / trigger DLQ
```

## Deploy

```bash
cd terraform-s3-copy-lambda
cp terraform.tfvars.example terraform.tfvars
# edit region / names as needed

terraform init
terraform plan
terraform apply
```

Use existing buckets instead of creating new ones:

```hcl
create_buckets     = false
source_bucket_name = "my-existing-source"
dest_bucket_name   = "my-existing-dest"
```

The Lambda IAM policy still grants GetObject on the source bucket and PutObject on the destination bucket. Those buckets must already exist in the same account.

## Trigger message

Send JSON to the **trigger** queue (`terraform output -raw trigger_queue_url`).

```json
{
  "source_bucket": "s3-copy-src-xxxxxxxx",
  "source_key": "incoming/report.csv",
  "dest_bucket": "s3-copy-dst-xxxxxxxx",
  "new_prefix": "copied/"
}
```

All fields except `source_key` are optional. Missing values fall back to environment defaults set by Terraform (`SOURCE_BUCKET`, `DEST_BUCKET`, `NEW_PREFIX`).

### Destination key

`dest_key` is always `new_prefix + basename(source_key)`:

| `source_key` | `new_prefix` | `dest_key` |
|---|---|---|
| `incoming/report.csv` | `copied/` | `copied/report.csv` |
| `incoming/report.csv` | `processed_` | `processed_report.csv` |
| `incoming/report.csv` | `archive/2026/08/` | `archive/2026/08/report.csv` |

Object metadata and tags are copied.

## Result messages

**Complete queue**

```json
{
  "status": "completed",
  "message_id": "sqs-message-id",
  "source_bucket": "...",
  "source_key": "incoming/report.csv",
  "dest_bucket": "...",
  "dest_key": "copied/report.csv",
  "etag": "\"...\"",
  "version_id": null
}
```

**Error queue**

```json
{
  "status": "error",
  "message_id": "sqs-message-id",
  "error": "S3 copy failed (NoSuchKey): The specified key does not exist.",
  "error_type": "JobError",
  "original_message": "{...}"
}
```

Validation problems and S3 client errors (missing key, access denied, bad payload) are treated as **job errors**: they are published to the error queue and the trigger message is deleted so it is not retried.

Unexpected failures (IAM outage mid-send, runtime bugs) are published to the error queue **and** reported as batch item failures so SQS retries, then the trigger DLQ after `sqs_max_receive_count` attempts.

## Manual smoke test

```bash
SRC=$(terraform output -raw source_bucket_name)
DST=$(terraform output -raw dest_bucket_name)
TRIGGER=$(terraform output -raw trigger_queue_url)
COMPLETE=$(terraform output -raw complete_queue_url)
ERROR=$(terraform output -raw error_queue_url)

echo 'hello' | aws s3 cp - "s3://$SRC/incoming/hello.txt"

aws sqs send-message --queue-url "$TRIGGER" --message-body "{
  \"source_bucket\": \"$SRC\",
  \"source_key\": \"incoming/hello.txt\",
  \"dest_bucket\": \"$DST\",
  \"new_prefix\": \"copied/\"
}"

# wait a few seconds
aws s3 ls "s3://$DST/copied/"
aws sqs receive-message --queue-url "$COMPLETE" --wait-time-seconds 10
```

## Outputs

| Output | Purpose |
|---|---|
| `trigger_queue_url` | Submit jobs |
| `complete_queue_url` | Success notifications |
| `error_queue_url` | Failure notifications |
| `trigger_dlq_url` | Exhausted retries |
| `source_bucket_name` / `dest_bucket_name` | Buckets in use |
| `example_message` | Ready-to-send sample payload |
