output "record_fqdns" {
  description = "Map of record key to fully-qualified domain name."
  value       = { for k, r in aws_route53_record.this : k => r.fqdn }
}

output "record_names" {
  description = "Map of record key to record name."
  value       = { for k, r in aws_route53_record.this : k => r.name }
}

output "urls" {
  description = "Convenience https:// URLs for each record."
  value       = { for k, r in aws_route53_record.this : k => "https://${r.fqdn}" }
}
