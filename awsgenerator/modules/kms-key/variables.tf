variable "alias" {
  description = "Human-friendly alias WITHOUT the \"alias/\" prefix, which the module adds. Keys have unreadable UUIDs, so always give an alias."
  type        = string
}

variable "description" {
  description = "What this key protects."
  type        = string
  default     = "Managed by Terraform"
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion completes, 7-30. AWS enforces a minimum of 7 because deleting a key makes everything it encrypted permanently unreadable."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "enable_key_rotation" {
  description = "Rotate the backing material annually. Free, transparent, and old data stays readable with the old material. Leave true."
  type        = bool
  default     = true
}

variable "service_principals" {
  description = "AWS service principals allowed to use the key, e.g. [\"rds.amazonaws.com\", \"secretsmanager.amazonaws.com\"]. Required for a service to encrypt on your behalf."
  type        = list(string)
  default     = []
}

variable "user_role_arns" {
  description = "IAM role/user ARNs allowed to encrypt and decrypt with this key."
  type        = list(string)
  default     = []
}

variable "admin_role_arns" {
  description = "IAM ARNs allowed to administer the key. Defaults to the account root when empty, which keeps normal IAM policies in charge."
  type        = list(string)
  default     = []
}

variable "multi_region" {
  description = "Create a multi-region key, replicable to other regions. Cannot be changed later."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for the key."
  type        = map(string)
  default     = {}
}
