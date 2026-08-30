# =============================================================================
# MODULE: security-group
# -----------------------------------------------------------------------------
# A generic, reusable security group. It creates NOTHING but the group and its
# rules -- the VPC is injected, and rule sources can reference security groups
# created elsewhere (including by another instance of this module).
#
# WHY ONE RESOURCE PER RULE:
# The old style used inline `ingress {}` blocks inside aws_security_group.
# Those force the whole group to be recomputed on any rule change, and they
# fight with rules added outside Terraform. The modern
# aws_vpc_security_group_*_rule resources are individually addressable, show up
# one-per-line in `terraform plan`, and can be changed without touching the
# group itself.
# =============================================================================

resource "aws_security_group" "this" {
  # name_prefix, not name. AWS cannot rename a security group in place, so a
  # fixed name plus create_before_destroy deadlocks: the replacement collides
  # with the original. A prefix lets AWS generate a unique suffix.
  name_prefix = "${var.name}-"
  description = var.description
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # Build the replacement, move attachments to it, then delete the old one.
    # Without this, replacing a group attached to a running instance fails.
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  security_group_id = aws_security_group.this.id
  description       = coalesce(each.value.description, each.key)

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.ip_protocol

  # Exactly one of these is non-null; the variable validation guarantees it.
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.egress_rules

  security_group_id = aws_security_group.this.id
  description       = coalesce(each.value.description, each.key)

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.ip_protocol

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id

  tags = var.tags
}

# Convenience: unrestricted outbound.
# ip_protocol = "-1" means every protocol, and AWS requires from_port/to_port
# to be omitted entirely in that case (not set to 0).
resource "aws_vpc_security_group_egress_rule" "allow_all" {
  count = var.allow_all_egress ? 1 : 0

  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = var.tags
}
