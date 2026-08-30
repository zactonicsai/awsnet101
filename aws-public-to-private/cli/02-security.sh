#!/usr/bin/env bash
# =============================================================================
# 02-security.sh  -  BUILD THE FIREWALLS
# -----------------------------------------------------------------------------
# Creates two security groups and the rules connecting them.
# COST: $0. Security groups are free.
# RUN:   bash 02-security.sh
# =============================================================================

source "$(dirname "$0")/00-config.sh"
preflight

# Make sure the previous script actually ran. ${VAR:-} means "the value, or
# empty if it was never set" - without the :- part, set -u would kill us here.
[[ -n "${VPC_ID:-}" ]] || die "VPC_ID not found. Run 01-network.sh first."

say "STEP 7: Creating the load balancer's security group (the public door)"

ALB_SG=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-alb-sg" \
  --description "Allow web traffic from the internet to the load balancer" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT}-alb-sg},{Key=Project,Value=${PROJECT}}]" \
  --query 'GroupId' \
  --output text \
  --region "$AWS_REGION")
save_state ALB_SG "$ALB_SG"
ok "ALB security group: $ALB_SG"

say "STEP 8: Creating the app servers' security group (the inner door)"

APP_SG=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-app-sg" \
  --description "Only the load balancer may reach these servers" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT}-app-sg},{Key=Project,Value=${PROJECT}}]" \
  --query 'GroupId' \
  --output text \
  --region "$AWS_REGION")
save_state APP_SG "$APP_SG"
ok "App security group: $APP_SG"

say "STEP 9: Writing the rules"

# --- RULE 1: internet -> load balancer on port 80 ----------------------------
# Security groups start out denying everything, so we only ever write "allow".
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG" \
  --protocol tcp \
  --port 80 \
  --cidr "$ALLOWED_CIDR" \
  --region "$AWS_REGION" >/dev/null
ok "Inbound: $ALLOWED_CIDR -> ALB on TCP/80"

# --- RULE 2: load balancer -> app servers on the app port --------------------
# --source-group is the magic word. Instead of naming IP addresses, we name the
# OTHER SECURITY GROUP. Read the rule as: "allow anything wearing the ALB badge."
# This keeps working even if IP addresses change, and it means a rogue server on
# the same street still cannot connect.
#
# The ip-permissions JSON form is used here because the simple --source-group
# flag cannot express egress rules cleanly.
aws ec2 authorize-security-group-egress \
  --group-id "$ALB_SG" \
  --ip-permissions "IpProtocol=tcp,FromPort=${APP_PORT},ToPort=${APP_PORT},UserIdGroupPairs=[{GroupId=${APP_SG}}]" \
  --region "$AWS_REGION" >/dev/null
ok "Outbound: ALB -> app servers on TCP/${APP_PORT}"

aws ec2 authorize-security-group-ingress \
  --group-id "$APP_SG" \
  --protocol tcp \
  --port "$APP_PORT" \
  --source-group "$ALB_SG" \
  --region "$AWS_REGION" >/dev/null
ok "Inbound: ALB security group -> app servers on TCP/${APP_PORT}"

# --- Removing the default wide-open outbound rule ----------------------------
# AWS attaches a default "allow all outbound" rule to every new security group.
# Our servers need to download nothing, so we strip it for maximum tightness.
# They can still REPLY to the load balancer, because security groups are
# STATEFUL - the response to an allowed request is automatically permitted.
#
# '|| warn' means: if the rule was already gone, print a note and carry on
# rather than crashing the script.
aws ec2 revoke-security-group-egress \
  --group-id "$APP_SG" \
  --ip-permissions 'IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]' \
  --region "$AWS_REGION" >/dev/null 2>&1 \
  && ok "Removed default allow-all-outbound from the app security group" \
  || warn "Default egress rule already absent - nothing to remove"

say "SECURITY COMPLETE. Next: bash 03-compute.sh"
