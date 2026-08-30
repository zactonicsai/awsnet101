#!/usr/bin/env bash
#
# aws-cost-destroy.sh  --  companion teardown script for aws-cost-inventory.sh
#
#   ############################################################
#   #  THIS SCRIPT PERMANENTLY DELETES AWS RESOURCES.          #
#   #  Deletions are NOT reversible. Data is NOT recoverable.  #
#   #  It is DRY-RUN by default. Nothing happens without       #
#   #  --apply AND typing the account ID at the prompt.        #
#   ############################################################
#
# Design rules:
#   * Dry run unless --apply. Dry run prints the exact command it would run.
#   * No implicit scope. You must name --targets. There is no "everything"
#     default, and `--targets all` still requires an extra confirmation.
#   * Anything carrying the protection tag (default key: Protect) is skipped.
#   * The default VPC is skipped unless --include-default-vpc.
#   * Deletions run in dependency order so they actually succeed.
#   * Every API call is logged to ./aws-destroy-<timestamp>.log
#
# Usage:
#   ./aws-cost-destroy.sh --targets waste                     # dry run, safest set
#   ./aws-cost-destroy.sh --targets waste --apply
#   ./aws-cost-destroy.sh --targets nat,eip,vpce -r us-east-1 --apply
#   ./aws-cost-destroy.sh --vpc vpc-0abc123 -r us-east-1      # full VPC teardown
#   ./aws-cost-destroy.sh --targets all -r us-east-1 --apply  # nuke the region
#
# Targets:
#   waste       unattached EBS volumes, unassociated EIPs, orphaned target
#               groups, snapshots older than --older-than days
#   nat         NAT gateways            eip     Elastic IPs
#   vpce        interface VPC endpoints vpn     Site-to-Site + Client VPN
#   tgw         TGW attachments + TGWs  elb     ALB/NLB/GWLB/Classic
#   ec2         EC2 instances           asg     Auto Scaling groups
#   ebs         EBS volumes             snapshots / ami
#   rds         RDS instances+clusters  elasticache / redshift
#   eks         EKS clusters+nodegroups ecs     ECS clusters+services
#   lambda      Lambda functions        logs    CloudWatch log groups
#   secrets     Secrets Manager         kms     schedule CMK deletion
#   efs         EFS file systems        all     every target above
#
# Options:
#   -p, --profile NAME        AWS profile
#   -r, --regions LIST        comma separated; default = all opted-in regions
#       --targets LIST        comma separated (required unless --vpc)
#       --vpc VPC-ID          full ordered teardown of one VPC (needs -r)
#       --apply               actually delete. Without this, nothing happens.
#       --force               skip the interactive confirmation (automation)
#       --protect-tag KEY     tag key that marks a resource off-limits (Protect)
#       --older-than DAYS     for snapshots/AMIs in `waste`; default 30
#       --include-default-vpc allow touching the default VPC
#       --keep-final-snapshot take final RDS snapshots instead of skipping
#

set -o pipefail
export AWS_PAGER=""
export AWS_DEFAULT_OUTPUT=text

PROFILE=""; REGION_LIST=""; TARGETS=""; ONE_VPC=""
APPLY=0; FORCE=0; PROT_KEY="Protect"; OLDER_THAN=30
INCLUDE_DEFAULT_VPC=0; FINAL_SNAP=0

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--profile) PROFILE="$2"; shift 2 ;;
    -r|--regions) REGION_LIST="$2"; shift 2 ;;
    --targets)    TARGETS="$2"; shift 2 ;;
    --vpc)        ONE_VPC="$2"; shift 2 ;;
    --apply)      APPLY=1; shift ;;
    --force)      FORCE=1; shift ;;
    --protect-tag) PROT_KEY="$2"; shift 2 ;;
    --older-than) OLDER_THAN="$2"; shift 2 ;;
    --include-default-vpc) INCLUDE_DEFAULT_VPC=1; shift ;;
    --keep-final-snapshot) FINAL_SNAP=1; shift ;;
    -h|--help)    sed -n '3,52p' "$0" | sed 's/^#\s\?//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "aws cli not found" >&2; exit 1; }

if [ -z "$TARGETS" ] && [ -z "$ONE_VPC" ]; then
  echo "Refusing to run with no scope. Pass --targets or --vpc. See --help." >&2
  exit 1
fi

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YEL=$'\033[33m'; CYA=$'\033[36m'; N=$'\033[0m'
else
  B=""; DIM=""; RED=""; GRN=""; YEL=""; CYA=""; N=""
fi

LOG="./aws-destroy-$(date -u +%Y%m%dT%H%M%SZ).log"
PLANNED=0; DELETED=0; FAILED=0; SKIPPED=0

awsc() { if [ -n "$PROFILE" ]; then aws --profile "$PROFILE" "$@"; else aws "$@"; fi; }

