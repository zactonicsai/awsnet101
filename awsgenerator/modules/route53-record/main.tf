# =============================================================================
# MODULE: route53-record
# -----------------------------------------------------------------------------
# DNS records inside a hosted zone you already own. This module deliberately
# does NOT create hosted zones.
#
# WHY NOT: creating a zone assigns four random nameservers that you must copy
# to your domain registrar by hand. If automation ever destroys and recreates
# that zone, you get four DIFFERENT nameservers and your domain stops resolving
# entirely until someone updates the registrar again. Create zones once,
# manually. Automate only the records inside them.
#
# ALIAS vs CNAME -- why alias is nearly always right for AWS resources:
#
#   A record  points at an IP. A load balancer has NO fixed IP, so unusable.
#   CNAME     points at a name. Works, but is ILLEGAL at a zone root, so you
#             could never point example.com itself at your load balancer.
#   ALIAS     Amazon's own type. Follows the resource's changing IPs, is legal
#             at the root, and costs NOTHING to query.
# =============================================================================

resource "aws_route53_record" "this" {
  for_each = var.records

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type

  allow_overwrite = each.value.allow_overwrite

  # TTL and records are only valid on NON-alias records. AWS rejects the
  # request if you set them alongside an alias block, hence the conditionals.
  ttl     = each.value.alias_name == null ? each.value.ttl : null
  records = each.value.alias_name == null ? each.value.values : null

  dynamic "alias" {
    for_each = each.value.alias_name != null ? [1] : []
    content {
      name = each.value.alias_name

      # The TARGET resource's hosted zone, not yours. Every ALB lives in a
      # hidden AWS-owned zone and exposes its ID as an output. Passing your own
      # zone ID here is the single most common Route 53 mistake.
      zone_id = each.value.alias_zone_id

      # Free extra health checking on top of the load balancer's own.
      evaluate_target_health = each.value.evaluate_target_health
    }
  }
}
