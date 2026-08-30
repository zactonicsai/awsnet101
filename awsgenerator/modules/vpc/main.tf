# =============================================================================
# MODULE: vpc
# -----------------------------------------------------------------------------
# The one BOOTSTRAP module in this library. Every other module accepts existing
# resource IDs; this one has to create the network primitives because something
# must. If you already have a VPC, skip this module entirely and pass your own
# vpc_id and subnet_ids straight into the others -- they neither know nor care
# whether this module produced them.
# =============================================================================

# Auto-select AZs only when the caller did not supply them.
data "aws_availability_zones" "this" {
  count = length(var.availability_zones) == 0 ? 1 : 0
  state = "available"
}

locals {
  # Resolve AZs once, then use local.azs everywhere below.
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.this[0].names, 0, var.az_count)

  # A NAT Gateway lives in a PUBLIC subnet and serves PRIVATE ones, so both
  # tiers must exist for NAT to make any sense.
  nat_enabled = var.enable_nat_gateway && length(var.public_subnet_cidrs) > 0 && length(var.private_subnet_cidrs) > 0

  # One NAT, or one per AZ. Controls how many EIPs and gateways we build.
  nat_count = local.nat_enabled ? (var.single_nat_gateway ? 1 : length(var.private_subnet_cidrs)) : 0

  # With one shared NAT every private subnet uses a single route table.
  # With per-AZ NATs each private subnet needs its own table pointing at its
  # own gateway, otherwise traffic would cross AZs and incur transfer charges.
  private_route_table_count = length(var.private_subnet_cidrs) == 0 ? 0 : (local.nat_enabled && !var.single_nat_gateway ? length(var.private_subnet_cidrs) : 1)

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(var.tags, { Name = "${var.name}-vpc" })
}

# -----------------------------------------------------------------------------
# Internet Gateway -- created only when public subnets exist.
# Free. Inert until a route table points at it.
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  count = length(var.public_subnet_cidrs) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

# -----------------------------------------------------------------------------
# Public subnets
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id     = aws_vpc.this.id
  cidr_block = var.public_subnet_cidrs[count.index]

  # Modulo lets you request more subnets than AZs without crashing; they wrap.
  availability_zone       = local.azs[count.index % length(local.azs)]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${count.index + 1}"
    Tier = "public"

    # This tag lets AWS Load Balancer Controller (EKS) auto-discover subnets.
    # Harmless if you are not using EKS.
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_route_table" "public" {
  count = length(var.public_subnet_cidrs) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public-rt" })
}

# THE route that defines a public subnet. Nothing else does.
resource "aws_route" "public_internet" {
  count = length(var.public_subnet_cidrs) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# -----------------------------------------------------------------------------
# Private subnets
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index % length(local.azs)]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                              = "${var.name}-private-${count.index + 1}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_route_table" "private" {
  count = local.private_route_table_count

  vpc_id = aws_vpc.this.id
  tags = merge(var.tags, {
    Name = local.private_route_table_count > 1 ? "${var.name}-private-rt-${count.index + 1}" : "${var.name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id = aws_subnet.private[count.index].id

  # One shared table -> index 0 for everyone. Per-AZ tables -> match the subnet.
  route_table_id = aws_route_table.private[local.private_route_table_count > 1 ? count.index : 0].id
}

# -----------------------------------------------------------------------------
# NAT Gateways -- the expensive optional part
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count = local.nat_count

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-eip-${count.index + 1}" })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id

  # A NAT Gateway sits in a PUBLIC subnet. Putting it in a private one is a
  # classic mistake that produces a gateway with no path to the internet.
  subnet_id = aws_subnet.public[count.index % length(aws_subnet.public)].id

  tags = merge(var.tags, { Name = "${var.name}-nat-${count.index + 1}" })

  # The IGW must exist and be attached before a NAT Gateway can function.
  # Terraform cannot infer this from the arguments, so we state it explicitly.
  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  count = local.nat_enabled ? local.private_route_table_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

# -----------------------------------------------------------------------------
# S3 Gateway Endpoint -- FREE private access to S3
# -----------------------------------------------------------------------------
# Genuinely free, and often removes the only reason you wanted a NAT Gateway.
# Attaches to route tables rather than using an ENI, which is why it costs nothing.
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private[*].id,
    aws_route_table.public[*].id,
  )

  tags = merge(var.tags, { Name = "${var.name}-s3-endpoint" })
}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Flow logs -- optional network visibility
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc-flow-logs/${var.name}"
  retention_in_days = var.flow_logs_retention_days
  tags              = var.tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix        = "${var.name}-flow-logs-"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = "flow-logs-"
  role        = aws_iam_role.flow_logs[0].id
  policy      = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id
  tags            = merge(var.tags, { Name = "${var.name}-flow-logs" })
}
