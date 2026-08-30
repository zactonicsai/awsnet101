output "keycloak_url" {
  description = "OPEN THIS. The Keycloak welcome page."
  value       = local.hostname_url
}

output "admin_console_url" {
  description = "Keycloak admin console."
  value       = "${local.hostname_url}/admin"
}

output "alb_dns_name" {
  description = "Load balancer hostname. Works with no custom domain."
  value       = module.alb.alb_dns_name
}

output "get_admin_password_command" {
  description = "Run this to retrieve the generated Keycloak admin password."
  value       = "aws secretsmanager get-secret-value --secret-id ${module.keycloak_admin.secret_name} --region ${var.aws_region} --query SecretString --output text"
}

output "get_db_password_command" {
  description = "Retrieve the RDS master password that AWS generated and rotates."
  value       = "aws secretsmanager get-secret-value --secret-id ${module.database.master_user_secret_arn} --region ${var.aws_region} --query SecretString --output text"
}

output "check_target_health" {
  description = "THE debugging command. Run this first for any 503."
  value       = module.keycloak_tg.health_check_command
}

output "session_manager_command" {
  description = "Open a shell on an instance with no SSH key and no open port 22. Get the instance ID from the ASG first."
  value       = "aws ssm start-session --target <instance-id> --region ${var.aws_region}"
}

output "list_instances_command" {
  description = "List the Keycloak instances and their IDs."
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${module.keycloak_asg.asg_name} --region ${var.aws_region} --query 'AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState,HealthStatus]' --output table"
}

output "database_endpoint" {
  description = "RDS endpoint. Reachable only from the app tier's security group."
  value       = module.database.endpoint
}

output "estimated_monthly_cost" {
  description = "Rough always-on estimate. The NAT Gateway is the largest single item."
  value = format(
    "ALB ~$16.20 + NAT ~$32.40 + %d x %s ~$%.2f + RDS %s ~$12.41 + secrets ~$0.80 = ~$%.2f/month",
    var.desired_capacity,
    var.instance_type,
    var.desired_capacity * 12.26,
    var.db_instance_class,
    16.20 + 32.40 + (var.desired_capacity * 12.26) + 12.41 + 0.80
  )
}