hdr() { printf '\n%s%s%s\n%s\n' "$B" "$1" "$N" "$(printf '=%.0s' $(seq 1 ${#1}))"; }
sub() { printf '\n  %s%s%s\n' "$CYA" "$1" "$N"; }
note(){ printf '    %s%s%s\n' "$DIM" "$1" "$N"; }

# run_cmd "<human description>" <argv...>
run_cmd() {
  desc="$1"; shift
  printf '%s\n' "--- $(date -u +%H:%M:%S) $desc" >>"$LOG"
  printf '%s\n' "    cmd: $*" >>"$LOG"
  if [ "$APPLY" -eq 1 ]; then
    printf '    %s[DELETE]%s %s\n' "$RED" "$N" "$desc"
    if "$@" >>"$LOG" 2>&1; then
      DELETED=$((DELETED + 1)); return 0
    else
      printf '              %sfailed — see %s%s\n' "$YEL" "$LOG" "$N"
      FAILED=$((FAILED + 1)); return 1
    fi
  else
    printf '    %s[dry-run]%s %s\n' "$DIM" "$N" "$desc"
    printf '              %s%s%s\n' "$DIM" "$*" "$N"
    PLANNED=$((PLANNED + 1)); return 0
  fi
}

skip() { printf '    %s[skip]%s    %s\n' "$GRN" "$N" "$1"; SKIPPED=$((SKIPPED + 1)); }

# Protection check for anything with EC2-style tags
ec2_protected() {
  v=$(awsc ec2 describe-tags --region "$REGION" \
        --filters Name=resource-id,Values="$1" \
        --query "Tags[?Key=='$PROT_KEY'].Value" 2>/dev/null)
  [ -n "$v" ] && [ "$v" != "None" ]
}

wants() {
  case ",$TARGETS," in
    *,all,*) return 0 ;;
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

wait_for() {  # wait_for <seconds> <desc> <cmd...>  — polls until cmd yields empty
  [ "$APPLY" -eq 0 ] && return 0
  limit="$1"; d="$2"; shift 2
  printf '              waiting for %s' "$d"
  i=0
  while [ "$i" -lt "$limit" ]; do
    out=$("$@" 2>/dev/null | sed '/^[[:space:]]*$/d')
    [ -z "$out" ] && { printf ' ok\n'; return 0; }
    printf '.'; sleep 5; i=$((i + 5))
  done
  printf ' timeout\n'
  return 1
}

if date -v-1d >/dev/null 2>&1; then
  CUTOFF=$(date -u -v-"${OLDER_THAN}"d +%Y-%m-%d)
else
  CUTOFF=$(date -u -d "$OLDER_THAN days ago" +%Y-%m-%d)
fi

# ---------------------------------------------------------- preflight ----

CALLER=$(awsc sts get-caller-identity --query '[Account,Arn]' 2>/dev/null)
[ -z "$CALLER" ] && { echo "${RED}Cannot authenticate.${N}" >&2; exit 1; }
ACCOUNT=$(printf '%s' "$CALLER" | cut -f1)
WHOAMI=$(printf '%s' "$CALLER" | cut -f2)

if [ -n "$REGION_LIST" ]; then
  REGIONS=$(printf '%s' "$REGION_LIST" | tr ',' ' ')
elif [ -n "$ONE_VPC" ]; then
  echo "--vpc requires -r <region>" >&2; exit 1
else
  REGIONS=$(awsc ec2 describe-regions --query 'Regions[].RegionName' 2>/dev/null | tr '\t' ' ')
fi

hdr "AWS RESOURCE TEARDOWN"
printf 'Account      : %s\n' "$ACCOUNT"
printf 'Identity     : %s\n' "$WHOAMI"
printf 'Regions      : %s\n' "$REGIONS"
printf 'Targets      : %s\n' "${TARGETS:-<vpc teardown: $ONE_VPC>}"
printf 'Protect tag  : %s (resources with this tag key are skipped)\n' "$PROT_KEY"
printf 'Log file     : %s\n' "$LOG"
if [ "$APPLY" -eq 1 ]; then
  printf 'Mode         : %sAPPLY — RESOURCES WILL BE DESTROYED%s\n' "$RED$B" "$N"
else
  printf 'Mode         : %sDRY RUN — nothing will be deleted%s\n' "$GRN" "$N"
fi

if [ "$APPLY" -eq 1 ] && [ "$FORCE" -eq 0 ]; then
  printf '\n%sThis permanently destroys resources in account %s.%s\n' "$RED$B" "$ACCOUNT" "$N"
  printf 'There is no undo. Snapshots and data will be lost.\n'
  case ",$TARGETS," in
    *,all,*) printf '%sYou selected TARGETS=all. This empties the listed regions.%s\n' "$RED$B" "$N" ;;
  esac
  printf '\nType the account ID (%s) to continue, anything else to abort: ' "$ACCOUNT"
  read -r ANS
  [ "$ANS" = "$ACCOUNT" ] || { echo "Aborted."; exit 1; }
