#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

preflight
require_value VPC_ID
require_value PUBLIC_SUBNET_ID
require_value PRIVATE_SUBNET_ID

if [[ -z "${IGW_ID:-}" ]]; then
  IGW_ID="$(awsr ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw},{Key=Project,Value=${PROJECT_NAME}}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)"
  save_state IGW_ID "${IGW_ID}"
  awsr ec2 attach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}"
fi

# Public route table: this is what lets the internet-facing NLB reach the internet.
if [[ -z "${PUBLIC_ROUTE_TABLE_ID:-}" ]]; then
  PUBLIC_ROUTE_TABLE_ID="$(awsr ec2 create-route-table \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rt},{Key=Project,Value=${PROJECT_NAME}}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)"
  save_state PUBLIC_ROUTE_TABLE_ID "${PUBLIC_ROUTE_TABLE_ID}"

  awsr ec2 create-route \
    --route-table-id "${PUBLIC_ROUTE_TABLE_ID}" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "${IGW_ID}" >/dev/null

  PUBLIC_RT_ASSOC_ID="$(awsr ec2 associate-route-table \
    --route-table-id "${PUBLIC_ROUTE_TABLE_ID}" \
    --subnet-id "${PUBLIC_SUBNET_ID}" \
    --query 'AssociationId' \
    --output text)"
  save_state PUBLIC_RT_ASSOC_ID "${PUBLIC_RT_ASSOC_ID}"
fi

# Private route table intentionally has NO internet/default route.
# This avoids NAT Gateway cost.
if [[ -z "${PRIVATE_ROUTE_TABLE_ID:-}" ]]; then
  PRIVATE_ROUTE_TABLE_ID="$(awsr ec2 create-route-table \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-rt},{Key=Project,Value=${PROJECT_NAME}}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)"
  save_state PRIVATE_ROUTE_TABLE_ID "${PRIVATE_ROUTE_TABLE_ID}"

  PRIVATE_RT_ASSOC_ID="$(awsr ec2 associate-route-table \
    --route-table-id "${PRIVATE_ROUTE_TABLE_ID}" \
    --subnet-id "${PRIVATE_SUBNET_ID}" \
    --query 'AssociationId' \
    --output text)"
  save_state PRIVATE_RT_ASSOC_ID "${PRIVATE_RT_ASSOC_ID}"
fi

echo "Internet Gateway : ${IGW_ID}"
echo "Public RT        : ${PUBLIC_ROUTE_TABLE_ID}"
echo "Private RT       : ${PRIVATE_ROUTE_TABLE_ID}"
echo "NOTE: Private route table has no NAT Gateway and no internet route."
