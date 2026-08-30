output "security_group_id" {
  description = "The group ID. Pass this to other modules, or reference it from another security group's rules to build tier-to-tier trust."
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  description = "Security group ARN, for IAM policies."
  value       = aws_security_group.this.arn
}

output "security_group_name" {
  description = "The generated name, including the random suffix AWS appended to name_prefix."
  value       = aws_security_group.this.name
}
