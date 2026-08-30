#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

preflight
require_value LOAD_BALANCER_ARN
require_value TARGET_GROUP_ARN

if [[ -z "${LISTENER_ARN:-}" ]]; then
  LISTENER_ARN="$(awsr elbv2 create-listener \
    --load-balancer-arn "${LOAD_BALANCER_ARN}" \
    --protocol TCP \
    --port "${LB_PORT}" \
    --default-actions "Type=forward,TargetGroupArn=${TARGET_GROUP_ARN}" \
    --query 'Listeners[0].ListenerArn' \
    --output text)"
  save_state LISTENER_ARN "${LISTENER_ARN}"
fi

echo "Listener: TCP ${LB_PORT}"
echo "Forward : target port ${APP_PORT}"
