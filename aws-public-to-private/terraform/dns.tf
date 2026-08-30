# =============================================================================
# dns.tf
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# The load balancer already works, but its address is an ugly machine-generated
# name like:
#     web-demo-alb-1234567890.us-east-1.elb.amazonaws.com
# DNS is the internet's phone book. This file adds an entry so people can type
# a friendly name like app.example.com instead.
#
# EVERYTHING HERE IS OPTIONAL. If enable_dns = false, none of it is created and
# your site still works at the long AWS name.
# =============================================================================

# -----------------------------------------------------------------------------
# LOOK UP YOUR EXISTING HOSTED ZONE
# -----------------------------------------------------------------------------
# A "hosted zone" is a container holding all DNS records for one domain.
#
# WHY WE LOOK IT UP INSTEAD OF CREATING IT - this is important:
# When you create a hosted zone, AWS assigns it 4 random nameservers, and you
# must copy those to your domain registrar. If Terraform ever destroys and
# recreates the zone, you get 4 BRAND NEW nameservers and your domain goes dark
# until you manually update the registrar again. So: create the zone ONCE, by
# hand, and let Terraform only manage the records inside it. This is the
# standard professional pattern.
#
# COST: $0.50 per hosted zone per month, plus $0.40 per million queries.
# Alias records pointing at AWS resources are queried for FREE.
data "aws_route53_zone" "main" {
  # count with a ternary is Terraform's way of saying "only if".
  # If enable_dns is true, make 1 of these. If false, make 0.
  count = var.enable_dns ? 1 : 0

  name = var.hosted_zone_name
  # private_zone = false means we want the PUBLIC zone (visible to the whole
  # internet), not a private one that only resolves inside a VPC.
  private_zone = false
}

# -----------------------------------------------------------------------------
# THE DNS RECORD ITSELF
# -----------------------------------------------------------------------------
resource "aws_route53_record" "app" {
  count = var.enable_dns ? 1 : 0

  # [0] because the data source above is a list (thanks to count).
  zone_id = data.aws_route53_zone.main[0].zone_id

  # The full name people will type, e.g. "app" + "." + "example.com"
  name = "${var.subdomain}.${var.hosted_zone_name}"

  # "A" is the record type that maps a name to an IPv4 address.
  type = "A"

  # --- WHY AN ALIAS RECORD AND NOT A CNAME --------------------------------
  # A load balancer has NO fixed IP address. AWS changes them whenever it
  # scales or replaces hardware. So you can never hard-code an IP.
  #
  # The old workaround was a CNAME (name -> another name), but a CNAME is
  # illegal at the root of a domain (you cannot CNAME example.com itself).
  #
  # An ALIAS is Amazon's own record type that solves both problems: it points
  # at an AWS resource, follows its address changes automatically, works at the
  # domain root, and costs nothing to query. For any AWS resource, always
  # prefer alias over CNAME.
  alias {
    name = aws_lb.main.dns_name

    # Every ALB lives in a special hidden hosted zone. This is NOT your zone ID -
    # it's AWS's internal one, and the ALB resource hands it to us directly.
    # Copying your own zone ID here is a very common and confusing mistake.
    zone_id = aws_lb.main.zone_id

    # Health checks at the DNS layer, on top of the ALB's own checks.
    # true is recommended and free for alias records.
    evaluate_target_health = true
  }
}
