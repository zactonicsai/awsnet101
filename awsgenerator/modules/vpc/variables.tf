variable "name" {
  description = "Name prefix applied to every resource this module creates."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR for the VPC, e.g. \"10.0.0.0/16\". Hard to change later, so be generous."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR, for example 10.0.0.0/16."
  }
}

variable "availability_zones" {
  description = <<-EOT
    AZ names to spread across, e.g. ["us-east-1a", "us-east-1b"].
    Leave empty to auto-select the first `az_count` available zones in the region.
    Passing them explicitly is better for production: auto-selection can shift
    if AWS changes zone ordering, which would move your subnets.
  EOT
  type        = list(string)
  default     = []
}

variable "az_count" {
  description = "How many AZs to auto-select when availability_zones is empty. Ignored otherwise."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2. Load balancers require two Availability Zones."
  }
}

variable "public_subnet_cidrs" {
  description = "One CIDR per AZ for public subnets. Empty list disables public subnets entirely."
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "One CIDR per AZ for private subnets. Empty list disables private subnets entirely."
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Give private subnets outbound internet access via NAT.
    COST WARNING: ~$32/month per NAT Gateway plus $0.045/GB. This is usually the
    largest line item on a small AWS bill. Leave false unless your private
    instances genuinely need to reach the internet.
  EOT
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = <<-EOT
    Put one NAT Gateway in the first AZ and route every private subnet through it.
    Saves ~$32/month per additional AZ, but the NAT becomes a single point of
    failure and you pay cross-AZ data transfer. true for dev, false for production.
  EOT
  type        = bool
  default     = true
}

variable "enable_s3_gateway_endpoint" {
  description = "Add a free S3 Gateway Endpoint so private subnets reach S3 without a NAT Gateway. Costs nothing; enable it by default."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Required by load balancers and most AWS services. Leave true."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Send VPC Flow Logs to CloudWatch. Costs CloudWatch ingestion (~$0.50/GB) but is invaluable for debugging connectivity and for audits."
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "How long to keep flow logs. Only used when enable_flow_logs is true."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags merged onto every resource created here."
  type        = map(string)
  default     = {}
}
