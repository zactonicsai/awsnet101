variable "name" {
  description = "Name for the network ACL."
  type        = string
}

variable "vpc_id" {
  description = "EXISTING VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = <<-EOT
    EXISTING subnet IDs to associate. Associating a subnet REPLACES whatever
    ACL it had (usually the permissive default), so the rules below become the
    only thing standing between that subnet and the wire. Get them right before
    you associate anything you care about.
  EOT
  type        = list(string)
  default     = []
}

variable "ingress_rules" {
  description = <<-EOT
    Inbound rules, keyed by a stable name.

    rule_number decides evaluation order: LOWEST FIRST, and the first match
    wins. Leave gaps (100, 200, 300) so you can insert later without renumbering.

    Example:
      ingress_rules = {
        http      = { rule_number = 100, from_port = 80,   to_port = 80,    cidr_block = "0.0.0.0/0" }
        ephemeral = { rule_number = 200, from_port = 1024, to_port = 65535, cidr_block = "0.0.0.0/0" }
      }
  EOT
  type = map(object({
    rule_number     = number
    action          = optional(string, "allow")
    protocol        = optional(string, "tcp")
    from_port       = optional(number)
    to_port         = optional(number)
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, r in var.ingress_rules : r.rule_number >= 1 && r.rule_number <= 32766
    ])
    error_message = "rule_number must be between 1 and 32766. Rule 32767 is the implicit DENY ALL and cannot be redefined."
  }

  validation {
    condition = alltrue([
      for k, r in var.ingress_rules : contains(["allow", "deny"], r.action)
    ])
    error_message = "action must be allow or deny."
  }

  validation {
    condition = alltrue([
      for k, r in var.ingress_rules :
      contains(["-1", "icmp", "icmpv6"], tostring(r.protocol)) || (r.from_port != null && r.to_port != null)
    ])
    error_message = "TCP and UDP rules require both from_port and to_port. Only protocol \"-1\" (all) may omit them."
  }
}

variable "egress_rules" {
  description = <<-EOT
    Outbound rules, same shape as ingress_rules.

    NACLs are STATELESS, so outbound rules are NOT optional. Unlike a security
    group, the reply to an allowed inbound request is a separate packet that
    must be permitted by an egress rule of its own. Forgetting this is the
    single most common NACL mistake: connections appear to hang rather than
    fail, because the request arrives and the answer is silently dropped.
  EOT
  type = map(object({
    rule_number     = number
    action          = optional(string, "allow")
    protocol        = optional(string, "tcp")
    from_port       = optional(number)
    to_port         = optional(number)
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, r in var.egress_rules : r.rule_number >= 1 && r.rule_number <= 32766
    ])
    error_message = "rule_number must be between 1 and 32766."
  }
}

variable "add_ephemeral_ingress_rule" {
  description = <<-EOT
    Auto-add an inbound rule for TCP 1024-65535 from ephemeral_cidr.

    WHY YOU ALMOST ALWAYS NEED THIS: when something inside the subnet makes an
    outbound request, the reply comes back to a random high-numbered port. With
    a stateless NACL that reply is inbound traffic and needs an inbound rule.
    Without it, package installs and API calls hang forever.
  EOT
  type        = bool
  default     = true
}

variable "add_ephemeral_egress_rule" {
  description = "Auto-add an outbound rule for TCP 1024-65535, which is how replies to inbound requests leave. Same reasoning as above, mirrored."
  type        = bool
  default     = true
}

variable "ephemeral_cidr" {
  description = "Source/destination for the auto-added ephemeral rules. 0.0.0.0/0 is normal; narrow it to your VPC CIDR for internal-only subnets."
  type        = string
  default     = "0.0.0.0/0"
}

variable "ephemeral_rule_number" {
  description = "Rule number for the auto-added ephemeral rules. High by default so your explicit rules are evaluated first."
  type        = number
  default     = 900
}

variable "tags" {
  description = "Tags for the network ACL."
  type        = map(string)
  default     = {}
}
