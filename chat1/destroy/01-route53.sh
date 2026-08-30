#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

if [[ -z "${HOSTED_ZONE_ID:-}" || -z "${NLB_DNS_NAME:-}" || -z "${NLB_CANONICAL_ZONE_ID:-}" ]]; then
  echo "Route 53 state missing; nothing to remove or it must be removed manually."
  exit 0
fi

DELETE_FILE="${ROOT_DIR}/.route53-delete.json"
cat > "${DELETE_FILE}" <<EOF
{
  "Comment": "Delete ${RECORD_NAME} alias",
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${NLB_CANONICAL_ZONE_ID}",
          "DNSName": "${NLB_DNS_NAME}",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF

echo "Deleting Route 53 alias ${RECORD_NAME}..."
set +e
CHANGE_ID="$(aws route53 change-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --change-batch "file://${DELETE_FILE}" \
  --no-cli-pager \
  --query 'ChangeInfo.Id' \
  --output text 2>/dev/null)"
RC=$?
set -e
rm -f "${DELETE_FILE}"

if [[ ${RC} -eq 0 && -n "${CHANGE_ID}" ]]; then
  aws route53 wait resource-record-sets-changed --id "${CHANGE_ID}" --no-cli-pager
else
  echo "Alias was already absent or could not be deleted."
fi

if [[ "${HOSTED_ZONE_CREATED_BY_US:-false}" == "true" ]]; then
  echo "This project created the hosted zone; attempting to delete it..."
  if aws route53 delete-hosted-zone --id "${HOSTED_ZONE_ID}" --no-cli-pager >/dev/null 2>&1; then
    echo "Deleted hosted zone ${HOSTED_ZONE_ID}"
  else
    echo "Hosted zone was NOT deleted."
    echo "It may contain records you added later. Review it before deleting manually."
  fi
else
  echo "Hosted zone existed before this project, so it will NOT be deleted."
fi
