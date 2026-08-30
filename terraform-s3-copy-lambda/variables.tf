variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to all resource names."
  type        = string
  default     = "s3-copy"
}

variable "tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
  default = {
    Project   = "s3-copy-lambda"
    ManagedBy = "terraform"
  }
}

variable "create_buckets" {
  description = "Whether Terraform should create the source and destination buckets."
  type        = bool
  default     = true
}

variable "source_bucket_name" {
  description = "Existing source bucket name. Used when create_buckets is false, or as the exact name when create_buckets is true. Leave empty to generate a unique name."
  type        = string
  default     = ""
}

variable "dest_bucket_name" {
  description = "Existing destination bucket name. Used when create_buckets is false, or as the exact name when create_buckets is true. Leave empty to generate a unique name."
  type        = string
  default     = ""
}

variable "default_new_prefix" {
  description = "Default key prefix applied when the SQS message does not include new_prefix. Use a path prefix ending with '/' (archive/) or a filename prefix (processed_)."
  type        = string
  default     = "copied/"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds. SQS visibility timeout is set higher than this."
  type        = number
  default     = 60
}

variable "lambda_memory_mb" {
  description = "Lambda memory in MB."
  type        = number
  default     = 256
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for the Lambda. Set null for unreserved."
  type        = number
  default     = null
}

variable "sqs_message_retention_seconds" {
  description = "How long SQS retains messages (60–1,209,600)."
  type        = number
  default     = 345600 # 4 days
}

variable "sqs_max_receive_count" {
  description = "Receive attempts before the trigger queue sends a message to its DLQ (invocation failures only)."
  type        = number
  default     = 3
}

variable "sqs_batch_size" {
  description = "Number of SQS messages delivered to Lambda per invocation."
  type        = number
  default     = 1
}

variable "enable_s3_versioning" {
  description = "Enable versioning on buckets created by this stack."
  type        = bool
  default     = true
}
