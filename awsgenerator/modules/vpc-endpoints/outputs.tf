output "gateway_endpoint_ids" {
  description = "Map of service name to gateway endpoint ID."
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}

output "interface_endpoint_ids" {
  description = "Map of service name to interface endpoint ID."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "interface_endpoint_dns_names" {
  description = "Private DNS names of the interface endpoints. Only needed if private_dns_enabled is false and you must address them explicitly."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.dns_entry }
}

output "estimated_monthly_cost" {
  description = "Rough cost of the interface endpoints. Gateway endpoints are free and excluded."
  value = format(
    "%d interface endpoint(s) x %d subnet(s) x ~$7.20 = ~$%.2f/month (gateway endpoints are free)",
    length(var.interface_endpoints),
    length(var.subnet_ids),
    length(var.interface_endpoints) * length(var.subnet_ids) * 7.20
  )
}
