variable "name" {
  description = "Name prefix for the launch template."
  type        = string
}

# --- Image selection ---------------------------------------------------------

variable "ami_id" {
  description = <<-EOT
    EXISTING AMI to launch. Leave null to auto-resolve the latest Amazon Linux
    2023 image matching `architecture` via AWS's public SSM parameter.

    Never hard-code an AMI ID in committed code: IDs differ per region and
    change with every security patch, so a literal goes stale and breaks
    cross-region reuse.
  EOT
  type        = string
  default     = null
}

variable "architecture" {
  description = "\"arm64\" (Graviton, ~20% cheaper) or \"x86_64\". Only used when ami_id is null. MUST match instance_type -- a t4g with an x86_64 image simply will not boot."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be either arm64 or x86_64."
  }
}

variable "instance_type" {
  description = "e.g. t4g.nano (ARM, ~$3/mo), t3.micro (x86, free tier eligible)."
  type        = string
  default     = "t4g.nano"
}

# --- User data ---------------------------------------------------------------

variable "user_data" {
  description = <<-EOT
    Bootstrap script as a raw string, run ONCE on first boot as root.
    Mutually exclusive with user_data_template_path.

    This module base64-encodes it for you -- do not pre-encode.
  EOT
  type        = string
  default     = null
}

variable "user_data_template_path" {
  description = <<-EOT
    Path to a script template rendered with user_data_vars before launch.
    Use this instead of `user_data` when the script needs values only known at
    apply time (a bucket name, a port, a database endpoint).

    Pass an absolute path so the module works no matter where it is called
    from:  user_data_template_path = "${path.root}/scripts/bootstrap.sh"
  EOT
  type        = string
  default     = null
}

variable "user_data_vars" {
  description = "Values substituted into the template's $${...} placeholders. All values must be strings."
  type        = map(string)
  default     = {}
}

# --- Networking and identity -------------------------------------------------

variable "security_group_ids" {
  description = "EXISTING security group IDs to attach. Pass module.app_sg.security_group_id."
  type        = list(string)
  default     = []
}

variable "iam_instance_profile_name" {
  description = "EXISTING instance profile NAME (not ARN). Pass module.app_profile.instance_profile_name. Null for no AWS permissions."
  type        = string
  default     = null
}

variable "key_name" {
  description = "EXISTING EC2 key pair for SSH. Leave null -- prefer Session Manager, which needs no key, no open port 22, and no key to leak."
  type        = string
  default     = null
}

variable "associate_public_ip_address" {
  description = "Force a public IP. Leave null to inherit the subnet's setting, which is what you want when launching into private subnets."
  type        = bool
  default     = null
}

# --- Storage -----------------------------------------------------------------

variable "root_volume_size" {
  description = "Root disk size in GB. 8 is the minimum for Amazon Linux 2023."
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Always gp3 -- cheaper AND faster than gp2. There is no reason left to use gp2."
  type        = string
  default     = "gp3"
}

variable "root_volume_encrypted" {
  description = "Encrypt the root volume. Free, no performance cost, no reason to disable."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "Customer-managed KMS key for volume encryption. Null uses the free AWS-managed key."
  type        = string
  default     = null
}

variable "extra_block_devices" {
  description = <<-EOT
    Additional EBS volumes.
    Example:
      extra_block_devices = [{ device_name = "/dev/xvdb", volume_size = 50 }]
  EOT
  type = list(object({
    device_name           = string
    volume_size           = number
    volume_type           = optional(string, "gp3")
    encrypted             = optional(bool, true)
    delete_on_termination = optional(bool, true)
  }))
  default = []
}

# --- Behaviour ---------------------------------------------------------------

variable "enable_detailed_monitoring" {
  description = "1-minute CloudWatch metrics instead of 5-minute. Costs ~$2.10/instance/month. Worth it when an ASG scales on metrics, because 5-minute data reacts too slowly."
  type        = bool
  default     = false
}

variable "http_tokens" {
  description = "\"required\" forces IMDSv2, which blocks an entire family of SSRF credential-theft attacks. Free. Only use \"optional\" for legacy software that genuinely cannot cope."
  type        = string
  default     = "required"
}

variable "http_put_response_hop_limit" {
  description = "Network hops the metadata response may travel. 1 stops containers on the host reaching it. Raise to 2 only if you run Docker and the container needs credentials."
  type        = number
  default     = 1
}

variable "instance_tags" {
  description = "Tags applied to instances and volumes created from this template."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags on the launch template resource itself."
  type        = map(string)
  default     = {}
}
