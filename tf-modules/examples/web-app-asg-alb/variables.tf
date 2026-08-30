variable "aws_region" {
  description = "Region to build in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for everything."
  type        = string
  default     = "web-demo"
}

variable "environment" {
  description = "Tag value only."
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "t4g.nano (~$3/mo) or t3.micro (free tier). Architecture is derived automatically."
  type        = string
  default     = "t4g.nano"
}

variable "app_port" {
  description = "Port the app listens on inside the private subnet."
  type        = number
  default     = 8080
}

variable "response_text" {
  description = "Text the site returns with status 200."
  type        = string
  default     = "It works!"
}

variable "allowed_cidr" {
  description = "Who may reach the load balancer. 0.0.0.0/0 is the whole internet; use YOUR_IP/32 for a private test."
  type        = string
  default     = "0.0.0.0/0"
}

variable "min_size" {
  description = "Minimum instances."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum instances. Also a cost ceiling."
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Starting instance count."
  type        = number
  default     = 2
}

variable "enable_dns" {
  description = "Only true if you already own a domain with a Route 53 public hosted zone."
  type        = bool
  default     = false
}

variable "hosted_zone_name" {
  description = "Your existing domain, e.g. example.com"
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Produces <subdomain>.<hosted_zone_name>"
  type        = string
  default     = "app"
}
