variable "name" {
  description = "Secret name. Use a path-like convention such as \"myapp/prod/keycloak-admin\" so secrets group sensibly in the console."
  type        = string
}

variable "description" {
  description = "What this secret holds."
  type        = string
  default     = "Managed by Terraform"
}

variable "generate_password" {
  description = <<-EOT
    Generate a random password instead of supplying one.

    IMPORTANT CAVEAT: the generated value IS stored in Terraform state. That is
    still far better than committing a password to Git, but it means state must
    be treated as a secret: encrypted S3 backend, restricted access, never in a
    repository. For the strongest option, use RDS's manage_master_user_password,
    where the value never touches Terraform at all.
  EOT
  type        = bool
  default     = false
}

variable "password_length" {
  description = "Length of the generated password."
  type        = number
  default     = 32
}

variable "password_override_special" {
  description = "Which special characters to allow. The default deliberately excludes quotes, backslashes, and shell metacharacters that break connection strings and user data scripts."
  type        = string
  default     = "!#$%&*()-_=+[]{}<>:?"
}

variable "secret_string" {
  description = "Literal secret value, used when generate_password is false. Ignored otherwise."
  type        = string
  default     = null
  sensitive   = true
}

variable "secret_key_value" {
  description = <<-EOT
    Store a JSON object instead of a plain string. Keys with a null value are
    replaced by the generated password, which is how you build a credentials
    blob in one step.

    Example:
      secret_key_value = { username = "admin", password = null }
    produces: {"username":"admin","password":"<generated>"}
  EOT
  type        = map(string)
  default     = null
  sensitive   = true
}

variable "kms_key_id" {
  description = "Customer-managed KMS key. Null uses the free AWS-managed key, which is fine for most cases."
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = <<-EOT
    Days a deleted secret is recoverable before permanent deletion.

    Set 0 for immediate deletion in test environments. Leave 7-30 in production.
    Gotcha: with a non-zero window the NAME stays reserved, so recreating a
    secret with the same name fails until the window expires.
  EOT
  type        = number
  default     = 7
}

variable "read_principal_arns" {
  description = "IAM role/user ARNs granted read access via a resource policy. Often simpler than editing each role. Empty list attaches no policy."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags for the secret."
  type        = map(string)
  default     = {}
}
