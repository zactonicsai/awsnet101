variable "aws_region" {
  description = "Region to build in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for everything. Keep it short -- it is combined with resource-specific suffixes."
  type        = string
  default     = "keycloak"
}

variable "environment" {
  description = "Tag value only."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC address range."
  type        = string
  default     = "10.20.0.0/16"
}

variable "instance_type" {
  description = <<-EOT
    Keycloak is a JVM application and needs real memory. t4g.nano (512 MB) will
    NOT start it. t4g.small (2 GB) is the realistic minimum; t4g.medium is
    comfortable. This is one place where the cheapest option genuinely does not
    work rather than merely being slow.
  EOT
  type        = string
  default     = "t4g.small"
}

variable "keycloak_image" {
  description = "Container image. Pin an explicit version -- \"latest\" means a future instance refresh silently upgrades you across a major version."
  type        = string
  default     = "quay.io/keycloak/keycloak:26.0"
}

variable "keycloak_http_port" {
  description = "Port Keycloak serves application traffic on."
  type        = number
  default     = 8080
}

variable "keycloak_management_port" {
  description = "Keycloak's separate management port. Health and metrics endpoints live HERE, not on the HTTP port -- the target group must check this one."
  type        = number
  default     = 9000
}

variable "db_instance_class" {
  description = "RDS size. db.t4g.micro (~$12/mo) is fine for testing."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Database Keycloak stores its realms and users in."
  type        = string
  default     = "keycloak"
}

variable "hostname_url" {
  description = <<-EOT
    Public URL users reach Keycloak on, e.g. "https://sso.example.com".

    Leave empty to use the load balancer's own hostname, which is fine for
    testing. Keycloak builds redirect URLs from this value, so if it is wrong
    every login bounces somewhere unreachable.
  EOT
  type        = string
  default     = ""
}

variable "allowed_cidr" {
  description = "Who may reach the load balancer. An identity provider is a high-value target -- restrict this to your office or VPN range in anything real."
  type        = string
  default     = "0.0.0.0/0"
}

variable "desired_capacity" {
  description = <<-EOT
    Number of Keycloak instances.

    Keep this at 1 unless you have configured Infinispan clustering. Multiple
    unclustered Keycloak nodes do not share session state, so users get logged
    out at random as the load balancer moves them between instances. Sticky
    sessions (enabled on the target group below) mitigate but do not fix this.
  EOT
  type        = number
  default     = 1
}

variable "max_size" {
  description = "ASG ceiling. Must exceed desired_capacity to allow rolling instance refresh."
  type        = number
  default     = 2
}

variable "enable_nacls" {
  description = "Attach Network ACLs as a second, subnet-level firewall layer on top of the security groups."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Protect the database and load balancer from accidental deletion. Turn on for anything holding real user accounts."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags merged onto everything."
  type        = map(string)
  default     = {}
}
