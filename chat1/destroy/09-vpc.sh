#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

if [[ -z "${VPC_ID:-}" ]]; then
  echo "No VPC state found."
  exit 0
fi

echo "Deleting VPC ${VPC_ID}..."
if awsr ec2 delete-vpc --vpc-id "${VPC_ID}"; then
  echo "VPC deleted."
else
  echo
  echo "ERROR: VPC could not be deleted."
  echo "Something may still depend on it. Inspect with:"
  echo "  aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${VPC_ID} --region ${AWS_REGION}"
  exit 1
fi
