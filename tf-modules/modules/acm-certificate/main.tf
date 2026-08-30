# =============================================================================
# MODULE: acm-certificate
# -----------------------------------------------------------------------------
# A free TLS certificate, validated automatically through DNS.
#
# WHY THIS IS ALMOST ALWAYS WORTH ADDING:
# ACM certificates cost NOTHING when used with a load balancer or CloudFront,
# and they RENEW THEMSELVES forever with no human involvement -- provided the
# validation records below stay in place. There is no good reason to run
# production on plain HTTP.
#
# REGION GOTCHA: a certificate must live in the SAME region as the load
# balancer using it. CloudFront is the exception -- it only accepts
# certificates from us-east-1. For CloudFront, pass an aliased provider:
#
#   module "cert" {
#     source    = "../../modules/acm-certificate"
#     providers = { aws = aws.us_east_1 }
#     ...
#   }
# =============================================================================

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = var.validation_method
  key_algorithm             = var.key_algorithm

  tags = merge(var.tags, { Name = var.domain_name })

  lifecycle {
    # A certificate attached to a listener cannot be deleted, so build the
    # replacement before removing the old one.
    create_before_destroy = true
  }
}

locals {
  # ACM asks for one CNAME record per distinct domain. Deduplicate first: a
  # certificate for example.com plus *.example.com produces two identical
  # validation options, and creating the same record twice is an error.
  validation_records = {
    for opt in aws_acm_certificate.this.domain_validation_options :
    opt.domain_name => {
      name  = opt.resource_record_name
      type  = opt.resource_record_type
      value = opt.resource_record_value
    }
  }
}

resource "aws_route53_record" "validation" {
  for_each = var.validation_method == "DNS" ? local.validation_records : {}

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60

  # Overwrite an existing record rather than failing. Re-running after a
  # partial apply is common, and without this you get a conflict error.
  allow_overwrite = true
}

# This resource creates nothing in AWS. It is a synchronisation point that
# blocks until ACM confirms the certificate is ISSUED, so anything depending on
# it can safely assume the certificate is usable.
resource "aws_acm_certificate_validation" "this" {
  count = var.validation_method == "DNS" && var.wait_for_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
