#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

preflight
validate_domain
require_value NLB_DNS_NAME
require_value NLB_CANONICAL_ZONE_ID

echo "Looking for an existing PUBLIC Route 53 hosted zone for ${DOMAIN_NAME}..."

# Exact match, including Route 53's trailing dot.
HOSTED_ZONE_ID="$(aws route53 list-hosted-zones-by-name \
  --dns-name "${DOMAIN_NAME}" \
  --no-cli-pager \
  --query "HostedZones[?Name=='${DOMAIN_NAME}.'] | [?Config.PrivateZone==\`false\`] | [0].Id" \
  --output text 2>/dev/null || true)"

if [[ "${HOSTED_ZONE_ID}" == "None" ]]; then
  HOSTED_ZONE_ID=""
fi

if [[ -z "${HOSTED_ZONE_ID}" ]]; then
  echo "No public hosted zone found. Creating one..."
  CALLER_REF="${PROJECT_NAME}-$(date +%s)"

  HOSTED_ZONE_ID="$(aws route53 create-hosted-zone \
    --name "${DOMAIN_NAME}" \
    --caller-reference "${CALLER_REF}" \
    --hosted-zone-config "Comment=${PROJECT_NAME} public zone,PrivateZone=false" \
    --no-cli-pager \
    --query 'HostedZone.Id' \
    --output text)"

  save_state HOSTED_ZONE_CREATED_BY_US "true"
else
  echo "Reusing existing hosted zone."
  save_state HOSTED_ZONE_CREATED_BY_US "false"
fi

# Route 53 often returns /hostedzone/Z123...; both forms work in many commands,
# but keeping only the ID makes output easier to read.
HOSTED_ZONE_ID="${HOSTED_ZONE_ID#/hostedzone/}"
save_state HOSTED_ZONE_ID "${HOSTED_ZONE_ID}"

CHANGE_FILE="${ROOT_DIR}/.route53-upsert.json"
cat > "${CHANGE_FILE}" <<EOF
{
  "Comment": "Route ${RECORD_NAME} to the Network Load Balancer",
  "Changes": [
    {
      "Action": "UPSERT",
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

CHANGE_ID="$(aws route53 change-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --change-batch "file://${CHANGE_FILE}" \
  --no-cli-pager \
  --query 'ChangeInfo.Id' \
  --output text)"

rm -f "${CHANGE_FILE}"

echo "Waiting for Route 53 change to become INSYNC..."
aws route53 wait resource-record-sets-changed --id "${CHANGE_ID}" --no-cli-pager

echo
echo "Hosted Zone ID: ${HOSTED_ZONE_ID}"
echo "Alias record   : ${RECORD_NAME}"
echo "Target NLB     : ${NLB_DNS_NAME}"
echo "URL            : http://${RECORD_NAME}"

if [[ "${HOSTED_ZONE_CREATED_BY_US}" == "true" ]]; then
  echo
  echo "IMPORTANT: This script created a NEW hosted zone."
  echo "If your domain is registered outside Route 53, update the domain registrar"
  echo "to use these Route 53 name servers:"
  aws route53 get-hosted-zone \
    --id "${HOSTED_ZONE_ID}" \
    --no-cli-pager \
    --query 'DelegationSet.NameServers' \
    --output table
fi
