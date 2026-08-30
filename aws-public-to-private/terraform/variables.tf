# =============================================================================
# variables.tf
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# Variables are the "settings knobs" of the project. Instead of hard-coding the
# region or the instance size in ten different files, we declare them once here
# and refer to them everywhere as var.<name>.
#
# You set their real values in terraform.tfvars (copy the .example file).
# =============================================================================

variable "aws_region" {
  description = "AWS region to build everything in. Must have at least 2 Availability Zones (all normal regions do)."
  type        = string
  default     = "us-east-1" # us-east-1 is usually the cheapest region.
}

variable "project_name" {
  description = "Short name glued onto every resource so you can find and delete them later."
  type        = string
  default     = "web-demo"

  # Validation blocks stop bad input BEFORE Terraform calls AWS.
  # AWS resource names dislike spaces and capital letters, so we enforce that.
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "project_name must be 3-20 characters, lowercase letters, numbers and hyphens only."
  }
}

variable "environment" {
  description = "Environment label used only for tagging (dev / test / prod)."
  type        = string
  default     = "dev"
}

# ---------------------------------------------------------------------------
# NETWORK SIZING
# ---------------------------------------------------------------------------
# CIDR is just a way of writing "a block of IP addresses".
# 10.0.0.0/16 means: every address from 10.0.0.0 to 10.0.255.255 (~65,000 IPs).
# The number after the slash is how many bits are LOCKED. Bigger number = smaller
# block. /16 is a big neighborhood, /24 is one street with 256 houses.

variable "vpc_cidr" {
  description = "Address range for the whole private network (VPC)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = <<-EOT
    Two PUBLIC streets - one per Availability Zone.
    The load balancer lives here because it must be reachable from the internet.
    An Application Load Balancer REQUIRES at least 2 subnets in 2 different AZs.
  EOT
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "You must supply at least 2 public subnet CIDRs (ALB requires 2 Availability Zones)."
  }
}

variable "private_subnet_cidrs" {
  description = <<-EOT
    Two PRIVATE streets - one per Availability Zone.
    Your actual servers live here. They have NO route to the internet, so nobody
    on the internet can reach them directly. Only the load balancer can.
  EOT
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "You must supply at least 2 private subnet CIDRs (one per AZ)."
  }
}

# ---------------------------------------------------------------------------
# COMPUTE (the actual little web servers)
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = <<-EOT
    Size of the virtual machine.
    t4g.nano  = ARM/Graviton, ~$3.07/month  <-- cheapest, our default
    t3.micro  = Intel, FREE for 750 hrs/month in the 12-month Free Tier
    Set this to t3.micro if your account is still inside the Free Tier window.
  EOT
  type        = string
  default     = "t4g.nano"
}

variable "instance_count" {
  description = <<-EOT
    How many servers to run behind the load balancer.
    1 = absolute cheapest (good for learning).
    2 = one per Availability Zone, survives an AZ outage (real production choice).
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 4
    error_message = "instance_count must be between 1 and 4 for this tutorial."
  }
}

variable "app_port" {
  description = "TCP port the tiny Python web server listens on inside the private subnet."
  type        = number
  default     = 8080
}

variable "response_text" {
  description = "The plain text your website will return with HTTP status 200."
  type        = string
  default     = "It works!"
}

# ---------------------------------------------------------------------------
# SECURITY
# ---------------------------------------------------------------------------

variable "allowed_ingress_cidrs" {
  description = <<-EOT
    Who is allowed to reach the load balancer on port 80.
    0.0.0.0/0 means THE ENTIRE INTERNET - correct for a public website.
    For a private test, put your own IP here instead, like ["203.0.113.45/32"].
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# DNS (the friendly URL)
# ---------------------------------------------------------------------------

variable "enable_dns" {
  description = <<-EOT
    Set to true ONLY if you already own a domain name and have a Route 53
    PUBLIC hosted zone for it. If false, you still get a working URL - the
    load balancer's own long AWS hostname.
  EOT
  type        = bool
  default     = false
}

variable "hosted_zone_name" {
  description = "Your existing Route 53 public hosted zone, e.g. \"example.com\". Leave blank if enable_dns = false."
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "The friendly name in front of your domain. \"app\" produces app.example.com."
  type        = string
  default     = "app"
}
