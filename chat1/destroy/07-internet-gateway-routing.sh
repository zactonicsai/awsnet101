#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

if [[ -n "${PUBLIC_RT_ASSOC_ID:-}" ]]; then
  awsr ec2 disassociate-route-table --association-id "${PUBLIC_RT_ASSOC_ID}" 2>/dev/null || true
fi
if [[ -n "${PRIVATE_RT_ASSOC_ID:-}" ]]; then
  awsr ec2 disassociate-route-table --association-id "${PRIVATE_RT_ASSOC_ID}" 2>/dev/null || true
fi

if [[ -n "${PUBLIC_ROUTE_TABLE_ID:-}" ]]; then
  echo "Deleting public route table..."
  awsr ec2 delete-route-table --route-table-id "${PUBLIC_ROUTE_TABLE_ID}" 2>/dev/null || true
fi
if [[ -n "${PRIVATE_ROUTE_TABLE_ID:-}" ]]; then
  echo "Deleting private route table..."
  awsr ec2 delete-route-table --route-table-id "${PRIVATE_ROUTE_TABLE_ID}" 2>/dev/null || true
fi

if [[ -n "${IGW_ID:-}" && -n "${VPC_ID:-}" ]]; then
  echo "Detaching Internet Gateway..."
  awsr ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" 2>/dev/null || true
  echo "Deleting Internet Gateway..."
  awsr ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}" 2>/dev/null || true
fi
