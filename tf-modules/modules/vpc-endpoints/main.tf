# =============================================================================
# MODULE: vpc-endpoints
# -----------------------------------------------------------------------------
# VPC endpoints let resources in a PRIVATE subnet reach AWS services without
# going through an internet gateway or a NAT Gateway. Traffic stays on the AWS
# network and never touches the public internet.
#
# TWO KINDS, AND THE DIFFERENCE MATTERS FINANCIALLY:
#
#   GATEWAY endpoints (S3, DynamoDB only)
#     Attach to route tables. No ENI, no hourly charge. COMPLETELY FREE.
#     Always enable the S3 one -- it costs nothing and often removes the only
#     reason you were considering a NAT Gateway.
#
#   INTERFACE endpoints (everything else)
#     Create a real network interface in each subnet, with a private IP.
#     ~$7.20/month PER ENDPOINT PER AZ, plus data processing.
#
# THE ARITHMETIC PEOPLE GET WRONG:
#   NAT Gateway            = ~$32/month + $0.045/GB, covers EVERY destination
#   3 interface endpoints
#     across 2 AZs         = ~$43/month, covers exactly three services
#
# Endpoints win when you need one or two services and want traffic off the
# public internet. NAT wins when you need general outbound access, such as
# pulling container images from Docker Hub or Quay.
# =============================================================================

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Gateway endpoints -- free
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(var.gateway_endpoints)

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type = "Gateway"

  # Gateway endpoints work by injecting a route with an AWS-managed prefix list
  # into these tables. That is the whole mechanism -- no ENI, hence no cost.
  route_table_ids = var.route_table_ids

  tags = merge(var.tags, { Name = "${var.name}-${each.value}-endpoint" })
}

# -----------------------------------------------------------------------------
# Interface endpoints -- billed per ENI-hour
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type = "Interface"

  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  # With private DNS on, ssm.us-east-1.amazonaws.com resolves to the endpoint's
  # private IP inside your VPC. Your code and the AWS CLI need no changes at
  # all -- they just stop needing internet access.
  private_dns_enabled = var.private_dns_enabled

  tags = merge(var.tags, { Name = "${var.name}-${each.value}-endpoint" })
}
