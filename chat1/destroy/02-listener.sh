#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

if [[ -z "${LISTENER_ARN:-}" ]]; then
  echo "No listener state found."
  exit 0
fi

echo "Deleting listener..."
awsr elbv2 delete-listener --listener-arn "${LISTENER_ARN}" 2>/dev/null || true
