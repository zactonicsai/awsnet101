output "asg_name" {
  description = "Auto Scaling Group name. Needed for CloudWatch alarms, scaling policies, and `aws autoscaling` CLI commands."
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN."
  value       = aws_autoscaling_group.this.arn
}

output "asg_id" {
  description = "Auto Scaling Group ID (same as the name for this resource type)."
  value       = aws_autoscaling_group.this.id
}

output "min_size" {
  description = "Configured minimum size."
  value       = aws_autoscaling_group.this.min_size
}

output "max_size" {
  description = "Configured maximum size."
  value       = aws_autoscaling_group.this.max_size
}

output "availability_zones" {
  description = "AZs the ASG spans, derived from the subnets you supplied."
  value       = aws_autoscaling_group.this.availability_zones
}

output "scaling_policy_arn" {
  description = "ARN of the target-tracking policy, or null when scaling is disabled."
  value       = try(aws_autoscaling_policy.target_tracking[0].arn, null)
}
