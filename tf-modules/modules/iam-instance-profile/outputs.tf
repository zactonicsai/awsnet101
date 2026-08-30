output "instance_profile_name" {
  description = "Instance profile NAME. This is what the launch-template module wants."
  value       = aws_iam_instance_profile.this.name
}

output "instance_profile_arn" {
  description = "Instance profile ARN."
  value       = aws_iam_instance_profile.this.arn
}

output "role_name" {
  description = "Role name. Use it to attach further policies from outside this module."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "Role ARN. Reference it in S3 bucket policies, KMS key policies, or anywhere you grant this workload access."
  value       = aws_iam_role.this.arn
}

output "role_id" {
  description = "Role unique ID."
  value       = aws_iam_role.this.unique_id
}
