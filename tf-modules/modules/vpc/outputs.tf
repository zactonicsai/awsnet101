output "vpc_id" {
  description = "VPC ID. Feed this into security-group, target-group, rds and any other module that needs it."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "The VPC's CIDR. Useful for writing security group rules that allow VPC-internal traffic."
  value       = aws_vpc.this.cidr_block
}

output "vpc_arn" {
  description = "VPC ARN, for IAM policies and resource-based policies."
  value       = aws_vpc.this.arn
}

output "public_subnet_ids" {
  description = "Public subnet IDs, in AZ order. Pass to the alb module."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, in AZ order. Pass to the asg and rds modules."
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDRs of the public subnets."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDRs of the private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "availability_zones" {
  description = "The AZs actually used, whether supplied or auto-selected."
  value       = local.azs
}

output "internet_gateway_id" {
  description = "Internet Gateway ID, or null when no public subnets were created."
  value       = try(aws_internet_gateway.this[0].id, null)
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs. Empty list when NAT is disabled."
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT Gateways. Give these to third parties who need to allow-list your outbound traffic."
  value       = aws_eip.nat[*].public_ip
}

output "public_route_table_id" {
  description = "Public route table ID, or null when no public subnets exist."
  value       = try(aws_route_table.public[0].id, null)
}

output "private_route_table_ids" {
  description = "Private route table IDs. One entry when sharing a NAT, one per AZ otherwise."
  value       = aws_route_table.private[*].id
}
