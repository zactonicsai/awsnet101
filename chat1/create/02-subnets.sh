#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

preflight
require_value VPC_ID

if [[ -z "${AZ:-}" ]]; then
  AZ="$(awsr ec2 describe-availability-zones \
    --filters Name=state,Values=available \
    --query 'AvailabilityZones[0].ZoneName' \
    --output text)"
  save_state AZ "${AZ}"
fi

echo "Using Availability Zone: ${AZ}"

if [[ -z "${PUBLIC_SUBNET_ID:-}" ]]; then
  PUBLIC_SUBNET_ID="$(awsr ec2 create-subnet \
    --vpc-id "${VPC_ID}" \
    --cidr-block "${PUBLIC_SUBNET_CIDR}" \
    --availability-zone "${AZ}" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public},{Key=Project,Value=${PROJECT_NAME}},{Key=Tier,Value=public}]" \
    --query 'Subnet.SubnetId' \
    --output text)"
  save_state PUBLIC_SUBNET_ID "${PUBLIC_SUBNET_ID}"
fi

if [[ -z "${PRIVATE_SUBNET_ID:-}" ]]; then
  PRIVATE_SUBNET_ID="$(awsr ec2 create-subnet \
    --vpc-id "${VPC_ID}" \
    --cidr-block "${PRIVATE_SUBNET_CIDR}" \
    --availability-zone "${AZ}" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private},{Key=Project,Value=${PROJECT_NAME}},{Key=Tier,Value=private}]" \
    --query 'Subnet.SubnetId' \
    --output text)"
  save_state PRIVATE_SUBNET_ID "${PRIVATE_SUBNET_ID}"
fi

# Be explicit: EC2s launched in the private subnet do NOT receive public IPv4.
awsr ec2 modify-subnet-attribute \
  --subnet-id "${PRIVATE_SUBNET_ID}" \
  --no-map-public-ip-on-launch

echo "Public subnet : ${PUBLIC_SUBNET_ID}"
echo "Private subnet: ${PRIVATE_SUBNET_ID}"
