variable "name" {
  description = "Name for the load balancer. Max 32 characters, alphanumerics and hyphens."
  type        = string
}

variable "subnet_ids" {
  description = <<-EOT
    EXISTING subnet IDs for the load balancer's network interfaces.

    Use PUBLIC subnets for an internet-facing load balancer, PRIVATE ones for
    an internal one. At least two, in two different AZs -- AWS refuses to build
    an ALB otherwise, and this requirement is not negotiable.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An Application Load Balancer requires at least 2 subnets in 2 different Availability Zones."
  }
}

variable "security_group_ids" {
  description = "EXISTING security group IDs controlling who may reach the load balancer."
  type        = list(string)
}

variable "internal" {
  description = <<-EOT
    false = internet-facing (public IPs, reachable from the internet).
    true  = internal (private IPs, reachable only from inside the VPC).

    This single boolean is the difference between a public and a private door.
  EOT
  type        = bool
  default     = false
}

variable "default_target_group_arn" {
  description = "EXISTING target group receiving traffic that matches no other rule. Leave null to serve default_fixed_response instead (useful before your app exists)."
  type        = string
  default     = null
}

variable "default_fixed_response" {
  description = "Static reply from the load balancer itself when no target group is set. Costs nothing and touches no server."
  type = object({
    content_type = optional(string, "text/plain")
    message_body = optional(string, "Not configured")
    status_code  = optional(string, "404")
  })
  default = {}
}

# --- HTTPS -------------------------------------------------------------------

variable "certificate_arn" {
  description = "EXISTING ACM certificate ARN. Supplying it creates an HTTPS listener on 443. Pass module.cert.certificate_arn."
  type        = string
  default     = null
}

variable "additional_certificate_arns" {
  description = "Extra certificates on the HTTPS listener for serving several domains from one load balancer (SNI)."
  type        = list(string)
  default     = []
}

variable "ssl_policy" {
  description = "TLS ciphers and versions to accept. The TLS13 policies are current best practice; use an older one only for genuinely ancient clients."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "redirect_http_to_https" {
  description = "When a certificate is supplied, make the port 80 listener issue a 301 redirect to HTTPS instead of serving traffic. Standard practice."
  type        = bool
  default     = true
}

variable "http_port" {
  description = "Plain HTTP listener port."
  type        = number
  default     = 80
}

variable "enable_http_listener" {
  description = "Create the HTTP listener at all. Set false for HTTPS-only."
  type        = bool
  default     = true
}

# --- Extra routing rules -----------------------------------------------------

variable "listener_rules" {
  description = <<-EOT
    Extra routing rules, keyed by name. Lower priority numbers are evaluated
    first; the default action runs only when nothing matches.

    Each rule needs exactly one action (forward OR fixed_response OR redirect)
    and at least one condition.

    Example -- a debug endpoint answered by the load balancer itself:
      listener_rules = {
        ping = {
          priority     = 100
          path_pattern = ["/ping"]
          fixed_response = { message_body = "pong", status_code = "200" }
        }
      }
  EOT
  type = map(object({
    priority         = number
    path_pattern     = optional(list(string))
    host_header      = optional(list(string))
    target_group_arn = optional(string)
    fixed_response = optional(object({
      content_type = optional(string, "text/plain")
      message_body = optional(string, "")
      status_code  = optional(string, "200")
    }))
    redirect = optional(object({
      host        = optional(string, "#{host}")
      path        = optional(string, "/#{path}")
      port        = optional(string, "443")
      protocol    = optional(string, "HTTPS")
      status_code = optional(string, "HTTP_301")
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, r in var.listener_rules :
      length(compact([
        try(r.target_group_arn, null),
        try(r.fixed_response, null) == null ? null : "fixed",
        try(r.redirect, null) == null ? null : "redirect",
      ])) == 1
    ])
    error_message = "Each listener rule needs exactly one action: target_group_arn, fixed_response, or redirect."
  }

  validation {
    condition = alltrue([
      for k, r in var.listener_rules :
      try(length(r.path_pattern), 0) > 0 || try(length(r.host_header), 0) > 0
    ])
    error_message = "Each listener rule needs at least one condition: path_pattern or host_header."
  }
}

# --- Behaviour ---------------------------------------------------------------

variable "enable_deletion_protection" {
  description = "Block deletion until someone turns this off. Set true in production so a stray destroy cannot take the site down."
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "Seconds an idle connection is held open. Raise for long-polling or slow uploads; a too-low value shows up as random 504s."
  type        = number
  default     = 60
}

variable "enable_http2" {
  description = "HTTP/2 support. Faster for browsers, no downside. Leave on."
  type        = bool
  default     = true
}

variable "drop_invalid_header_fields" {
  description = "Discard malformed headers instead of passing them to your app. Free protection against request-smuggling tricks."
  type        = bool
  default     = true
}

variable "access_logs_bucket" {
  description = "EXISTING S3 bucket for access logs. Null disables logging. You cannot debug traffic you did not record -- enable this in production."
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "Key prefix inside the access logs bucket."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for the load balancer and its listeners."
  type        = map(string)
  default     = {}
}
