variable "bucket_name" {
  description = "Globally unique bucket name. S3 names are shared across EVERY AWS account on earth, so include your org or a random suffix."
  type        = string
}

variable "versioning_enabled" {
  description = "Keep every version of every object. Your best protection against accidental deletion and ransomware. Note old versions keep costing storage -- pair with a lifecycle rule."
  type        = bool
  default     = true
}

variable "block_public_access" {
  description = "Block ALL public access. Leave true unless you are deliberately hosting a public website. Public buckets are one of the most common serious data breaches."
  type        = bool
  default     = true
}

variable "sse_algorithm" {
  description = "\"AES256\" is free SSE-S3 encryption. \"aws:kms\" allows customer-managed keys and audit trails, but costs per request."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be AES256 or aws:kms."
  }
}

variable "kms_key_id" {
  description = "KMS key ARN, used only when sse_algorithm is aws:kms."
  type        = string
  default     = null
}

variable "bucket_key_enabled" {
  description = "S3 Bucket Keys cut KMS request costs by up to 99%. Free to enable. Always leave true when using KMS."
  type        = bool
  default     = true
}

variable "lifecycle_rules" {
  description = <<-EOT
    Lifecycle rules, keyed by name. These are how you stop storage costs
    growing forever.

    Example:
      lifecycle_rules = {
        expire-old-logs = {
          prefix                            = "logs/"
          expiration_days                   = 90
          noncurrent_version_expiration_days = 30
        }
      }
  EOT
  type = map(object({
    enabled                            = optional(bool, true)
    prefix                             = optional(string, "")
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transition_to_ia_days              = optional(number)
    transition_to_glacier_days         = optional(number)
    abort_incomplete_upload_days       = optional(number, 7)
  }))
  default = {}
}

variable "enable_alb_access_logs_policy" {
  description = <<-EOT
    Attach the bucket policy that lets an Application Load Balancer write
    access logs here. Required -- ALB log delivery fails silently without it,
    and the failure is invisible until you notice the bucket is empty.
  EOT
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete a bucket that still contains objects. Convenient for test environments, dangerous anywhere else."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for the bucket."
  type        = map(string)
  default     = {}
}
