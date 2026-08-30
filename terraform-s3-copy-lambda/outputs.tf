output "source_bucket_name" {
  description = "Source S3 bucket name."
  value       = local.source_bucket_name
}

output "dest_bucket_name" {
  description = "Destination S3 bucket name."
  value       = local.dest_bucket_name
}

output "trigger_queue_url" {
  description = "Send copy jobs to this queue."
  value       = aws_sqs_queue.trigger.url
}

output "trigger_queue_arn" {
  value = aws_sqs_queue.trigger.arn
}

output "complete_queue_url" {
  description = "Successful copy notifications land here."
  value       = aws_sqs_queue.complete.url
}

output "error_queue_url" {
  description = "Failed copy notifications land here."
  value       = aws_sqs_queue.error.url
}

output "trigger_dlq_url" {
  description = "Poison messages that exhaust receive attempts on the trigger queue."
  value       = aws_sqs_queue.trigger_dlq.url
}

output "lambda_function_name" {
  value = aws_lambda_function.worker.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.worker.arn
}

output "example_message" {
  description = "Example JSON body to send to the trigger queue."
  value = jsonencode({
    source_bucket = local.source_bucket_name
    source_key    = "incoming/report.csv"
    dest_bucket   = local.dest_bucket_name
    new_prefix    = var.default_new_prefix
  })
}