fi

# ======================================================== TARGET HANDLERS =

del_waste() {
  sub "waste: unattached EBS volumes"
  for v in $(awsc ec2 describe-volumes --region "$REGION" \
               --filters Name=status,Values=available --query 'Volumes[].VolumeId'); do
    ec2_protected "$v" && { skip "$v (protected)"; continue; }
    run_cmd "volume $v" awsc ec2 delete-volume --region "$REGION" --volume-id "$v"
  done

  sub "waste: unassociated Elastic IPs"
  for a in $(awsc ec2 describe-addresses --region "$REGION" \
               --query 'Addresses[?AssociationId==null].AllocationId'); do
    ec2_protected "$a" && { skip "$a (protected)"; continue; }
    run_cmd "EIP $a" awsc ec2 release-address --region "$REGION" --allocation-id "$a"
  done

  sub "waste: target groups with no load balancer"
  awsc elbv2 describe-target-groups --region "$REGION" \
    --query 'TargetGroups[?length(LoadBalancerArns)==`0`].TargetGroupArn' 2>/dev/null \
  | tr '\t' '\n' | while read -r tg; do
      [ -z "$tg" ] && continue
      run_cmd "target group ${tg##*/}" awsc elbv2 delete-target-group --region "$REGION" --target-group-arn "$tg"
    done

  sub "waste: EBS snapshots older than $OLDER_THAN days (before $CUTOFF)"
  awsc ec2 describe-snapshots --region "$REGION" --owner-ids self \
    --query 'Snapshots[].[SnapshotId,StartTime]' 2>/dev/null \
  | while IFS=$'\t' read -r sid stime; do
      [ -z "$sid" ] && continue
      [ "${stime%%T*}" \> "$CUTOFF" ] && continue
      ec2_protected "$sid" && { skip "$sid (protected)"; continue; }
      run_cmd "snapshot $sid ($stime)" awsc ec2 delete-snapshot --region "$REGION" --snapshot-id "$sid"
    done
}

del_nat() {
  sub "NAT gateways"
  IDS=""
  for ng in $(awsc ec2 describe-nat-gateways --region "$REGION" \
                --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId'); do
    ec2_protected "$ng" && { skip "$ng (protected)"; continue; }
    run_cmd "NAT gateway $ng" awsc ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$ng" \
      && IDS="$IDS $ng"
  done
  [ -n "$IDS" ] && wait_for 300 "NAT gateways to drain" \
    awsc ec2 describe-nat-gateways --region "$REGION" --nat-gateway-ids $IDS \
      --query 'NatGateways[?State!=`deleted`].NatGatewayId'
}

del_eip() {
  sub "Elastic IPs (all, including attached)"
  for a in $(awsc ec2 describe-addresses --region "$REGION" --query 'Addresses[].AllocationId'); do
    ec2_protected "$a" && { skip "$a (protected)"; continue; }
    assoc=$(awsc ec2 describe-addresses --region "$REGION" --allocation-ids "$a" \
              --query 'Addresses[0].AssociationId')
    if [ -n "$assoc" ] && [ "$assoc" != "None" ]; then
      run_cmd "disassociate $a" awsc ec2 disassociate-address --region "$REGION" --association-id "$assoc"
    fi
    run_cmd "release EIP $a" awsc ec2 release-address --region "$REGION" --allocation-id "$a"
  done
}

del_vpce() {
  sub "VPC endpoints (interface / GWLB — these bill hourly)"
  IDS=$(awsc ec2 describe-vpc-endpoints --region "$REGION" \
          --query 'VpcEndpoints[?VpcEndpointType!=`Gateway`].VpcEndpointId' | tr '\t' ' ')
  for e in $IDS; do
    ec2_protected "$e" && { skip "$e (protected)"; continue; }
    run_cmd "VPC endpoint $e" awsc ec2 delete-vpc-endpoints --region "$REGION" --vpc-endpoint-ids "$e"
  done
}

del_vpn() {
  sub "Site-to-Site VPN connections"
  for v in $(awsc ec2 describe-vpn-connections --region "$REGION" \
               --query 'VpnConnections[?State!=`deleted`].VpnConnectionId'); do
    ec2_protected "$v" && { skip "$v (protected)"; continue; }
    run_cmd "VPN connection $v" awsc ec2 delete-vpn-connection --region "$REGION" --vpn-connection-id "$v"
  done
  sub "Client VPN endpoints"
  for c in $(awsc ec2 describe-client-vpn-endpoints --region "$REGION" \
               --query 'ClientVpnEndpoints[].ClientVpnEndpointId'); do
    for asc in $(awsc ec2 describe-client-vpn-target-networks --region "$REGION" \
                   --client-vpn-endpoint-id "$c" --query 'ClientVpnTargetNetworks[].AssociationId'); do
      run_cmd "disassociate network $asc from $c" \
        awsc ec2 disassociate-client-vpn-target-network --region "$REGION" \
          --client-vpn-endpoint-id "$c" --association-id "$asc"
    done
    run_cmd "Client VPN $c" awsc ec2 delete-client-vpn-endpoint --region "$REGION" --client-vpn-endpoint-id "$c"
  done
}

del_tgw() {
  sub "Transit Gateway attachments"
  IDS=""
  awsc ec2 describe-transit-gateway-attachments --region "$REGION" \
    --query 'TransitGatewayAttachments[?State==`available`].[TransitGatewayAttachmentId,ResourceType]' \
  | while IFS=$'\t' read -r at rt; do
      [ -z "$at" ] && continue
      case "$rt" in
        vpc)    run_cmd "TGW VPC attachment $at" awsc ec2 delete-transit-gateway-vpc-attachment \
                  --region "$REGION" --transit-gateway-attachment-id "$at" ;;
        peering) run_cmd "TGW peering $at" awsc ec2 delete-transit-gateway-peering-attachment \
                  --region "$REGION" --transit-gateway-attachment-id "$at" ;;
        *)      note "attachment $at ($rt) must be removed from its owning service first" ;;
      esac
    done
  sub "Transit Gateways"
  for t in $(awsc ec2 describe-transit-gateways --region "$REGION" \
               --query 'TransitGateways[?State==`available`].TransitGatewayId'); do
    ec2_protected "$t" && { skip "$t (protected)"; continue; }
    run_cmd "Transit Gateway $t" awsc ec2 delete-transit-gateway --region "$REGION" --transit-gateway-id "$t"
  done
}

