# =============================================================================
# security.tf
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# Security Groups are firewalls that wrap around individual resources.
# Think of a subnet as a street, and a security group as the locked front door
# of one specific house on that street.
#
# TWO RULES TO MEMORIZE:
#   1. Security groups DENY everything by default. You only write "allow" rules.
#   2. They are STATEFUL. If you allow a request in, the reply is automatically
#      allowed back out. You never write a rule for the response.
#
# THE PATTERN BELOW IS THE MOST IMPORTANT SECURITY IDEA IN THIS WHOLE TUTORIAL:
# the server's firewall does not say "allow 10.0.0.0/24". It says
# "allow the load balancer's security group". This is called SG-to-SG
# referencing, and it means only that exact load balancer can ever connect -
# even if someone later launches a rogue server on the same street.
# COST: $0. Security groups are free.
# =============================================================================

# -----------------------------------------------------------------------------
# LOAD BALANCER SECURITY GROUP - the public-facing front door
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Allows web traffic from the internet into the load balancer"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-alb-sg"
  }

  # create_before_destroy avoids a classic Terraform deadlock: AWS refuses to
  # delete a security group that is still attached to something, so we create
  # the replacement first, move the attachment, then delete the old one.
  lifecycle {
    create_before_destroy = true
  }
}

# Modern best practice is one resource PER RULE (not inline ingress blocks).
# Separate rule resources can be changed without recreating the whole group,
# and they show up individually in `terraform plan` so you can see exactly
# what is opening or closing.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  # for_each loops over the list of allowed sources, making one rule each.
  # toset() converts the list into a set, which for_each requires.
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "Allow inbound HTTP from ${each.value}"

  cidr_ipv4   = each.value # normally 0.0.0.0/0 = the whole internet
  from_port   = 80         # start of the port range
  to_port     = 80         # end of the port range (same = just port 80)
  ip_protocol = "tcp"
}

# The load balancer must be allowed to START connections to your servers.
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow the ALB to reach the app servers on the app port"

  # referenced_security_group_id targets a GROUP, not an IP range.
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# -----------------------------------------------------------------------------
# APPLICATION SECURITY GROUP - wraps the private servers
# -----------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name_prefix = "${var.project_name}-app-"
  description = "Only the load balancer may talk to these servers"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# THE KEY RULE. Read it out loud:
# "Allow TCP port 8080 inbound, but only from things wearing the ALB's badge."
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id
  description       = "Allow app traffic ONLY from the load balancer"

  referenced_security_group_id = aws_security_group.alb.id # <-- not a CIDR!
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# NOTE ON OUTBOUND: we deliberately give the app servers NO egress rules at all.
# They cannot start a connection to anything. They can still REPLY to the load
# balancer because security groups are stateful. This is the tightest possible
# setting and it works here because our server needs zero downloads to run.
# In a real app that calls a database or an API, you would add a narrow egress
# rule pointing at that specific destination.
