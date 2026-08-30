#!/usr/bin/env bash
# =============================================================================
# 06-verify.sh  -  PROVE IT WORKS, AND DIAGNOSE IT IF IT DOESN'T
# -----------------------------------------------------------------------------
# Runs the checks in the same order a professional would: from the inside out.
# COST: $0.
# RUN:  bash 06-verify.sh
# =============================================================================

source "$(dirname "$0")/00-config.sh"
preflight

[[ -n "${TG_ARN:-}" ]]  || die "Target group not found. Run 04-loadbalancer.sh first."
[[ -n "${ALB_DNS:-}" ]] || die "Load balancer not found. Run 04-loadbalancer.sh first."

# -----------------------------------------------------------------------------
say "CHECK 1: Are the servers healthy?"
# -----------------------------------------------------------------------------
# THIS IS THE MOST IMPORTANT TROUBLESHOOTING COMMAND IN ALL OF AWS LOAD BALANCING.
# If State is not "healthy", the ALB will not send traffic and you get 503.
# The Reason and Description columns tell you exactly why.
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason,Why:TargetHealth.Description}' \
  --output table \
  --region "$AWS_REGION"

echo
echo "  How to read that table:"
echo "    healthy      -> perfect, traffic is flowing"
echo "    initial      -> still running its first checks. Wait ~60 seconds and re-run."
echo "    unhealthy    -> the server answered wrongly, or not at all. See README troubleshooting."
echo "    unused       -> the target is registered but the load balancer has no listener for it."
echo "    draining     -> being removed on purpose, finishing existing requests."

# -----------------------------------------------------------------------------
say "CHECK 2: Does the load balancer itself respond? (touches no server)"
# -----------------------------------------------------------------------------
# /ping is our fixed-response rule. It isolates networking from application.
#   Works here but fails on / -> your SERVERS or HEALTH CHECK are the problem.
#   Fails here too                -> your SECURITY GROUP, SUBNETS, or ROUTES are the problem.
#
# curl flags: -s silent, -S still show errors, -i include headers, --max-time cap the wait
curl -sS -i --max-time 15 "http://${ALB_DNS}/ping" || warn "No answer from /ping"

# -----------------------------------------------------------------------------
say "CHECK 3: Does the real application respond?"
# -----------------------------------------------------------------------------
# This is the full journey: your computer -> DNS -> internet gateway ->
# load balancer -> private subnet -> Python server -> and all the way back.
curl -sS -i --max-time 15 "http://${ALB_DNS}/" || warn "No answer from /"

# -----------------------------------------------------------------------------
say "CHECK 4: Just the status code"
# -----------------------------------------------------------------------------
# -o /dev/null throws away the body; -w prints only the format string we want.
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://${ALB_DNS}/" || echo "000")
echo "  HTTP status code: ${CODE}"
echo
case "$CODE" in
  200) ok "SUCCESS. 200 means everything worked end to end." ;;
  503) warn "503 Service Unavailable = the ALB has no HEALTHY targets. Check 1 above tells you why." ;;
  504) warn "504 Gateway Timeout = the ALB reached your server but got no reply in time. Check the app port and security group." ;;
  000) warn "No response at all = DNS did not resolve, or the ALB security group is blocking you. Check ALLOWED_CIDR." ;;
  *)   warn "Unexpected code ${CODE}. See the README troubleshooting table." ;;
esac

# -----------------------------------------------------------------------------
say "CHECK 5: Watch the load balancing happen"
# -----------------------------------------------------------------------------
# With two servers registered, repeated requests should alternate between them.
# The ALB's default algorithm is round-robin, so you see them take turns.
echo "  Sending 6 requests - watch the 'Served by' line change:"
for i in $(seq 1 6); do
  printf '    %d) ' "$i"
  curl -s --max-time 10 "http://${ALB_DNS}/" 2>/dev/null | grep 'Served by' || echo "(no answer)"
done

# -----------------------------------------------------------------------------
say "CHECK 6: Prove the servers really are private"
# -----------------------------------------------------------------------------
# If this list is empty, no server has a public IP address, which means nobody
# on the internet can possibly reach them directly. That is the whole security
# argument of this architecture, demonstrated in one command.
echo "  Public IP addresses assigned to our instances:"
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=${PROJECT}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Instance:InstanceId,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress}' \
  --output table \
  --region "$AWS_REGION"
echo "  A PublicIP column showing 'None' everywhere is exactly what we want."

if [[ -n "${FQDN:-}" ]]; then
  say "CHECK 7: Friendly domain"
  echo "  dig +short ${FQDN}"
  dig +short "${FQDN}" 2>/dev/null || warn "dig not installed - try: nslookup ${FQDN}"
  curl -sS -o /dev/null -w '  HTTP status via %{url}: %{http_code}\n' --max-time 15 "http://${FQDN}/" || true
fi

say "VERIFICATION DONE"
echo "  When you are finished, DESTROY EVERYTHING to stop the charges:"
echo "      bash 99-destroy.sh"
