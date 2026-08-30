output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "RDS instance ARN."
  value       = aws_db_instance.this.arn
}

output "endpoint" {
  description = "Connection endpoint including the port, e.g. mydb.abc123.us-east-1.rds.amazonaws.com:5432"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname only, without the port."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the database listens on."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "Master username."
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = <<-EOT
    Secrets Manager ARN holding the auto-generated master password, or null
    when you supplied your own.

    Grant your application's IAM role secretsmanager:GetSecretValue on this ARN
    and it can fetch credentials at runtime -- no password in your code, your
    state file, or your environment variables.
  EOT
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "db_subnet_group_name" {
  description = "Subnet group name, reusable by read replicas."
  value       = aws_db_subnet_group.this.name
}
