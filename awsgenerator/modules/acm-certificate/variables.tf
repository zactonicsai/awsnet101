variable "domain_name" {
  description = "Primary domain, e.g. \"app.example.com\". Use \"*.example.com\" for a wildcard covering every direct subdomain."
  type        = string
}

variable "subject_alternative_names" {
  description = "Extra domains on the same certificate, e.g. [\"www.example.com\", \"api.example.com\"]."
  type        = list(string)
  default     = []
}

variable "hosted_zone_id" {
  description = <<-EOT
    EXISTING Route 53 hosted zone ID where validation records are written.
    Pass module.dns_zone.zone_id, or look up a zone you already own with the
    aws_route53_zone data source.

    Create hosted zones BY HAND, once. Creating one assigns four random
    nameservers you must copy to your registrar; if automation ever recreates
    the zone you get four different ones and your domain goes dark.
  EOT
  type        = string
}

variable "validation_method" {
  description = "\"DNS\" validates automatically and renews forever without human involvement. \"EMAIL\" requires someone to click a link every renewal. Always use DNS."
  type        = string
  default     = "DNS"
}

variable "wait_for_validation" {
  description = "Block `terraform apply` until the certificate is issued. Keep true -- a load balancer cannot attach a PENDING_VALIDATION certificate, so continuing early just fails later."
  type        = bool
  default     = true
}

variable "key_algorithm" {
  description = "\"RSA_2048\" is universally compatible. \"EC_prime256v1\" is faster and smaller but rejected by some very old clients."
  type        = string
  default     = "RSA_2048"
}

variable "tags" {
  description = "Tags for the certificate."
  type        = map(string)
  default     = {}
}
