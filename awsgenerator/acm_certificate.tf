###############################################################################
# ACM certificate for use with an Application / Network Load Balancer
#
# Usage with an HTTPS listener (same module or another stack):
#
#   certificate_arn = aws_acm_certificate_validation.this.certificate_arn
#
#   resource "aws_lb_listener" "https" {
#     load_balancer_arn = aws_lb.this.arn
#     port              = 443
#     protocol          = "HTTPS"
#     ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#     certificate_arn   = aws_acm_certificate_validation.this.certificate_arn
#     ...
#   }
#
# Notes
# - The certificate MUST be in the same AWS region as the load balancer.
# - For CloudFront, request the cert in us-east-1 instead.
# - Output the validated ARN (aws_acm_certificate_validation) so the listener
#   is not created until ACM has issued the certificate.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "domain_name" {
  description = "Primary domain name for the certificate (e.g. example.com or app.example.com)."
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional names on the certificate. Include a wildcard (e.g. *.example.com) if the ALB serves multiple hostnames."
  type        = list(string)
  default     = []
}

variable "route53_zone_name" {
  description = "Public Route 53 hosted zone name used for DNS validation (usually the apex, e.g. example.com)."
  type        = string
}

variable "route53_zone_id" {
  description = "Optional explicit hosted zone ID. If empty, the zone is looked up by route53_zone_name."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the ACM certificate."
  type        = map(string)
  default     = {}
}

data "aws_route53_zone" "this" {
  count        = var.route53_zone_id == "" ? 1 : 0
  name         = var.route53_zone_name
  private_zone = false
}

locals {
  zone_id = var.route53_zone_id != "" ? var.route53_zone_id : data.aws_route53_zone.this[0].zone_id
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = merge(var.tags, {
    Name = var.domain_name
  })

  # Required so a replacement cert is issued before the old one is destroyed.
  # Prevents HTTPS listener downtime during domain / SAN changes.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.zone_id
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

# Use this output as certificate_arn on aws_lb_listener (HTTPS / TLS).
output "certificate_arn" {
  description = "ARN of the issued ACM certificate. Use this on the load balancer HTTPS/TLS listener."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "certificate_domain_name" {
  description = "Primary domain name on the certificate."
  value       = aws_acm_certificate.this.domain_name
}

output "certificate_status" {
  description = "ACM certificate status after validation completes."
  value       = aws_acm_certificate.this.status
}
