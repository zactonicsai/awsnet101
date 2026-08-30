variable "name" {
  description = "Name prefix for the security group. A random suffix is appended so the group can be replaced without a name clash."
  type        = string
}

variable "description" {
  description = "What this group is for. Shows in the console. AWS will not let you change this later without replacing the group."
  type        = string
  default     = "Managed by Terraform"
}

variable "vpc_id" {
  description = "EXISTING VPC to create the group in. Pass module.vpc.vpc_id, or a literal ID for a VPC you already have."
  type        = string
}

variable "ingress_rules" {
  description = <<-EOT
    Inbound rules, keyed by a stable name you choose. The key becomes the
    for_each key, so renaming a key destroys and recreates that one rule.

    Give EXACTLY ONE source per rule:
      cidr_ipv4                    = "0.0.0.0/0"
      cidr_ipv6                    = "::/0"
      prefix_list_id               = "pl-xxxx"       (e.g. a CloudFront managed list)
      referenced_security_group_id = "sg-xxxx"       (preferred -- see the README)
      self                         = true            (other members of this same group)

    Example:
      ingress_rules = {
        http_from_internet = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" }
        app_from_alb       = { from_port = 8080, to_port = 8080, referenced_security_group_id = module.alb_sg.security_group_id }
      }
  EOT
  type = map(object({
    description                  = optional(string)
    from_port                    = number
    to_port                      = number
    ip_protocol                  = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
  }))
  default = {}

  validation {
    # Exactly one source must be set. Zero sources creates an invalid rule;
    # more than one is silently ignored by AWS in confusing ways.
    condition = alltrue([
      for k, r in var.ingress_rules :
      length(compact([
        try(r.cidr_ipv4, null),
        try(r.cidr_ipv6, null),
        try(r.prefix_list_id, null),
        try(r.referenced_security_group_id, null),
        try(r.self, false) ? "self" : null,
      ])) == 1
    ])
    error_message = "Each ingress rule needs exactly one of: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, or self = true."
  }
}

variable "egress_rules" {
  description = <<-EOT
    Outbound rules, same shape as ingress_rules.

    NOTE: leaving this empty means NO outbound access at all. That is often
    correct and is the tightest possible setting -- security groups are
    stateful, so replies to allowed inbound traffic still work. Set
    allow_all_egress = true if the workload needs to reach out.
  EOT
  type = map(object({
    description                  = optional(string)
    from_port                    = number
    to_port                      = number
    ip_protocol                  = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, r in var.egress_rules :
      length(compact([
        try(r.cidr_ipv4, null),
        try(r.cidr_ipv6, null),
        try(r.prefix_list_id, null),
        try(r.referenced_security_group_id, null),
        try(r.self, false) ? "self" : null,
      ])) == 1
    ])
    error_message = "Each egress rule needs exactly one of: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, or self = true."
  }
}

variable "allow_all_egress" {
  description = "Convenience switch adding a single allow-everything-outbound rule. Common for app servers that call APIs; skip it for locked-down tiers."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for the security group."
  type        = map(string)
  default     = {}
}
