# =============================================================================
# outputs.tf
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# Outputs are the values Terraform prints when it finishes. They are how you
# get the URL you just built without hunting through the AWS console.
# You can also re-print them any time with:  terraform output
# =============================================================================

output "website_url" {
  description = "THE URL TO OPEN IN YOUR BROWSER. This is the answer to the whole tutorial."
  # If DNS was enabled, show the friendly name. Otherwise show the ALB's own name.
  value = var.enable_dns ? "http://${var.subdomain}.${var.hosted_zone_name}" : "http://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  description = "The load balancer's built-in AWS hostname. Always works, even without a domain."
  value       = aws_lb.main.dns_name
}

output "ping_url" {
  description = "Debug endpoint answered by the load balancer itself. If this works but website_url does not, the problem is your servers, not your network."
  value       = "http://${aws_lb.main.dns_name}/ping"
}

output "test_command" {
  description = "Copy-paste this to test from your terminal. -i shows the status code and headers."
  value       = "curl -i http://${aws_lb.main.dns_name}"
}

output "check_target_health_command" {
  description = "Run this to see whether your servers passed the health check. This is the #1 troubleshooting command."
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.app.arn} --region ${var.aws_region}"
}

output "vpc_id" {
  description = "ID of the VPC that was created."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "The public subnets - where the load balancer lives."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "The private subnets - where your servers hide."
  value       = aws_subnet.private[*].id
}

output "instance_private_ips" {
  description = "Private IPs of the app servers. Note there are no public IPs at all - that is the point."
  value       = aws_instance.app[*].private_ip
}

output "estimated_monthly_cost_usd" {
  description = "Rough always-on cost estimate. Destroy when done and you pay pennies instead."
  value = format(
    "ALB ~$16.20 + EC2 %d x ~$3.07 + EBS %d x ~$0.64 + Route53 %s = ~$%.2f/month if left running 24/7",
    var.instance_count,
    var.instance_count,
    var.enable_dns ? "$0.50" : "$0.00",
    16.20 + (var.instance_count * 3.07) + (var.instance_count * 0.64) + (var.enable_dns ? 0.50 : 0.0)
  )
}
