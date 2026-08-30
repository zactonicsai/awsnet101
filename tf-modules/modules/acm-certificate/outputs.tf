output "certificate_arn" {
  description = <<-EOT
    Certificate ARN, safe to attach to a listener.

    When wait_for_validation is true this deliberately returns the ARN from the
    VALIDATION resource, not the certificate resource. Both are the same string,
    but routing through the validation resource forces Terraform to wait for
    issuance before creating the listener -- otherwise the listener is created
    first and fails with a certificate-not-issued error.
  EOT
  value       = var.wait_for_validation && var.validation_method == "DNS" ? aws_acm_certificate_validation.this[0].certificate_arn : aws_acm_certificate.this.arn
}

output "certificate_id" {
  description = "Certificate ID."
  value       = aws_acm_certificate.this.id
}

output "domain_name" {
  description = "Primary domain on the certificate."
  value       = aws_acm_certificate.this.domain_name
}

output "status" {
  description = "Certificate status, e.g. ISSUED or PENDING_VALIDATION."
  value       = aws_acm_certificate.this.status
}

output "validation_record_fqdns" {
  description = "The validation records created. These must STAY in place -- delete them and automatic renewal silently stops working, which you discover when the certificate expires."
  value       = [for r in aws_route53_record.validation : r.fqdn]
}
