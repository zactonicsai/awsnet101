#!/usr/bin/env bash
# =============================================================================
# 05-dns.sh  -  GIVE IT A FRIENDLY URL  (OPTIONAL)
# -----------------------------------------------------------------------------
# Points yourname.yourdomain.com at the load balancer using a Route 53 ALIAS
# record.
#
# SKIP THIS SCRIPT unless you already own a domain AND have created a public
# hosted zone for it in Route 53. Your site already works at the long ALB name.
#
# COST: $0.50/month per hosted zone. Alias queries to AWS resources are FREE.
# RUN:  ENABLE_DNS=true HOSTED_ZONE_NAME=example.com bash 05-dns.sh
# =============================================================================

source "$(dirname "$0")/00-config.sh"
preflight

if [[ "$ENABLE_DNS" != "true" ]]; then
  warn "ENABLE_DNS is not 'true' - skipping DNS setup."
  echo  "Your site already works at: http://${ALB_DNS:-<run 04 first>}"
  echo  "To enable DNS: ENABLE_DNS=true HOSTED_ZONE_NAME=yourdomain.com bash 05-dns.sh"
  exit 0
fi

[[ -n "${ALB_DNS:-}" ]]     || die "Load balancer not found. Run 04-loadbalancer.sh first."
[[ -n "${ALB_ZONE_ID:-}" ]] || die "ALB zone ID not found. Re-run 04-loadbalancer.sh."

say "STEP 20: Finding your hosted zone"

# A hosted zone is the container holding all DNS records for one domain.
#
# WE LOOK IT UP RATHER THAN CREATE IT, on purpose. Creating a zone assigns 4
# random nameservers that you must copy to your domain registrar by hand. If a
# script ever deletes and recreates the zone, you get 4 different nameservers
# and your domain goes dark until you update the registrar again. Create the
# zone ONCE manually; automate only the records inside it.
#
# The trailing dot in "example.com." is real DNS syntax meaning "fully
# qualified, stop here". Route 53 always returns names in this form.
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "${HOSTED_ZONE_NAME}." \
  --query "HostedZones[?Name=='${HOSTED_ZONE_NAME}.' && Config.PrivateZone==\`false\`].Id | [0]" \
  --output text)

# Route 53 returns IDs prefixed with "/hostedzone/". The change-record API wants
# it without the prefix, so we strip it. '${VAR#pattern}' removes a prefix.
ZONE_ID="${ZONE_ID#/hostedzone/}"

if [[ -z "$ZONE_ID" || "$ZONE_ID" == "None" ]]; then
  die "No PUBLIC hosted zone found for '${HOSTED_ZONE_NAME}'. Create one in the Route 53 console first, then point your registrar at its 4 nameservers."
fi
save_state ZONE_ID "$ZONE_ID"
ok "Found hosted zone: $ZONE_ID"

say "STEP 21: Creating the ALIAS record"

FQDN="${SUBDOMAIN}.${HOSTED_ZONE_NAME}"

# WHY AN ALIAS AND NOT A CNAME:
#   - A load balancer has no fixed IP, so a plain A record is impossible.
#   - A CNAME would work for a subdomain but is ILLEGAL at the domain root.
#   - An ALIAS is Amazon's own type: it tracks the ALB's changing IPs
#     automatically, works at the root, and costs nothing to query.
#
# HostedZoneId inside the AliasTarget is the ALB's OWN hidden zone ID
# (CanonicalHostedZoneId), NOT your domain's zone ID. Confusing these two is
# the single most common Route 53 mistake.
#
# UPSERT means "update if it exists, otherwise create" - safe to re-run.
CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "{
    \"Comment\": \"Point ${FQDN} at the ${PROJECT} load balancer\",
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"${FQDN}\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"${ALB_ZONE_ID}\",
          \"DNSName\": \"dualstack.${ALB_DNS}\",
          \"EvaluateTargetHealth\": true
        }
      }
    }]
  }" \
  --query 'ChangeInfo.Id' \
  --output text)
ok "DNS change submitted: $CHANGE_ID"

# The "dualstack." prefix tells Route 53 to hand back both IPv4 and IPv6
# addresses. It is the recommended form for ALB alias targets and costs nothing.

say "STEP 22: Waiting for the change to spread across Route 53"
warn "Usually under 60 seconds."

aws route53 wait resource-record-sets-changed --id "$CHANGE_ID"
ok "DNS record is live everywhere"

save_state FQDN "$FQDN"

say "DNS COMPLETE"
echo
echo "  Your friendly URL: http://${FQDN}"
echo
echo "  Verify with:  dig +short ${FQDN}"
echo "  Test with:    curl -i http://${FQDN}"
echo
warn "Your computer may cache the old answer for a few minutes. If it fails, wait or try a different network."
