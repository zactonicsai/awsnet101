#!/usr/bin/env bash
# =============================================================================
# 99-destroy.sh  -  DELETE EVERYTHING AND STOP THE BILL
# -----------------------------------------------------------------------------
# THE MOST IMPORTANT SCRIPT IN THIS PROJECT.
# An idle load balancer costs about $16 every month, forever, whether or not
# anyone visits. Run this the moment you finish practising.
#
# ORDER MATTERS ENORMOUSLY. AWS refuses to delete a resource that something else
# still depends on. We work backwards, innermost dependency last:
#     DNS -> listener -> load balancer -> target group -> instances ->
#     security groups -> route tables -> subnets -> gateway -> VPC
# Getting this order wrong is the #1 reason people give up and leave things
# running (and paying). Terraform figures the order out for you automatically.
#
# RUN: bash 99-destroy.sh
# =============================================================================

source "$(dirname "$0")/00-config.sh"
preflight

say "This will PERMANENTLY DELETE all '${PROJECT}' resources in ${AWS_REGION}."
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || die "Cancelled. Nothing was deleted."

# quiet() runs a command but ignores failures, so that an already-deleted
# resource doesn't abort the whole teardown halfway through.
quiet() { "$@" >/dev/null 2>&1 || true; }

# --- 1. DNS record -----------------------------------------------------------
if [[ -n "${ZONE_ID:-}" && -n "${FQDN:-}" && -n "${ALB_DNS:-}" && -n "${ALB_ZONE_ID:-}" ]]; then
  say "Deleting DNS record ${FQDN}"
  # DELETE requires the record to be described EXACTLY as it exists, which is
  # why we repeat every field rather than just naming it.
  quiet aws route53 change-resource-record-sets \
    --hosted-zone-id "$ZONE_ID" \
    --change-batch "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"${FQDN}\",\"Type\":\"A\",\"AliasTarget\":{\"HostedZoneId\":\"${ALB_ZONE_ID}\",\"DNSName\":\"dualstack.${ALB_DNS}\",\"EvaluateTargetHealth\":true}}}]}"
  ok "DNS record removed (the hosted zone itself is kept - it is yours)"
fi

# --- 2. Load balancer (deletes its listeners and rules with it) --------------
if [[ -n "${ALB_ARN:-}" ]]; then
  say "Deleting the load balancer - THIS IS THE EXPENSIVE ONE"
  quiet aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION"
  # Wait for it to actually disappear. The target group and security groups
  # cannot be deleted while the ALB still references them.
  quiet aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN" --region "$AWS_REGION"
  ok "Load balancer deleted - billing for it has stopped"
fi

# --- 3. Target group ---------------------------------------------------------
if [[ -n "${TG_ARN:-}" ]]; then
  say "Deleting the target group"
  quiet aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region "$AWS_REGION"
  ok "Target group deleted"
fi

# --- 4. EC2 instances --------------------------------------------------------
INSTANCES=""
[[ -n "${INSTANCE_1:-}" ]] && INSTANCES="$INSTANCES $INSTANCE_1"
[[ -n "${INSTANCE_2:-}" ]] && INSTANCES="$INSTANCES $INSTANCE_2"
if [[ -n "${INSTANCES// /}" ]]; then
  say "Terminating instances:$INSTANCES"
  # shellcheck disable=SC2086
  quiet aws ec2 terminate-instances --instance-ids $INSTANCES --region "$AWS_REGION"
  warn "Waiting for termination (this frees the network interfaces - can take 1-2 minutes)"
  # shellcheck disable=SC2086
  quiet aws ec2 wait instance-terminated --instance-ids $INSTANCES --region "$AWS_REGION"
  ok "Instances terminated (their encrypted disks were deleted with them)"
fi

# --- 5. Security groups ------------------------------------------------------
# The two groups reference EACH OTHER, and AWS will not delete a group while
# another group's rule still points at it. So we strip the cross-references
# first, then delete. This circular-dependency dance is a classic AWS gotcha.
if [[ -n "${APP_SG:-}" && -n "${ALB_SG:-}" ]]; then
  say "Removing cross-references between the security groups"
  quiet aws ec2 revoke-security-group-ingress --group-id "$APP_SG" \
    --protocol tcp --port "$APP_PORT" --source-group "$ALB_SG" --region "$AWS_REGION"
  quiet aws ec2 revoke-security-group-egress --group-id "$ALB_SG" \
    --ip-permissions "IpProtocol=tcp,FromPort=${APP_PORT},ToPort=${APP_PORT},UserIdGroupPairs=[{GroupId=${APP_SG}}]" \
    --region "$AWS_REGION"
  ok "Cross-references removed"

  say "Deleting the security groups"
  # Retry a few times: network interfaces can linger for a minute after the
  # instances vanish, and AWS blocks deletion until they are gone.
  for sg in "$APP_SG" "$ALB_SG"; do
    for attempt in 1 2 3 4 5 6; do
      if aws ec2 delete-security-group --group-id "$sg" --region "$AWS_REGION" >/dev/null 2>&1; then
        ok "Deleted $sg"
        break
      fi
      warn "  $sg still in use, retrying in 15s (attempt $attempt/6)"
      sleep 15
    done
  done
fi

# --- 6. Route tables ---------------------------------------------------------
# Associations must be removed before the table can be deleted. We look them up
# live rather than trusting saved state, since association IDs were never saved.
for rt in "${PUBLIC_RT:-}" "${PRIVATE_RT:-}"; do
  [[ -n "$rt" ]] || continue
  say "Deleting route table $rt"
  ASSOCS=$(aws ec2 describe-route-tables --route-table-ids "$rt" \
    --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
    --output text --region "$AWS_REGION" 2>/dev/null || echo "")
  for a in $ASSOCS; do
    quiet aws ec2 disassociate-route-table --association-id "$a" --region "$AWS_REGION"
  done
  quiet aws ec2 delete-route-table --route-table-id "$rt" --region "$AWS_REGION"
  ok "Route table $rt deleted"
done

# --- 7. Subnets --------------------------------------------------------------
for sn in "${PUBLIC_SUBNET_1:-}" "${PUBLIC_SUBNET_2:-}" "${PRIVATE_SUBNET_1:-}" "${PRIVATE_SUBNET_2:-}"; do
  [[ -n "$sn" ]] || continue
  quiet aws ec2 delete-subnet --subnet-id "$sn" --region "$AWS_REGION"
  ok "Subnet $sn deleted"
done

# --- 8. Internet gateway -----------------------------------------------------
if [[ -n "${IGW_ID:-}" && -n "${VPC_ID:-}" ]]; then
  say "Detaching and deleting the internet gateway"
  quiet aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION"
  quiet aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$AWS_REGION"
  ok "Internet gateway deleted"
fi

# --- 9. The VPC itself -------------------------------------------------------
if [[ -n "${VPC_ID:-}" ]]; then
  say "Deleting the VPC"
  quiet aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$AWS_REGION"
  ok "VPC deleted"
fi

# --- 10. Clear our local bookkeeping ----------------------------------------
rm -f "$STATE_FILE"

say "TEARDOWN COMPLETE"
echo "  Verify nothing was missed (should print nothing):"
echo "    aws ec2 describe-vpcs --filters Name=tag:Project,Values=${PROJECT} --query 'Vpcs[].VpcId' --output text --region ${AWS_REGION}"
echo "    aws elbv2 describe-load-balancers --query \"LoadBalancers[?contains(LoadBalancerName,'${PROJECT}')].LoadBalancerName\" --output text --region ${AWS_REGION}"
echo
warn "Also check the Billing console in 24 hours to confirm charges have stopped."
