variable "name" {
  description = "Name prefix for the role and instance profile."
  type        = string
}

variable "managed_policy_arns" {
  description = <<-EOT
    AWS-managed or customer-managed policy ARNs to attach.

    Two you will want constantly:
      arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
        -- enables Session Manager shell access with no SSH key and no open port 22
      arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
        -- lets the instance publish metrics and logs
  EOT
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = <<-EOT
    Inline policies as a map of name => JSON policy document.
    Build the JSON with the aws_iam_policy_document data source rather than
    hand-writing it -- you get validation and no quoting mistakes.

    Example:
      inline_policies = {
        read-app-bucket = data.aws_iam_policy_document.bucket_read.json
      }
  EOT
  type        = map(string)
  default     = {}
}

variable "trusted_service" {
  description = "Which AWS service may assume this role. \"ec2.amazonaws.com\" for EC2 instances."
  type        = string
  default     = "ec2.amazonaws.com"
}

variable "permissions_boundary" {
  description = "Optional permissions boundary ARN. Many organisations require one -- it caps what the role can ever be granted, even by a future edit."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for the role and profile."
  type        = map(string)
  default     = {}
}