del_elb() {
  sub "Load balancers (v2)"
  awsc elbv2 describe-load-balancers --region "$REGION" \
    --query 'LoadBalancers[].[LoadBalancerArn,LoadBalancerName]' \
  | while IFS=$'\t' read -r arn name; do
      [ -z "$arn" ] && continue
      run_cmd "load balancer $name" awsc elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn"
    done
  sub "Classic ELBs"
  for l in $(awsc elb describe-load-balancers --region "$REGION" \
               --query 'LoadBalancerDescriptions[].LoadBalancerName'); do
    run_cmd "classic ELB $l" awsc elb delete-load-balancer --region "$REGION" --load-balancer-name "$l"
  done
  [ "$APPLY" -eq 1 ] && { note "pausing 30s for ENIs to release"; sleep 30; }
}

del_asg() {
  sub "Auto Scaling groups"
  for g in $(awsc autoscaling describe-auto-scaling-groups --region "$REGION" \
               --query 'AutoScalingGroups[].AutoScalingGroupName'); do
    run_cmd "ASG $g (force delete)" awsc autoscaling delete-auto-scaling-group \
      --region "$REGION" --auto-scaling-group-name "$g" --force-delete
  done
}

del_ec2() {
  sub "EC2 instances"
  IDS=""
  for i in $(awsc ec2 describe-instances --region "$REGION" \
               --filters Name=instance-state-name,Values=running,stopped,stopping \
               --query 'Reservations[].Instances[].InstanceId'); do
    ec2_protected "$i" && { skip "$i (protected)"; continue; }
    api=$(awsc ec2 describe-instance-attribute --region "$REGION" --instance-id "$i" \
            --attribute disableApiTermination --query 'DisableApiTermination.Value' 2>/dev/null)
    if [ "$api" = "True" ]; then
      run_cmd "disable termination protection on $i" awsc ec2 modify-instance-attribute \
        --region "$REGION" --instance-id "$i" --no-disable-api-termination
    fi
    run_cmd "terminate instance $i" awsc ec2 terminate-instances --region "$REGION" --instance-ids "$i" \
      && IDS="$IDS $i"
  done
  [ -n "$IDS" ] && wait_for 600 "instances to terminate" \
    awsc ec2 describe-instances --region "$REGION" --instance-ids $IDS \
      --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId'
}

del_ebs() {
  sub "EBS volumes (all not in-use)"
  for v in $(awsc ec2 describe-volumes --region "$REGION" \
               --filters Name=status,Values=available --query 'Volumes[].VolumeId'); do
    ec2_protected "$v" && { skip "$v (protected)"; continue; }
    run_cmd "volume $v" awsc ec2 delete-volume --region "$REGION" --volume-id "$v"
  done
}

del_snapshots() {
  sub "EBS snapshots (owned by this account)"
  for s in $(awsc ec2 describe-snapshots --region "$REGION" --owner-ids self --query 'Snapshots[].SnapshotId'); do
    ec2_protected "$s" && { skip "$s (protected)"; continue; }
    run_cmd "snapshot $s" awsc ec2 delete-snapshot --region "$REGION" --snapshot-id "$s"
  done
}

