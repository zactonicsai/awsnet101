#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

echo
echo "================ AWS LOW-COST STACK ================"
printf "%-24s %s\n" "Region:" "${AWS_REGION}"
printf "%-24s %s\n" "VPC:" "${VPC_ID:-not created}"
printf "%-24s %s\n" "Public subnet:" "${PUBLIC_SUBNET_ID:-not created}"
printf "%-24s %s\n" "Private subnet:" "${PRIVATE_SUBNET_ID:-not created}"
printf "%-24s %s\n" "EC2:" "${INSTANCE_ID:-not created}"
printf "%-24s %s\n" "EC2 private IP:" "${PRIVATE_IP:-not created}"
printf "%-24s %s\n" "Target group:" "${TARGET_GROUP_ARN:-not created}"
printf "%-24s %s\n" "NLB:" "${LOAD_BALANCER_ARN:-not created}"
printf "%-24s %s\n" "NLB DNS:" "${NLB_DNS_NAME:-not created}"
printf "%-24s %s\n" "Hosted zone:" "${HOSTED_ZONE_ID:-not created}"
printf "%-24s %s\n" "URL:" "http://${RECORD_NAME}"
echo "====================================================="

if [[ -n "${TARGET_GROUP_ARN:-}" ]]; then
  echo
  echo "Target health:"
  awsr elbv2 describe-target-health \
    --target-group-arn "${TARGET_GROUP_ARN}" \
    --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
    --output table || true
fi

echo
echo "Test after DNS is delegated/propagated:"
echo "  curl -v http://${RECORD_NAME}/"
