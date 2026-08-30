#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

preflight
require_value PUBLIC_SUBNET_ID
require_value NLB_SG_ID

if [[ -z "${LOAD_BALANCER_ARN:-}" ]]; then
  echo "Creating ONE-AZ internet-facing Network Load Balancer..."
  LOAD_BALANCER_ARN="$(awsr elbv2 create-load-balancer \
    --name "${PROJECT_NAME}-nlb" \
    --type network \
    --scheme internet-facing \
    --ip-address-type ipv4 \
    --subnets "${PUBLIC_SUBNET_ID}" \
    --security-groups "${NLB_SG_ID}" \
    --tags "Key=Project,Value=${PROJECT_NAME}" \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)"
  save_state LOAD_BALANCER_ARN "${LOAD_BALANCER_ARN}"
fi

awsr elbv2 wait load-balancer-available --load-balancer-arns "${LOAD_BALANCER_ARN}"

NLB_DNS_NAME="$(awsr elbv2 describe-load-balancers \
  --load-balancer-arns "${LOAD_BALANCER_ARN}" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)"
save_state NLB_DNS_NAME "${NLB_DNS_NAME}"

NLB_CANONICAL_ZONE_ID="$(awsr elbv2 describe-load-balancers \
  --load-balancer-arns "${LOAD_BALANCER_ARN}" \
  --query 'LoadBalancers[0].CanonicalHostedZoneId' \
  --output text)"
save_state NLB_CANONICAL_ZONE_ID "${NLB_CANONICAL_ZONE_ID}"

echo "NLB ARN : ${LOAD_BALANCER_ARN}"
echo "NLB DNS : ${NLB_DNS_NAME}"
