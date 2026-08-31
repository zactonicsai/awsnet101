output "launch_template_id" {
  description = "ID of the launch template. Pass to aws_instance or an Auto Scaling group."
  value       = aws_launch_template.this.id
}

output "launch_template_arn" {
  description = "ARN of the launch template."
  value       = aws_launch_template.this.arn
}

output "launch_template_name" {
  description = "Generated name of the launch template."
  value       = aws_launch_template.this.name
}

output "latest_version" {
  description = "Latest version number of the launch template."
  value       = aws_launch_template.this.latest_version
}
