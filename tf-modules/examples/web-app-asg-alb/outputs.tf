output "website_url" {
  description = "OPEN THIS. The answer to the whole example."
  value       = var.enable_dns ? "http://${var.subdomain}.${var.hosted_zone_name}" : module.alb.url
}

output "alb_dns_name" {
  description = "The load balancer's own hostname. Always works, even without DNS."
  value       = module.alb.alb_dns_name
}

output "ping_url" {
  description = "Answered by the load balancer itself. If this works but the site does not, your instances are the problem."
  value       = "http://${module.alb.alb_dns_name}/ping"
}

output "check_target_health" {
  description = "The single most useful debugging command. Run it whenever you see a 503."
  value       = module.app_tg.health_check_command
}

output "asg_name" {
  description = "Auto Scaling Group name, for CLI inspection."
  value       = module.app_asg.asg_name
}

output "private_subnet_ids" {
  description = "Where the instances live. Note they have no public IPs at all."
  value       = module.network.private_subnet_ids
}

output "estimated_monthly_cost" {
  description = "Rough always-on estimate. Destroy when finished and you pay pennies."
  value = format(
    "ALB ~$16.20 + %d x t4g.nano ~$%.2f + EBS ~$%.2f = ~$%.2f/month if left running",
    var.desired_capacity,
    var.desired_capacity * 3.07,
    var.desired_capacity * 0.64,
    16.20 + (var.desired_capacity * 3.71)
  )
}
