#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

steps=(
  "create/01-vpc.sh"
  "create/02-subnets.sh"
  "create/03-internet-gateway-routing.sh"
  "create/04-security-groups.sh"
  "create/05-ec2.sh"
  "create/06-target-group.sh"
  "create/07-network-load-balancer.sh"
  "create/08-listener.sh"
  "create/09-route53.sh"
)

echo "============================================================"
echo " Creating low-cost Route 53 -> NLB -> private EC2 stack"
echo "============================================================"

for step in "${steps[@]}"; do
  echo
  echo ">>> ${step}"
  "${ROOT_DIR}/${step}"
done

echo
echo "============================================================"
echo " CREATE COMPLETE"
echo "============================================================"
"${ROOT_DIR}/show-status.sh"
