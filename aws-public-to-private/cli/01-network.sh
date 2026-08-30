#!/usr/bin/env bash
# =============================================================================
# 01-network.sh  -  BUILD THE NETWORK
# -----------------------------------------------------------------------------
# Creates: 1 VPC, 2 public subnets, 2 private subnets, 1 internet gateway,
#          2 route tables, and the associations that tie them together.
# COST: $0. Every resource in this script is free.
# RUN:   bash 01-network.sh
# =============================================================================

# Load settings and helpers. "$(dirname "$0")" = the folder this script is in.
source "$(dirname "$0")/00-config.sh"
preflight

say "STEP 1: Creating the VPC (your private neighborhood inside AWS)"

# --- Create the VPC ----------------------------------------------------------
# --query is JMESPath, a mini query language built into the AWS CLI. It digs the
# one value we want out of the big JSON reply.
# --output text strips the quotes so the result is a clean string.
# --tag-specifications labels the resource AT CREATION TIME (one call instead of two).
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT}-vpc},{Key=Project,Value=${PROJECT}}]" \
  --query 'Vpc.VpcId' \
  --output text \
  --region "$AWS_REGION")
save_state VPC_ID "$VPC_ID"
ok "VPC created: $VPC_ID"

# --- Turn on DNS features ----------------------------------------------------
# These are OFF by default on a hand-made VPC and the load balancer needs them.
# Note they must be enabled one at a time - AWS rejects both in a single call.
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support   --region "$AWS_REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$AWS_REGION"
ok "DNS support and DNS hostnames enabled"

say "STEP 2: Finding two Availability Zones"

# An Availability Zone is a physically separate data center. We need two so that
# one building losing power doesn't take our whole site down. AWS requires an
# Application Load Balancer to span at least two.
# 'read -r AZ1 AZ2 <<< "string"' splits the two names into two variables.
read -r AZ1 AZ2 <<< "$(aws ec2 describe-availability-zones \
  --filters "Name=state,Values=available" \
  --query 'AvailabilityZones[0:2].ZoneName' \
  --output text \
  --region "$AWS_REGION")"
save_state AZ1 "$AZ1"
save_state AZ2 "$AZ2"
ok "Using Availability Zones: $AZ1 and $AZ2"

say "STEP 3: Creating the PUBLIC subnets (streets for the load balancer)"

# create_subnet is a small function so we don't copy-paste the same call 4 times.
# $1 = CIDR block, $2 = availability zone, $3 = Name tag suffix, $4 = tier label
create_subnet() {
  aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$1" \
    --availability-zone "$2" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-$3},{Key=Tier,Value=$4},{Key=Project,Value=${PROJECT}}]" \
    --query 'Subnet.SubnetId' \
    --output text \
    --region "$AWS_REGION"
}

PUBLIC_SUBNET_1=$(create_subnet "$PUBLIC_CIDR_1" "$AZ1" "public-1" "public")
PUBLIC_SUBNET_2=$(create_subnet "$PUBLIC_CIDR_2" "$AZ2" "public-2" "public")
save_state PUBLIC_SUBNET_1 "$PUBLIC_SUBNET_1"
save_state PUBLIC_SUBNET_2 "$PUBLIC_SUBNET_2"

# Give anything launched in these subnets an automatic public IP address.
# This is one half of what makes a subnet "public".
for s in "$PUBLIC_SUBNET_1" "$PUBLIC_SUBNET_2"; do
  aws ec2 modify-subnet-attribute --subnet-id "$s" --map-public-ip-on-launch --region "$AWS_REGION"
done
ok "Public subnets ready (auto-assign public IP is ON)"

say "STEP 4: Creating the PRIVATE subnets (streets for your real servers)"

PRIVATE_SUBNET_1=$(create_subnet "$PRIVATE_CIDR_1" "$AZ1" "private-1" "private")
PRIVATE_SUBNET_2=$(create_subnet "$PRIVATE_CIDR_2" "$AZ2" "private-2" "private")
save_state PRIVATE_SUBNET_1 "$PRIVATE_SUBNET_1"
save_state PRIVATE_SUBNET_2 "$PRIVATE_SUBNET_2"
# We deliberately do NOT run modify-subnet-attribute here. No public IPs.
ok "Private subnets ready (no public IPs - this is intentional)"

say "STEP 5: Creating the Internet Gateway (the one gate in the fence)"

IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT}-igw},{Key=Project,Value=${PROJECT}}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text \
  --region "$AWS_REGION")
save_state IGW_ID "$IGW_ID"

# Creating the gate is not enough - it must be bolted onto our fence.
aws ec2 attach-internet-gateway \
  --internet-gateway-id "$IGW_ID" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION"
ok "Internet Gateway $IGW_ID attached to $VPC_ID"

say "STEP 6: Creating route tables (the road signs)"

# --- PUBLIC route table ------------------------------------------------------
PUBLIC_RT=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-public-rt},{Key=Project,Value=${PROJECT}}]" \
  --query 'RouteTable.RouteTableId' \
  --output text \
  --region "$AWS_REGION")
save_state PUBLIC_RT "$PUBLIC_RT"

# THIS SINGLE COMMAND IS WHAT MAKES A SUBNET "PUBLIC".
# It says: anything addressed to 0.0.0.0/0 (= anywhere in the world) leaves
# through the internet gateway.
aws ec2 create-route \
  --route-table-id "$PUBLIC_RT" \
  --destination-cidr-block "0.0.0.0/0" \
  --gateway-id "$IGW_ID" \
  --region "$AWS_REGION" >/dev/null
ok "Default route 0.0.0.0/0 -> $IGW_ID added to public route table"

# A route table does nothing until associated with a subnet.
for s in "$PUBLIC_SUBNET_1" "$PUBLIC_SUBNET_2"; do
  aws ec2 associate-route-table --route-table-id "$PUBLIC_RT" --subnet-id "$s" --region "$AWS_REGION" >/dev/null
done
ok "Public subnets associated with the public route table"

# --- PRIVATE route table -----------------------------------------------------
PRIVATE_RT=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-private-rt},{Key=Project,Value=${PROJECT}}]" \
  --query 'RouteTable.RouteTableId' \
  --output text \
  --region "$AWS_REGION")
save_state PRIVATE_RT "$PRIVATE_RT"

# NOTICE: there is no create-route command for this table.
# The only route is the automatic "local" one covering 10.0.0.0/16, which AWS
# adds for you and cannot be removed. That local route is what lets the load
# balancer in the public subnet reach the servers in the private subnet.
# No internet route means no NAT Gateway, which saves ~$32/month.

for s in "$PRIVATE_SUBNET_1" "$PRIVATE_SUBNET_2"; do
  aws ec2 associate-route-table --route-table-id "$PRIVATE_RT" --subnet-id "$s" --region "$AWS_REGION" >/dev/null
done
ok "Private subnets associated with the private route table (no internet route)"

say "NETWORK COMPLETE. Next: bash 02-security.sh"
