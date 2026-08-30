resource "aws_sqs_queue" "trigger_dlq" {
  name                       = "${local.name}-trigger-dlq"
  message_retention_seconds  = var.sqs_message_retention_seconds
  sqs_managed_sse_enabled    = true
}

resource "aws_sqs_queue" "trigger" {
  name                       = "${local.name}-trigger"
  visibility_timeout_seconds = local.visibility_timeout
  message_retention_seconds  = var.sqs_message_retention_seconds
  sqs_managed_sse_enabled    = true
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.trigger_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
}

resource "aws_sqs_queue" "complete" {
  name                      = "${local.name}-complete"
  message_retention_seconds = var.sqs_message_retention_seconds
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "error" {
  name                      = "${local.name}-error"
  message_retention_seconds = var.sqs_message_retention_seconds
  sqs_managed_sse_enabled   = true
}
