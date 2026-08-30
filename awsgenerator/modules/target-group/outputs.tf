output "target_group_arn" {
  description = "Target group ARN. Pass to the asg module's target_group_arns and to the alb module's listener."
  value       = aws_lb_target_group.this.arn
}

output "target_group_name" {
  description = "Generated name including the random suffix."
  value       = aws_lb_target_group.this.name
}

output "target_group_id" {
  description = "Target group ID (identical to the ARN for this resource)."
  value       = aws_lb_target_group.this.id
}

output "arn_suffix" {
  description = "ARN suffix, e.g. targetgroup/my-tg/1234567890. Required by CloudWatch metrics and by ALBRequestCountPerTarget scaling policies."
  value       = aws_lb_target_group.this.arn_suffix
}

output "health_check_command" {
  description = "Ready-to-run CLI command showing why targets are healthy or not. The single most useful load balancer debugging command there is."
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.this.arn} --output table"
}
