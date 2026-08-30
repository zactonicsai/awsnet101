# =============================================================================
# MODULE: network-acl
# -----------------------------------------------------------------------------
# A Network ACL is a firewall at the SUBNET boundary, evaluated before traffic
# ever reaches a security group. It is a second, coarser layer of defence.
#
# THE THREE DIFFERENCES FROM A SECURITY GROUP -- internalise these:
#
#   1. STATELESS. A security group remembers that you allowed a request in and
#      lets the reply out automatically. A NACL does not. Every conversation
#      needs rules in BOTH directions, including the ephemeral high ports that
#      replies arrive on.
#
#   2. NUMBERED, FIRST MATCH WINS. Rules are evaluated lowest number first and
#      evaluation STOPS at the first match. A deny at 100 beats an allow at 200.
#      Security groups evaluate every rule together and have no ordering.
#
#   3. SUPPORTS DENY. Security groups can only allow. NACLs can explicitly
#      block, which makes them the right tool for blanket bans (an abusive IP
#      range) that you do not want to encode in every security group.
#
# WHEN TO USE ONE: as defence in depth, or for coarse subnet-wide blocking.
# Day-to-day access control belongs in security groups -- they are stateful,
# they reference each other, and they are far harder to get subtly wrong.
# =============================================================================

resource "aws_network_acl" "this" {
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = var.name })
}

# Associating a subnet REPLACES its current ACL. A subnet always has exactly
# one, defaulting to the VPC's permissive default ACL.
resource "aws_network_acl_association" "this" {
  count = length(var.subnet_ids)

  network_acl_id = aws_network_acl.this.id
  subnet_id      = var.subnet_ids[count.index]
}

resource "aws_network_acl_rule" "ingress" {
  for_each = var.ingress_rules

  network_acl_id = aws_network_acl.this.id
  rule_number    = each.value.rule_number
  egress         = false
  rule_action    = each.value.action
  protocol       = each.value.protocol

  # Ports are meaningless for protocol "-1" (all traffic) and AWS rejects them.
  from_port = contains(["-1", "icmp", "icmpv6"], tostring(each.value.protocol)) ? null : each.value.from_port
  to_port   = contains(["-1", "icmp", "icmpv6"], tostring(each.value.protocol)) ? null : each.value.to_port

  cidr_block      = each.value.cidr_block
  ipv6_cidr_block = each.value.ipv6_cidr_block

  icmp_type = each.value.icmp_type
  icmp_code = each.value.icmp_code
}

resource "aws_network_acl_rule" "egress" {
  for_each = var.egress_rules

  network_acl_id = aws_network_acl.this.id
  rule_number    = each.value.rule_number
  egress         = true
  rule_action    = each.value.action
  protocol       = each.value.protocol

  from_port = contains(["-1", "icmp", "icmpv6"], tostring(each.value.protocol)) ? null : each.value.from_port
  to_port   = contains(["-1", "icmp", "icmpv6"], tostring(each.value.protocol)) ? null : each.value.to_port

  cidr_block      = each.value.cidr_block
  ipv6_cidr_block = each.value.ipv6_cidr_block

  icmp_type = each.value.icmp_type
  icmp_code = each.value.icmp_code
}

# -----------------------------------------------------------------------------
# Ephemeral port rules -- the ones everybody forgets
# -----------------------------------------------------------------------------
# When an instance opens a connection out, the operating system picks a random
# source port in the high range and the reply comes back to THAT port. A
# stateless NACL sees that reply as brand-new inbound traffic and drops it
# unless a rule allows it. Symptom: yum/dnf hangs, curl hangs, nothing errors.
#
# Linux uses 32768-60999; AWS NAT Gateways use 1024-65535. We allow the wider
# range so both work.
resource "aws_network_acl_rule" "ephemeral_ingress" {
  count = var.add_ephemeral_ingress_rule ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = var.ephemeral_rule_number
  egress         = false
  rule_action    = "allow"
  protocol       = "tcp"
  from_port      = 1024
  to_port        = 65535
  cidr_block     = var.ephemeral_cidr
}

resource "aws_network_acl_rule" "ephemeral_egress" {
  count = var.add_ephemeral_egress_rule ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = var.ephemeral_rule_number
  egress         = true
  rule_action    = "allow"
  protocol       = "tcp"
  from_port      = 1024
  to_port        = 65535
  cidr_block     = var.ephemeral_cidr
}
