#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

steps=(
  "destroy/01-route53.sh"
  "destroy/02-listener.sh"
  "destroy/03-network-load-balancer.sh"
  "destroy/04-target-group.sh"
  "destroy/05-ec2.sh"
  "destroy/06-security-groups.sh"
  "destroy/07-internet-gateway-routing.sh"
  "destroy/08-subnets.sh"
  "destroy/09-vpc.sh"
)

echo "============================================================"
echo " Destroying Route 53 -> NLB -> private EC2 stack"
echo "============================================================"

for step in "${steps[@]}"; do
  echo
  echo ">>> ${step}"
  "${ROOT_DIR}/${step}"
done

rm -f "${ROOT_DIR}/.state.env" "${ROOT_DIR}/.route53-"*.json "${ROOT_DIR}/.user-data.sh" 2>/dev/null || true

echo
echo "============================================================"
echo " DESTROY COMPLETE"
echo "============================================================"
