output "alb_arn" {
  description = "Load balancer ARN."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "The load balancer's own AWS hostname. Always works, even without a custom domain -- test with this before blaming DNS."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = <<-EOT
    The load balancer's hidden Route 53 hosted zone ID.

    This is NOT your domain's zone ID. It is what an ALIAS record's
    AliasTarget requires, and confusing the two is the most common Route 53
    mistake there is. Pass it to the route53-record module as alias_zone_id.
  EOT
  value       = aws_lb.this.zone_id
}

output "arn_suffix" {
  description = "ARN suffix, e.g. app/my-alb/1234567890. Needed by CloudWatch metrics and ALBRequestCountPerTarget scaling."
  value       = aws_lb.this.arn_suffix
}

output "http_listener_arn" {
  description = "HTTP listener ARN, or null when disabled. Attach further rules to it from outside this module."
  value       = try(aws_lb_listener.http[0].arn, null)
}

output "https_listener_arn" {
  description = "HTTPS listener ARN, or null when no certificate was supplied."
  value       = try(aws_lb_listener.https[0].arn, null)
}

output "url" {
  description = "Ready-to-open URL using the load balancer's own hostname."
  value       = local.https_enabled ? "https://${aws_lb.this.dns_name}" : "http://${aws_lb.this.dns_name}"
}
