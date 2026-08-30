#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

preflight
require_value VPC_ID
require_value INSTANCE_ID

if [[ -z "${TARGET_GROUP_ARN:-}" ]]; then
  TARGET_GROUP_ARN="$(awsr elbv2 create-target-group \
    --name "${PROJECT_NAME}-tg" \
    --protocol TCP \
    --port "${APP_PORT}" \
    --target-type instance \
    --vpc-id "${VPC_ID}" \
    --health-check-protocol TCP \
    --health-check-port traffic-port \
    --tags "Key=Project,Value=${PROJECT_NAME}" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)"
  save_state TARGET_GROUP_ARN "${TARGET_GROUP_ARN}"
fi

awsr elbv2 register-targets \
  --target-group-arn "${TARGET_GROUP_ARN}" \
  --targets "Id=${INSTANCE_ID},Port=${APP_PORT}"

echo "Target Group: ${TARGET_GROUP_ARN}"
echo "Registered  : ${INSTANCE_ID}:${APP_PORT}"
