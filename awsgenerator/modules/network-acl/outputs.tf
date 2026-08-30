output "network_acl_id" {
  description = "Network ACL ID."
  value       = aws_network_acl.this.id
}

output "network_acl_arn" {
  description = "Network ACL ARN."
  value       = aws_network_acl.this.arn
}

output "associated_subnet_ids" {
  description = "Subnets whose ACL was replaced by this one."
  value       = var.subnet_ids
}
