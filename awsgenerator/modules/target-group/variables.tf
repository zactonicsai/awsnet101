variable "name" {
  description = "Name prefix. AWS caps target group name_prefix at SIX characters, so this module truncates automatically."
  type        = string
}

variable "vpc_id" {
  description = "EXISTING VPC ID. Must be the same VPC as the targets, or registration fails."
  type        = string
}

variable "port" {
  description = "Port the load balancer uses to reach targets. Need not match the public listener port -- port 80 outside, 8080 inside is completely normal."
  type        = number
  default     = 80
}

variable "protocol" {
  description = "HTTP or HTTPS from the load balancer to the targets. HTTP is fine inside a VPC; use HTTPS if you must encrypt internal hops too."
  type        = string
  default     = "HTTP"
}

variable "target_type" {
  description = <<-EOT
    "instance" -- register EC2 instance IDs. What an ASG uses.
    "ip"       -- register IP addresses. Containers, Fargate, on-prem via VPN.
    "lambda"   -- invoke a Lambda function. No servers at all.
    "alb"      -- chain an ALB behind a Network Load Balancer.
  EOT
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["instance", "ip", "lambda", "alb"], var.target_type)
    error_message = "target_type must be one of: instance, ip, lambda, alb."
  }
}

# --- Health check ------------------------------------------------------------

variable "health_check_path" {
  description = "URL the load balancer requests. Point it at an endpoint that verifies real dependencies -- a static page passes even when your database is down."
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "HTTP codes counting as healthy. \"200\" is strict; \"200-299\" is more forgiving. Anything outside this range means the target is treated as dead even while running perfectly."
  type        = string
  default     = "200"
}

variable "health_check_interval" {
  description = "Seconds between checks. Lower reacts faster but generates more traffic."
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds to wait for a response before counting it a failure. Must be less than health_check_interval."
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Consecutive passes before traffic resumes to a target."
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Consecutive failures before traffic stops. 2 with a 30s interval means a dead server is out of rotation within ~60 seconds."
  type        = number
  default     = 2
}

variable "health_check_port" {
  description = "\"traffic-port\" reuses the serving port. Override only if health checks live on a separate management port."
  type        = string
  default     = "traffic-port"
}

# --- Behaviour ---------------------------------------------------------------

variable "deregistration_delay" {
  description = <<-EOT
    Seconds to let in-flight requests finish before removing a target.

    AWS defaults to 300, which makes deploys and `terraform destroy` feel
    frozen. Set it just above your slowest request: too low cuts users off
    mid-request, too high slows every deployment.
  EOT
  type        = number
  default     = 30
}

variable "stickiness_enabled" {
  description = "Send a returning visitor back to the same target via a cookie. Needed for session state held in server memory; leave off for stateless apps so load spreads evenly."
  type        = bool
  default     = false
}

variable "stickiness_duration" {
  description = "Seconds a stickiness cookie lasts. Default is one day."
  type        = number
  default     = 86400
}

variable "slow_start_duration" {
  description = "Seconds over which a new target ramps up to full share of traffic. Useful for JIT-compiled apps (JVM, .NET) that are slow while warming. 0 disables; valid range is 30-900."
  type        = number
  default     = 0
}

variable "load_balancing_algorithm" {
  description = "\"round_robin\" spreads evenly. \"least_outstanding_requests\" favours idle targets and is better when request durations vary a lot."
  type        = string
  default     = "round_robin"
}

variable "tags" {
  description = "Tags for the target group."
  type        = map(string)
  default     = {}
}