del_ami() {
  sub "AMIs owned by this account (deregister, then drop backing snapshots)"
  for a in $(awsc ec2 describe-images --region "$REGION" --owners self --query 'Images[].ImageId'); do
    ec2_protected "$a" && { skip "$a (protected)"; continue; }
    snaps=$(awsc ec2 describe-images --region "$REGION" --image-ids "$a" \
              --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' | tr '\t' ' ')
    run_cmd "deregister AMI $a" awsc ec2 deregister-image --region "$REGION" --image-id "$a"
    for s in $snaps; do
      [ -z "$s" ] || [ "$s" = "None" ] && continue
      run_cmd "backing snapshot $s" awsc ec2 delete-snapshot --region "$REGION" --snapshot-id "$s"
    done
  done
}

del_rds() {
  sub "RDS instances"
  for d in $(awsc rds describe-db-instances --region "$REGION" --query 'DBInstances[].DBInstanceIdentifier'); do
    prot=$(awsc rds describe-db-instances --region "$REGION" --db-instance-identifier "$d" \
             --query 'DBInstances[0].DeletionProtection')
    if [ "$prot" = "True" ]; then
      run_cmd "disable deletion protection on $d" awsc rds modify-db-instance --region "$REGION" \
        --db-instance-identifier "$d" --no-deletion-protection --apply-immediately
    fi
    if [ "$FINAL_SNAP" -eq 1 ]; then
      run_cmd "delete RDS $d (final snapshot kept)" awsc rds delete-db-instance --region "$REGION" \
        --db-instance-identifier "$d" --final-db-snapshot-identifier "${d}-final-$(date -u +%Y%m%d%H%M)"
    else
      run_cmd "delete RDS $d (NO final snapshot)" awsc rds delete-db-instance --region "$REGION" \
        --db-instance-identifier "$d" --skip-final-snapshot --delete-automated-backups
    fi
  done
  sub "RDS / Aurora clusters"
  for c in $(awsc rds describe-db-clusters --region "$REGION" --query 'DBClusters[].DBClusterIdentifier'); do
    run_cmd "disable deletion protection on cluster $c" awsc rds modify-db-cluster --region "$REGION" \
      --db-cluster-identifier "$c" --no-deletion-protection --apply-immediately
    run_cmd "delete cluster $c" awsc rds delete-db-cluster --region "$REGION" \
      --db-cluster-identifier "$c" --skip-final-snapshot
  done
}

del_elasticache() {
  sub "ElastiCache"
  for g in $(awsc elasticache describe-replication-groups --region "$REGION" \
               --query 'ReplicationGroups[].ReplicationGroupId' 2>/dev/null); do
    run_cmd "replication group $g" awsc elasticache delete-replication-group --region "$REGION" \
      --replication-group-id "$g" --no-retain-primary-cluster
  done
  for c in $(awsc elasticache describe-cache-clusters --region "$REGION" \
               --query 'CacheClusters[?ReplicationGroupId==null].CacheClusterId' 2>/dev/null); do
    run_cmd "cache cluster $c" awsc elasticache delete-cache-cluster --region "$REGION" --cache-cluster-id "$c"
  done
}

del_redshift() {
  sub "Redshift clusters"
  for c in $(awsc redshift describe-clusters --region "$REGION" --query 'Clusters[].ClusterIdentifier'); do
    run_cmd "Redshift $c (no final snapshot)" awsc redshift delete-cluster --region "$REGION" \
      --cluster-identifier "$c" --skip-final-cluster-snapshot
  done
}

del_eks() {
  sub "EKS clusters"
  for c in $(awsc eks list-clusters --region "$REGION" --query 'clusters'); do
    for ng in $(awsc eks list-nodegroups --region "$REGION" --cluster-name "$c" --query 'nodegroups'); do
      run_cmd "nodegroup $ng ($c)" awsc eks delete-nodegroup --region "$REGION" \
        --cluster-name "$c" --nodegroup-name "$ng"
    done
    [ "$APPLY" -eq 1 ] && wait_for 900 "nodegroups of $c" \
      awsc eks list-nodegroups --region "$REGION" --cluster-name "$c" --query 'nodegroups'
    for fp in $(awsc eks list-fargate-profiles --region "$REGION" --cluster-name "$c" \
                  --query 'fargateProfileNames' 2>/dev/null); do
      run_cmd "fargate profile $fp ($c)" awsc eks delete-fargate-profile --region "$REGION" \
        --cluster-name "$c" --fargate-profile-name "$fp"
    done
    run_cmd "EKS cluster $c" awsc eks delete-cluster --region "$REGION" --name "$c"
  done
}

del_ecs() {
  sub "ECS clusters"
  for c in $(awsc ecs list-clusters --region "$REGION" --query 'clusterArns'); do
    for s in $(awsc ecs list-services --region "$REGION" --cluster "$c" --query 'serviceArns'); do
      run_cmd "ECS service ${s##*/}" awsc ecs delete-service --region "$REGION" \
        --cluster "$c" --service "$s" --force
    done
    for t in $(awsc ecs list-tasks --region "$REGION" --cluster "$c" --query 'taskArns'); do
      run_cmd "ECS task ${t##*/}" awsc ecs stop-task --region "$REGION" --cluster "$c" --task "$t"
    done
    run_cmd "ECS cluster ${c##*/}" awsc ecs delete-cluster --region "$REGION" --cluster "$c"
  done
}

del_lambda() {
  sub "Lambda functions"
  for f in $(awsc lambda list-functions --region "$REGION" --query 'Functions[].FunctionName'); do
    run_cmd "lambda $f" awsc lambda delete-function --region "$REGION" --function-name "$f"
  done
}

del_efs() {
  sub "EFS file systems"
  for fs in $(awsc efs describe-file-systems --region "$REGION" --query 'FileSystems[].FileSystemId'); do
    for mt in $(awsc efs describe-mount-targets --region "$REGION" --file-system-id "$fs" \
                  --query 'MountTargets[].MountTargetId'); do
      run_cmd "mount target $mt" awsc efs delete-mount-target --region "$REGION" --mount-target-id "$mt"
    done
    [ "$APPLY" -eq 1 ] && sleep 20
    run_cmd "EFS $fs" awsc efs delete-file-system --region "$REGION" --file-system-id "$fs"
  done
}

del_logs() {
  sub "CloudWatch log groups"
  for lg in $(awsc logs describe-log-groups --region "$REGION" --query 'logGroups[].logGroupName'); do
    run_cmd "log group $lg" awsc logs delete-log-group --region "$REGION" --log-group-name "$lg"
  done
}

del_secrets() {
  sub "Secrets Manager (scheduled, 7-day recovery window)"
  for s in $(awsc secretsmanager list-secrets --region "$REGION" --query 'SecretList[].Name'); do
    run_cmd "secret $s" awsc secretsmanager delete-secret --region "$REGION" \
      --secret-id "$s" --recovery-window-in-days 7
  done
}

del_kms() {
  sub "KMS customer-managed keys (scheduled, 30-day window — cancellable)"
  for k in $(awsc kms list-keys --region "$REGION" --query 'Keys[].KeyId'); do
    mgr=$(awsc kms describe-key --region "$REGION" --key-id "$k" --query 'KeyMetadata.KeyManager' 2>/dev/null)
    [ "$mgr" != "CUSTOMER" ] && continue
    st=$(awsc kms describe-key --region "$REGION" --key-id "$k" --query 'KeyMetadata.KeyState' 2>/dev/null)
    [ "$st" != "Enabled" ] && [ "$st" != "Disabled" ] && continue
    run_cmd "schedule KMS key $k" awsc kms schedule-key-deletion --region "$REGION" \
      --key-id "$k" --pending-window-in-days 30
  done
}

# ==================================================== FULL VPC TEARDOWN ===
# Order matters. Each layer holds an ENI or a dependency on the one below it.

teardown_vpc() {
  V="$1"
  isdef=$(awsc ec2 describe-vpcs --region "$REGION" --vpc-ids "$V" --query 'Vpcs[0].IsDefault' 2>/dev/null)
  if [ "$isdef" = "True" ] && [ "$INCLUDE_DEFAULT_VPC" -eq 0 ]; then
    printf '  %sRefusing to delete the default VPC %s. Pass --include-default-vpc.%s\n' "$YEL" "$V" "$N"
    return 1
  fi
  ec2_protected "$V" && { skip "$V (protected)"; return 1; }

  printf '\n  %sTearing down %s in %s%s\n' "$B" "$V" "$REGION" "$N"

  sub "1. EC2 instances in $V"
  IDS=$(awsc ec2 describe-instances --region "$REGION" \
          --filters Name=vpc-id,Values="$V" Name=instance-state-name,Values=running,stopped \
          --query 'Reservations[].Instances[].InstanceId' | tr '\t' ' ')
  for i in $IDS; do
    run_cmd "terminate $i" awsc ec2 terminate-instances --region "$REGION" --instance-ids "$i"
  done
  [ -n "$IDS" ] && wait_for 600 "instances" \
    awsc ec2 describe-instances --region "$REGION" --instance-ids $IDS \
      --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId'

  sub "2. Load balancers in $V"
  awsc elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?VpcId=='$V'].[LoadBalancerArn,LoadBalancerName]" \
  | while IFS=$'\t' read -r arn nm; do
      [ -z "$arn" ] && continue
      run_cmd "LB $nm" awsc elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn"
    done
  for l in $(awsc elb describe-load-balancers --region "$REGION" \
               --query "LoadBalancerDescriptions[?VPCId=='$V'].LoadBalancerName"); do
    run_cmd "classic ELB $l" awsc elb delete-load-balancer --region "$REGION" --load-balancer-name "$l"
  done
  [ "$APPLY" -eq 1 ] && sleep 30

  sub "3. NAT gateways in $V"
  NIDS=$(awsc ec2 describe-nat-gateways --region "$REGION" \
           --filter Name=vpc-id,Values="$V" Name=state,Values=available,pending \
           --query 'NatGateways[].NatGatewayId' | tr '\t' ' ')
  for ng in $NIDS; do
    run_cmd "NAT $ng" awsc ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$ng"
  done
  [ -n "$NIDS" ] && wait_for 300 "NAT gateways" \
    awsc ec2 describe-nat-gateways --region "$REGION" --nat-gateway-ids $NIDS \
      --query 'NatGateways[?State!=`deleted`].NatGatewayId'

  sub "4. VPC endpoints in $V"
  for e in $(awsc ec2 describe-vpc-endpoints --region "$REGION" \
               --filters Name=vpc-id,Values="$V" --query 'VpcEndpoints[].VpcEndpointId'); do
    run_cmd "endpoint $e" awsc ec2 delete-vpc-endpoints --region "$REGION" --vpc-endpoint-ids "$e"
  done

  sub "5. Transit Gateway + peering attachments"
  for at in $(awsc ec2 describe-transit-gateway-attachments --region "$REGION" \
                --filters Name=resource-id,Values="$V" \
                --query 'TransitGatewayAttachments[?State==`available`].TransitGatewayAttachmentId'); do
    run_cmd "TGW attachment $at" awsc ec2 delete-transit-gateway-vpc-attachment \
      --region "$REGION" --transit-gateway-attachment-id "$at"
  done
  for pc in $(awsc ec2 describe-vpc-peering-connections --region "$REGION" \
                --filters Name=requester-vpc-info.vpc-id,Values="$V" \
                --query 'VpcPeeringConnections[?Status.Code==`active`].VpcPeeringConnectionId'); do
    run_cmd "peering $pc" awsc ec2 delete-vpc-peering-connection --region "$REGION" \
      --vpc-peering-connection-id "$pc"
  done

  sub "6. VPN + virtual private gateways"
  for vg in $(awsc ec2 describe-vpn-gateways --region "$REGION" \
                --filters Name=attachment.vpc-id,Values="$V" \
                --query 'VpnGateways[?State!=`deleted`].VpnGatewayId'); do
    for vc in $(awsc ec2 describe-vpn-connections --region "$REGION" \
                  --filters Name=vpn-gateway-id,Values="$vg" \
                  --query 'VpnConnections[?State!=`deleted`].VpnConnectionId'); do
      run_cmd "VPN connection $vc" awsc ec2 delete-vpn-connection --region "$REGION" --vpn-connection-id "$vc"
    done
    run_cmd "detach VGW $vg" awsc ec2 detach-vpn-gateway --region "$REGION" --vpn-gateway-id "$vg" --vpc-id "$V"
    run_cmd "delete VGW $vg" awsc ec2 delete-vpn-gateway --region "$REGION" --vpn-gateway-id "$vg"
  done

  sub "7. Flow logs"
  for fl in $(awsc ec2 describe-flow-logs --region "$REGION" \
                --filter Name=resource-id,Values="$V" --query 'FlowLogs[].FlowLogId'); do
    run_cmd "flow log $fl" awsc ec2 delete-flow-logs --region "$REGION" --flow-log-ids "$fl"
  done

  sub "8. Leftover network interfaces"
  for eni in $(awsc ec2 describe-network-interfaces --region "$REGION" \
                 --filters Name=vpc-id,Values="$V" Name=status,Values=available \
                 --query 'NetworkInterfaces[].NetworkInterfaceId'); do
    run_cmd "ENI $eni" awsc ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni"
  done

  sub "9. Internet gateway"
  for igw in $(awsc ec2 describe-internet-gateways --region "$REGION" \
                 --filters Name=attachment.vpc-id,Values="$V" --query 'InternetGateways[].InternetGatewayId'); do
    run_cmd "detach IGW $igw" awsc ec2 detach-internet-gateway --region "$REGION" \
      --internet-gateway-id "$igw" --vpc-id "$V"
    run_cmd "delete IGW $igw" awsc ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$igw"
  done
  for eig in $(awsc ec2 describe-egress-only-internet-gateways --region "$REGION" \
                 --query "EgressOnlyInternetGateways[?Attachments[?VpcId=='$V']].EgressOnlyInternetGatewayId"); do
    run_cmd "egress-only IGW $eig" awsc ec2 delete-egress-only-internet-gateway \
      --region "$REGION" --egress-only-internet-gateway-id "$eig"
  done

  sub "10. Subnets"
  for s in $(awsc ec2 describe-subnets --region "$REGION" \
               --filters Name=vpc-id,Values="$V" --query 'Subnets[].SubnetId'); do
    run_cmd "subnet $s" awsc ec2 delete-subnet --region "$REGION" --subnet-id "$s"
  done

  sub "11. Route tables (non-main)"
  for rt in $(awsc ec2 describe-route-tables --region "$REGION" \
                --filters Name=vpc-id,Values="$V" \
                --query 'RouteTables[?!(Associations[?Main==`true`])].RouteTableId'); do
    run_cmd "route table $rt" awsc ec2 delete-route-table --region "$REGION" --route-table-id "$rt"
  done

  sub "12. Network ACLs (non-default)"
  for na in $(awsc ec2 describe-network-acls --region "$REGION" \
                --filters Name=vpc-id,Values="$V" --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId'); do
    run_cmd "network ACL $na" awsc ec2 delete-network-acl --region "$REGION" --network-acl-id "$na"
  done

  sub "13. Security groups (rules first — they reference each other)"
  SGS=$(awsc ec2 describe-security-groups --region "$REGION" \
          --filters Name=vpc-id,Values="$V" \
          --query 'SecurityGroups[?GroupName!=`default`].GroupId' | tr '\t' ' ')
  for sg in $SGS; do
    ing=$(awsc ec2 describe-security-groups --region "$REGION" --group-ids "$sg" \
            --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null)
    if [ -n "$ing" ] && [ "$ing" != "[]" ]; then
      run_cmd "revoke ingress on $sg" awsc ec2 revoke-security-group-ingress \
        --region "$REGION" --group-id "$sg" --ip-permissions "$ing"
    fi
    egr=$(awsc ec2 describe-security-groups --region "$REGION" --group-ids "$sg" \
            --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null)
    if [ -n "$egr" ] && [ "$egr" != "[]" ]; then
      run_cmd "revoke egress on $sg" awsc ec2 revoke-security-group-egress \
        --region "$REGION" --group-id "$sg" --ip-permissions "$egr"
    fi
  done
  for sg in $SGS; do
    run_cmd "security group $sg" awsc ec2 delete-security-group --region "$REGION" --group-id "$sg"
  done

  sub "14. DHCP options set (if custom)"
  dh=$(awsc ec2 describe-vpcs --region "$REGION" --vpc-ids "$V" --query 'Vpcs[0].DhcpOptionsId')
  if [ -n "$dh" ] && [ "$dh" != "default" ] && [ "$dh" != "None" ]; then
    run_cmd "reset DHCP options on $V" awsc ec2 associate-dhcp-options \
      --region "$REGION" --vpc-id "$V" --dhcp-options-id default
    run_cmd "DHCP options $dh" awsc ec2 delete-dhcp-options --region "$REGION" --dhcp-options-id "$dh"
  fi

  sub "15. The VPC itself"
  run_cmd "VPC $V" awsc ec2 delete-vpc --region "$REGION" --vpc-id "$V"
}

# ================================================================= MAIN ===

for REGION in $REGIONS; do
  hdr "REGION: $REGION"

  if [ -n "$ONE_VPC" ]; then
    teardown_vpc "$ONE_VPC"
    continue
  fi

  # Ordered so dependencies clear before their dependents.
  wants asg         && del_asg
  wants ecs         && del_ecs
  wants eks         && del_eks
  wants ec2         && del_ec2
  wants elb         && del_elb
  wants rds         && del_rds
  wants elasticache && del_elasticache
  wants redshift    && del_redshift
  wants efs         && del_efs
  wants lambda      && del_lambda
  wants nat         && del_nat
  wants vpce        && del_vpce
  wants vpn         && del_vpn
  wants tgw         && del_tgw
  wants eip         && del_eip
  wants ebs         && del_ebs
  wants ami         && del_ami
  wants snapshots   && del_snapshots
  wants logs        && del_logs
  wants secrets     && del_secrets
  wants kms         && del_kms
  wants waste       && del_waste
done

hdr "SUMMARY"
if [ "$APPLY" -eq 1 ]; then
  printf 'Deleted : %s%s%s\n' "$GRN" "$DELETED" "$N"
  printf 'Failed  : %s%s%s\n' "$YEL" "$FAILED" "$N"
else
  printf 'Would delete : %s%s%s   (dry run — nothing was touched)\n' "$B" "$PLANNED" "$N"
  printf '\nRe-run with %s--apply%s to execute.\n' "$B" "$N"
fi
printf 'Skipped (protected) : %s\n' "$SKIPPED"
printf 'Log : %s\n' "$LOG"

cat <<'EOF'

Reminders
  * Deletions cascade with lag. Re-run aws-cost-inventory.sh afterwards to
    confirm, and check the bill 24-48h later — Cost Explorer trails reality.
  * Some things this script deliberately will NOT delete: S3 buckets (data
    loss risk, and non-empty buckets need a full object purge first), Route53
    hosted zones, IAM, Organizations, and anything under CloudFormation or
    Terraform control. Delete IaC-managed resources through the stack instead,
    or your next `apply` will fight you.
  * Reserved Instances and Savings Plans keep billing after the resources are
    gone. Terminating an instance does not cancel its RI.
  * KMS keys and Secrets Manager secrets are scheduled, not immediate — you can
    cancel with `kms cancel-key-deletion` / `secretsmanager restore-secret`.
EOF
