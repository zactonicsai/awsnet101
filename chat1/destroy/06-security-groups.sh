#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

# EC2 SG references NLB SG, so delete EC2 SG first.
if [[ -n "${EC2_SG_ID:-}" ]]; then
  echo "Deleting EC2 security group ${EC2_SG_ID}..."
  awsr ec2 delete-security-group --group-id "${EC2_SG_ID}" 2>/dev/null || true
fi

if [[ -n "${NLB_SG_ID:-}" ]]; then
  echo "Deleting NLB security group ${NLB_SG_ID}..."
  awsr ec2 delete-security-group --group-id "${NLB_SG_ID}" 2>/dev/null || true
fi
