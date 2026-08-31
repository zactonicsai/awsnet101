variable "name" {
  description = "Base name for the load balancer and its target group. Must be <= 28 chars (the module appends '-tg')."
  type        = string
}

variable "vpc_id" {
  description = "VPC that the target group lives in. Must be the same VPC as the subnets and instances."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the ALB is placed in. Supplied by the caller. Needs at least two subnets in two different Availability Zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An Application Load Balancer requires at least two subnets in different Availability Zones."
  }
}

variable "security_group_ids" {
  description = "Security groups attached to the ALB. Supplied by the caller. Should allow inbound on listener_port."
  type        = list(string)
}

variable "internal" {
  description = "true = internal (private) ALB, false = internet-facing."
  type        = bool
  default     = false
}

variable "listener_port" {
  description = "Port the ALB listens on for client traffic."
  type        = number
  default     = 80
}

variable "target_port" {
  description = "Port on the EC2 instances that the ALB forwards to."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "URL path the ALB requests to decide if a target is healthy."
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "HTTP status codes counted as healthy, e.g. \"200\" or \"200-299\"."
  type        = string
  default     = "200"
}

variable "health_check_interval" {
  description = "Seconds between health checks."
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds to wait for a health check response before it counts as failed."
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Consecutive successful checks before a target is marked healthy."
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Consecutive failed checks before a target is marked unhealthy."
  type        = number
  default     = 2
}

variable "deregistration_delay" {
  description = "Seconds the ALB waits for in-flight requests to finish before removing a target."
  type        = number
  default     = 60
}

variable "idle_timeout" {
  description = "Seconds an idle connection is kept open."
  type        = number
  default     = 60
}

variable "enable_deletion_protection" {
  description = "Blocks 'terraform destroy' of the ALB when true. Keep false for demos."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
