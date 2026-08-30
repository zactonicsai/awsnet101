#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

if [[ -n "${PRIVATE_SUBNET_ID:-}" ]]; then
  echo "Deleting private subnet..."
  awsr ec2 delete-subnet --subnet-id "${PRIVATE_SUBNET_ID}" 2>/dev/null || true
fi

if [[ -n "${PUBLIC_SUBNET_ID:-}" ]]; then
  echo "Deleting public subnet..."
  awsr ec2 delete-subnet --subnet-id "${PUBLIC_SUBNET_ID}" 2>/dev/null || true
fi
