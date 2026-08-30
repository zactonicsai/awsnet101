#!/usr/bin/env bash
# =============================================================================
# 04-loadbalancer.sh  -  THE PART THAT CONNECTS THE INTERNET TO THE PRIVATE SERVERS
# -----------------------------------------------------------------------------
# Creates the Application Load Balancer, the target group, registers the servers
# into it, and attaches a listener. All four steps are required.
#
# NOTE: these commands use "aws elbv2", not "aws elb". elbv2 is the modern API
# covering ALB and NLB. The old "aws elb" is for the retired Classic Load
# Balancer, and mixing them up is a very common source of confusing errors.
#
# COST: ~$16.20/month for the ALB. This is the expensive part - destroy when done.
# RUN:  bash 04-loadbalancer.sh
# =============================================================================

source "$(dirname "$0")/00-config.sh"
preflight

[[ -n "${PUBLIC_SUBNET_1:-}" ]] || die "Subnets not found. Run 01-network.sh first."
[[ -n "${INSTANCE_1:-}" ]]      || die "Instances not found. Run 03-compute.sh first."

say "STEP 14: Creating the Application Load Balancer"

# The ALB goes in the PUBLIC subnets - it is the only thing the internet touches.
# --scheme internet-facing gives it public IP addresses.
#   (--scheme internal would make it reachable only from inside the VPC.)
# --type application means Layer 7: it understands HTTP paths and hostnames.
# Two subnets in two different AZs are MANDATORY; AWS rejects fewer.
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${PROJECT}-alb" \
  --type application \
  --scheme internet-facing \
  --subnets "$PUBLIC_SUBNET_1" "$PUBLIC_SUBNET_2" \
  --security-groups "$ALB_SG" \
  --tags "Key=Name,Value=${PROJECT}-alb" "Key=Project,Value=${PROJECT}" \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text \
  --region "$AWS_REGION")
save_state ALB_ARN "$ALB_ARN"
ok "Load balancer created"

# An ARN (Amazon Resource Name) is AWS's globally unique ID for a resource.
# It looks like: arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/...

say "STEP 15: Creating the target group (the list of who can answer)"

# The target group holds the health-check policy AND the list of servers.
# --port / --protocol describe how the ALB talks to servers on the INSIDE.
#   The public arrives on port 80; the ALB forwards to 8080. That is normal.
# --target-type instance means we register EC2 instance IDs.
#
# HEALTH CHECK SETTINGS - this is where "returns 200" matters:
#   --health-check-path /            the URL the ALB requests
#   --matcher HttpCode=200           only a clean 200 counts as healthy
#   --health-check-interval-seconds  how often to check
#   --healthy-threshold-count 2      2 passes in a row -> start sending traffic
#   --unhealthy-threshold-count 2    2 failures in a row -> stop sending traffic
TG_ARN=$(aws elbv2 create-target-group \
  --name "${PROJECT}-tg" \
  --protocol HTTP \
  --port "$APP_PORT" \
  --vpc-id "$VPC_ID" \
  --target-type instance \
  --health-check-protocol HTTP \
  --health-check-path "/" \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --matcher "HttpCode=200" \
  --tags "Key=Name,Value=${PROJECT}-tg" "Key=Project,Value=${PROJECT}" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text \
  --region "$AWS_REGION")
save_state TG_ARN "$TG_ARN"
ok "Target group created"

# Shorten the deregistration delay from the 300-second default so teardown
# doesn't appear to hang for five minutes.
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes "Key=deregistration_delay.timeout_seconds,Value=30" \
  --region "$AWS_REGION" >/dev/null
ok "Deregistration delay set to 30 seconds"

say "STEP 16: Registering the servers INTO the target group"

# THIS IS THE STEP PEOPLE FORGET.
# Creating servers and creating a target group does not connect them. Without
# this command everything looks perfect and the website returns 503.
aws elbv2 register-targets \
  --target-group-arn "$TG_ARN" \
  --targets "Id=${INSTANCE_1},Port=${APP_PORT}" "Id=${INSTANCE_2},Port=${APP_PORT}" \
  --region "$AWS_REGION"
ok "Registered $INSTANCE_1 and $INSTANCE_2"

say "STEP 17: Creating the listener (the load balancer's ear)"

# Without a listener the ALB exists but answers nothing at all.
# default-actions says what to do when no other rule matches: forward to our
# target group.
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" \
  --query 'Listeners[0].ListenerArn' \
  --output text \
  --region "$AWS_REGION")
save_state LISTENER_ARN "$LISTENER_ARN"
ok "Listener on port 80 -> target group"

say "STEP 18: Adding a /ping debug rule answered by the ALB itself"

# fixed-response makes the load balancer reply directly, touching no server.
# If /ping works but / returns 503, you have PROVED the problem is your servers
# or health check rather than your networking. This one trick saves hours.
aws elbv2 create-rule \
  --listener-arn "$LISTENER_ARN" \
  --priority 100 \
  --conditions "Field=path-pattern,Values=/ping" \
  --actions 'Type=fixed-response,FixedResponseConfig={MessageBody="pong - the load balancer itself is alive",StatusCode=200,ContentType=text/plain}' \
  --region "$AWS_REGION" >/dev/null
ok "/ping rule created"

say "STEP 19: Waiting for the load balancer to become active"
warn "This is the slow part - typically 2 to 4 minutes. Be patient."

aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN" --region "$AWS_REGION"
ok "Load balancer is ACTIVE"

# Fetch the public hostname AWS generated for us.
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region "$AWS_REGION")
save_state ALB_DNS "$ALB_DNS"

# Also grab the ALB's own hidden hosted zone ID - the DNS script needs it.
ALB_ZONE_ID=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].CanonicalHostedZoneId' \
  --output text \
  --region "$AWS_REGION")
save_state ALB_ZONE_ID "$ALB_ZONE_ID"

say "LOAD BALANCER COMPLETE"
echo
echo "  Your site:  http://${ALB_DNS}"
echo "  Debug ping: http://${ALB_DNS}/ping"
echo
warn "Targets need ~60 seconds to pass 2 health checks. Run 06-verify.sh to watch."
echo "Next: bash 06-verify.sh   (or bash 05-dns.sh first if you own a domain)"
