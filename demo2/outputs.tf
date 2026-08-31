output "alb_dns_name" {
  description = "Paste this into a browser once the target shows as healthy."
  value       = module.alb.alb_dns_name
}

output "alb_url" {
  description = "Full URL of the demo site."
  value       = "http://${module.alb.alb_dns_name}:${var.listener_port}"
}

output "target_group_arn" {
  description = "ARN of the target group the instance is registered in."
  value       = module.alb.target_group_arn
}

output "launch_template_id" {
  description = "ID of the launch template used to build the instance."
  value       = module.launch_template.launch_template_id
}

output "instance_id" {
  description = "ID of the EC2 instance."
  value       = aws_instance.web.id
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance."
  value       = aws_instance.web.private_ip
}

output "instance_role_arn" {
  description = "ARN of the IAM role attached to the instance, if one was created."
  value       = var.create_instance_profile ? aws_iam_role.instance[0].arn : null
}
