output "secret_arn" {
  description = "Secret ARN. Grant secretsmanager:GetSecretValue on this in your instance role, and pass it into user data so the app knows what to fetch."
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_id" {
  description = "Secret ID."
  value       = aws_secretsmanager_secret.this.id
}

output "secret_name" {
  description = "Secret name, usable with the CLI: aws secretsmanager get-secret-value --secret-id <name>"
  value       = aws_secretsmanager_secret.this.name
}

output "password" {
  description = "The generated password, or null. SENSITIVE -- prefer passing secret_arn to your application and letting it fetch the value at runtime, so the password never travels through user data."
  value       = local.generated
  sensitive   = true
}
