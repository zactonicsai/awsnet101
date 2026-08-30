data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "worker" {
  function_name = local.lambda_name
  description   = "Copy an S3 object to another bucket with a new key prefix; report to complete/error SQS queues."
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_mb

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      COMPLETE_QUEUE_URL = aws_sqs_queue.complete.url
      ERROR_QUEUE_URL    = aws_sqs_queue.error.url
      DEST_BUCKET        = local.dest_bucket_name
      NEW_PREFIX         = var.default_new_prefix
      SOURCE_BUCKET      = local.source_bucket_name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]
}

resource "aws_lambda_event_source_mapping" "trigger" {
  event_source_arn                   = aws_sqs_queue.trigger.arn
  function_name                      = aws_lambda_function.worker.arn
  batch_size                         = var.sqs_batch_size
  enabled                            = true
  function_response_types            = ["ReportBatchItemFailures"]
  maximum_batching_window_in_seconds = 0
}
