variable "name" {
  description = "Name prefix for the endpoints."
  type        = string
}

variable "vpc_id" {
  description = "EXISTING VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "EXISTING PRIVATE subnet IDs for interface endpoints. One ENI is created per subnet, and you are billed per ENI-hour -- so listing four subnets costs twice as much as listing two."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "EXISTING security group IDs for interface endpoints. Must allow inbound HTTPS (443) from the instances that will use them, or every call times out."
  type        = list(string)
  default     = []
}

variable "route_table_ids" {
  description = "EXISTING route table IDs for gateway endpoints. Gateway endpoints attach to route tables rather than creating ENIs, which is why they are free."
  type        = list(string)
  default     = []
}

variable "interface_endpoints" {
  description = <<-EOT
    Service short names for interface endpoints, e.g. ["ssm", "ec2messages",
    "ssmmessages", "secretsmanager", "ecr.api", "ecr.dkr", "logs"].

    COST: ~$7.20/month EACH, per Availability Zone, plus $0.01/GB.
    Three endpoints across two AZs is roughly $43/month -- more than a NAT
    Gateway. Do the arithmetic before assuming endpoints are the cheap option.

    Common bundles:
      Session Manager  -> ["ssm", "ec2messages", "ssmmessages"]
      Pull from ECR    -> ["ecr.api", "ecr.dkr"] plus the S3 GATEWAY endpoint,
                          because image layers live in S3
      Read secrets     -> ["secretsmanager"]
  EOT
  type        = list(string)
  default     = []
}

variable "gateway_endpoints" {
  description = "Service short names for gateway endpoints. Only \"s3\" and \"dynamodb\" exist. Both are FREE -- always enable S3 if anything private touches S3 or pulls container images."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.gateway_endpoints : contains(["s3", "dynamodb"], s)])
    error_message = "Only s3 and dynamodb support gateway endpoints. Everything else must be an interface endpoint."
  }
}

variable "private_dns_enabled" {
  description = "Make the real AWS hostname resolve to the endpoint's private IP, so applications need no code changes. Requires enable_dns_hostnames and enable_dns_support on the VPC. Leave true."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for the endpoints."
  type        = map(string)
  default     = {}
}
