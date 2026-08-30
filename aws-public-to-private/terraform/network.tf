# =============================================================================
# network.tf
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# This builds the "land" everything else sits on:
#   - a VPC        = your own private fenced-off neighborhood inside AWS
#   - subnets      = individual streets inside that neighborhood
#   - an IGW       = the one and only gate in the fence to the internet
#   - route tables = the road signs that tell traffic which way to go
#
# THE BIG IDEA:
# A subnet is "public" or "private" for exactly ONE reason: whether its route
# table has a road sign pointing at the internet gate. That's it. There is no
# checkbox called "make public". It's just the road sign.
# =============================================================================

# -----------------------------------------------------------------------------
# DATA SOURCE: look up which Availability Zones exist in this region.
# A "data" block READS existing information instead of creating something.
# Availability Zones (AZs) are physically separate data centers in a region.
# We spread across 2 of them so one building catching fire doesn't kill the site.
# -----------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available" # only AZs currently healthy and accepting new resources
}

# -----------------------------------------------------------------------------
# THE VPC - Virtual Private Cloud
# Think of this as renting an empty plot of land and putting a fence around it.
# Nothing inside can talk to the outside world unless you explicitly allow it.
# COST: $0. VPCs are free.
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr # the address range, e.g. 10.0.0.0/16

  # enable_dns_support lets things inside the VPC use AWS's built-in DNS server
  # so they can look up names like s3.amazonaws.com.
  enable_dns_support = true

  # enable_dns_hostnames gives resources internal DNS names.
  # The load balancer needs this to work properly.
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# -----------------------------------------------------------------------------
# INTERNET GATEWAY (IGW)
# The single gate in the fence. Attaching it does NOT open anything by itself -
# it only becomes useful once a route table points traffic at it.
# COST: $0. Internet Gateways are free (you pay for data transfer, not the gate).
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id # bolt the gate onto our fence

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# -----------------------------------------------------------------------------
# PUBLIC SUBNETS - the streets where the load balancer lives
# count = 2 means Terraform makes this resource twice, numbered [0] and [1].
# count.index is 0 for the first copy and 1 for the second.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[count.index] # 10.0.0.0/24 then 10.0.1.0/24

  # Put copy [0] in the first AZ and copy [1] in the second AZ.
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Give anything launched here an automatic public IP address.
  # The load balancer needs public IPs to be reachable from the internet.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  }
}

# -----------------------------------------------------------------------------
# PRIVATE SUBNETS - the streets where your real servers live
# Identical to the public ones EXCEPT:
#   1. map_public_ip_on_launch is false (no public IP address at all)
#   2. their route table (below) has no path to the internet gateway
# That combination is what makes them genuinely unreachable from outside.
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false # <-- no public IP. Ever.

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "private"
  }
}

# -----------------------------------------------------------------------------
# PUBLIC ROUTE TABLE - the road signs for the public streets
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # A route says: "traffic headed for THIS destination goes THAT way."
  route {
    # 0.0.0.0/0 means "any address anywhere in the world" - the default route.
    cidr_block = "0.0.0.0/0"
    # ...send it out through the internet gate.
    gateway_id = aws_internet_gateway.main.id
  }

  # NOTE: there is an invisible built-in route for 10.0.0.0/16 (the VPC itself)
  # that AWS adds automatically and you cannot remove. That's what lets the
  # public and private subnets talk to each other internally.

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# A route table does nothing until it is ASSOCIATED with a subnet.
# This is the step that actually nails the road sign to the street corner.
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# PRIVATE ROUTE TABLE - deliberately has NO internet route
# -----------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # Look closely: there is no "route" block here at all.
  # The only route that exists is AWS's automatic local one (10.0.0.0/16).
  # Result: servers here can talk to the load balancer, and to each other,
  # and to absolutely nothing on the internet.
  #
  # COST NOTE: The usual way to give private servers outbound internet is a
  # NAT Gateway, which costs about $32/month PLUS data charges. That would be
  # the single most expensive thing in this project, so we skip it entirely.
  # Our servers don't need to download anything - see user_data.sh.

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
