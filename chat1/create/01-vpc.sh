#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

preflight

if [[ -n "${VPC_ID:-}" ]] && awsr ec2 describe-vpcs --vpc-ids "${VPC_ID}" >/dev/null 2>&1; then
  echo "VPC already exists: ${VPC_ID}"
  exit 0
fi

echo "Creating VPC ${VPC_CIDR}..."
VPC_ID="$(awsr ec2 create-vpc \
  --cidr-block "${VPC_CIDR}" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'Vpc.VpcId' \
  --output text)"

save_state VPC_ID "${VPC_ID}"

awsr ec2 wait vpc-available --vpc-ids "${VPC_ID}"

# These settings make normal AWS DNS names work inside the VPC.
awsr ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-support '{"Value":true}'
awsr ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames '{"Value":true}'

echo "Created VPC: ${VPC_ID}"
