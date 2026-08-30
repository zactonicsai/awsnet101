#!/usr/bin/env bash
#
# aws-cost-inventory.sh
#
# Reports everything in an AWS account that generates a charge:
#   1. Actual spend from Cost Explorer (by service, by region, by usage type)
#   2. A per-region inventory of billable resources
#   3. A VPC-specific pass (NAT GWs, endpoints, public IPv4, VPN, TGW...)
#   4. A "likely waste" section (unattached volumes, idle EIPs, etc.)
#
# Read-only. Never mutates anything.
#
# Requires: awscli v2. (jq is NOT required.)
#
# Usage:
#   ./aws-cost-inventory.sh                       # all opted-in regions, last 30 days
#   ./aws-cost-inventory.sh -p prod -d 60         # named profile, 60 days of cost data
#   ./aws-cost-inventory.sh -r us-east-1,eu-west-1
#   ./aws-cost-inventory.sh --detail              # list every resource ID, not just counts
#   ./aws-cost-inventory.sh --no-cost             # skip Cost Explorer (it bills $0.01/call)
#

set -o pipefail
export AWS_PAGER=""
export AWS_DEFAULT_OUTPUT=text

PROFILE=""
REGION_LIST=""
DAYS=30
DETAIL=0
SKIP_CE=0

# ---------------------------------------------------------------- args ----

usage() {
  sed -n '3,25p' "$0" | sed 's/^#\s\?//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--profile) PROFILE="$2"; shift 2 ;;
    -r|--regions) REGION_LIST="$2"; shift 2 ;;
    -d|--days)    DAYS="$2";    shift 2 ;;
    -v|--detail)  DETAIL=1;     shift ;;
    --no-cost)    SKIP_CE=1;    shift ;;
    -h|--help)    usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "aws cli not found on PATH" >&2; exit 1; }

# ------------------------------------------------------------- helpers ----

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; YEL=$'\033[33m'; CYA=$'\033[36m'; RED=$'\033[31m'; N=$'\033[0m'
else
  B=""; DIM=""; YEL=""; CYA=""; RED=""; N=""
fi

awsc() {
  if [ -n "$PROFILE" ]; then aws --profile "$PROFILE" "$@"; else aws "$@"; fi
}

hdr()  { printf '\n%s%s%s\n' "$B" "$1" "$N"; printf '%s\n' "$(printf '=%.0s' $(seq 1 ${#1}))"; }
sub()  { printf '\n  %s%s%s\n' "$CYA" "$1" "$N"; }

# _res <show-details 0|1> <label> <command...>
# Runs the command, counts non-empty output lines, prints a tidy line.
# API errors (no permission, service absent in region) are swallowed unless --detail.
_res() {
  show="$1"; label="$2"; shift 2
  out=$("$@" 2>/dev/null)
  rc=$?
  if [ $rc -ne 0 ]; then
    [ "$DETAIL" -eq 1 ] && printf '    %-42s %s\n' "$label" "${DIM}skipped (no access / n/a here)${N}"
    return 0
  fi
  out=$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d')
  n=$(printf '%s' "$out" | grep -c '')
  [ "$n" -eq 0 ] && { [ "$DETAIL" -eq 1 ] && printf '    %-42s %s\n' "$label" "${DIM}0${N}"; return 0; }

  FINDINGS=$((FINDINGS + n))
  printf '    %-42s %s%s%s\n' "$label" "$YEL" "$n" "$N"
  if [ "$show" -eq 1 ] || [ "$DETAIL" -eq 1 ]; then
    printf '%s\n' "$out" | sed 's/^/        /' | expand -t 4
  fi
}
res()  { _res 0 "$@"; }   # count only
resd() { _res 1 "$@"; }   # count + always show the resource IDs

# --------------------------------------------------------------- dates ----

if date -v-1d >/dev/null 2>&1; then           # BSD / macOS
  START=$(date -u -v-"${DAYS}"d +%Y-%m-%d)
  END=$(date -u -v+1d +%Y-%m-%d)
  MSTART=$(date -u +%Y-%m-01)
else                                          # GNU
  START=$(date -u -d "$DAYS days ago" +%Y-%m-%d)
  END=$(date -u -d "tomorrow" +%Y-%m-%d)
  MSTART=$(date -u +%Y-%m-01)
fi

# -------------------------------------------------------------- identity --

CALLER=$(awsc sts get-caller-identity --query '[Account,Arn]' 2>/dev/null)
if [ -z "$CALLER" ]; then
  echo "${RED}Could not authenticate. Check your credentials/profile.${N}" >&2
  exit 1
fi
ACCOUNT=$(printf '%s' "$CALLER" | cut -f1)
WHOAMI=$(printf '%s' "$CALLER" | cut -f2)

if [ -n "$REGION_LIST" ]; then
  REGIONS=$(printf '%s' "$REGION_LIST" | tr ',' ' ')
else
  REGIONS=$(awsc ec2 describe-regions --query 'Regions[].RegionName' 2>/dev/null | tr '\t' ' ')
  [ -z "$REGIONS" ] && REGIONS="us-east-1"
fi

hdr "AWS BILLABLE RESOURCE INVENTORY"
printf 'Account   : %s\n' "$ACCOUNT"
printf 'Identity  : %s\n' "$WHOAMI"
printf 'Generated : %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
printf 'Regions   : %s\n' "$(printf '%s' "$REGIONS" | wc -w | tr -d ' ') opted-in"

# ================================================================ COSTS ===
# Cost Explorer only answers on the us-east-1 endpoint. Each call costs $0.01.

ce() { awsc ce --region us-east-1 "$@"; }

money_sort() {
  awk -F'\t' '{ c[$1] += $2 } END { for (k in c) if (c[k] > 0.005) printf "%12.2f  %s\n", c[k], k }' \
    | sort -rn
}

if [ "$SKIP_CE" -eq 0 ]; then
  hdr "1. ACTUAL SPEND  (${START} .. today)"

  TOTAL=$(ce get-cost-and-usage \
      --time-period Start="$START",End="$END" \
      --granularity MONTHLY --metrics UnblendedCost \
      --query 'ResultsByTime[].Total.UnblendedCost.Amount' 2>/dev/null \
      | tr '\t' '\n' | awk '{s+=$1} END {printf "%.2f", s}')

  if [ -z "$TOTAL" ]; then
    printf '  %sCost Explorer unavailable.%s Enable it in Billing console and grant\n' "$RED" "$N"
    printf '  ce:GetCostAndUsage, or rerun with --no-cost.\n'
  else
    printf '\n  Total unblended cost: %s$%s USD%s\n' "$B" "$TOTAL" "$N"

    sub "By service (USD)"
    ce get-cost-and-usage \
      --time-period Start="$START",End="$END" \
      --granularity MONTHLY --metrics UnblendedCost \
      --group-by Type=DIMENSION,Key=SERVICE \
      --query 'ResultsByTime[].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' 2>/dev/null \
      | money_sort | sed 's/^/    /'

    sub "By region (USD)"
    ce get-cost-and-usage \
      --time-period Start="$START",End="$END" \
      --granularity MONTHLY --metrics UnblendedCost \
      --group-by Type=DIMENSION,Key=REGION \
      --query 'ResultsByTime[].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' 2>/dev/null \
      | money_sort | sed 's/^/    /'

    sub "VPC + EC2-Other usage types (NAT GW, endpoints, public IPv4, EBS, transfer)"
    ce get-cost-and-usage \
      --time-period Start="$START",End="$END" \
      --granularity MONTHLY --metrics UnblendedCost \
      --group-by Type=DIMENSION,Key=USAGE_TYPE \
      --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Virtual Private Cloud","EC2 - Other"]}}' \
      --query 'ResultsByTime[].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' 2>/dev/null \
      | money_sort | sed 's/^/    /'

    sub "Month-to-date forecast"
    ce get-cost-forecast \
      --time-period Start="$END",End="$(date -u -d '+30 days' +%Y-%m-%d 2>/dev/null || date -u -v+30d +%Y-%m-%d)" \
      --granularity MONTHLY --metric UNBLENDED_COST \
      --query 'Total.Amount' 2>/dev/null \
      | awk '{printf "    next 30 days (forecast): $%.2f\n", $1}'
  fi
fi

# ================================================== GLOBAL / NON-REGIONAL =

hdr "2. GLOBAL SERVICES"
FINDINGS=0

sub "Storage & content delivery"
res  "S3 buckets"                          awsc s3api list-buckets --query 'Buckets[].Name'
res  "CloudFront distributions"            awsc cloudfront list-distributions --query 'DistributionList.Items[].[Id,DomainName,Status]'
res  "Route53 hosted zones (\$0.50/mo ea)"  awsc route53 list-hosted-zones --query 'HostedZones[].[Id,Name]'
res  "Route53 health checks"               awsc route53 list-health-checks --query 'HealthChecks[].Id'
res  "Route53 domains registered"          awsc route53domains list-domains --region us-east-1 --query 'Domains[].DomainName'

sub "Global networking & edge"
resd "Global Accelerators (\$0.025/hr ea)"  awsc globalaccelerator list-accelerators --region us-west-2 --query 'Accelerators[].[Name,Status]'
res  "WAF (CloudFront scope) web ACLs"     awsc wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query 'WebACLs[].Name'

sub "Identity & directory"
res  "IAM roles"                           awsc iam list-roles --query 'Roles[].RoleName'
res  "ACM Private CAs (\$400/mo ea)"        awsc acm-pca list-certificate-authorities --region us-east-1 --query 'CertificateAuthorities[?Status==`ACTIVE`].Arn'

# ============================================================ PER-REGION ==

hdr "3. PER-REGION BILLABLE RESOURCES"

for r in $REGIONS; do
  BEFORE=$FINDINGS
  BUF=$(printf '\n%s--- %s ---%s\n' "$B" "$r" "$N")
  printf '%s' "$BUF"

  # -- The VPC pieces that actually cost money -----------------------------
  sub "VPC / networking  [${r}]"
  res  "VPCs (container, free)" \
       awsc ec2 describe-vpcs --region "$r" --query 'Vpcs[].[VpcId,CidrBlock,IsDefault]'
  resd "NAT Gateways  (~\$32/mo + data ea)" \
       awsc ec2 describe-nat-gateways --region "$r" \
         --filter Name=state,Values=available,pending \
         --query 'NatGateways[].[NatGatewayId,VpcId,SubnetId,State]'
  resd "Interface/GWLB endpoints (~\$7/mo/AZ)" \
       awsc ec2 describe-vpc-endpoints --region "$r" \
         --query 'VpcEndpoints[?VpcEndpointType!=`Gateway`].[VpcEndpointId,ServiceName,VpcEndpointType]'
  res  "Gateway endpoints (S3/DDB, free)" \
       awsc ec2 describe-vpc-endpoints --region "$r" \
         --query 'VpcEndpoints[?VpcEndpointType==`Gateway`].[VpcEndpointId,ServiceName]'
  resd "Elastic IPs  (\$3.60/mo each, always)" \
       awsc ec2 describe-addresses --region "$r" \
         --query 'Addresses[].[PublicIp,AllocationId,InstanceId,AssociationId]'
  resd "Site-to-Site VPN  (~\$36/mo each)" \
       awsc ec2 describe-vpn-connections --region "$r" \
         --query 'VpnConnections[?State!=`deleted`].[VpnConnectionId,State,VpnGatewayId]'
  resd "Client VPN endpoints (~\$72/mo + user hrs)" \
       awsc ec2 describe-client-vpn-endpoints --region "$r" \
         --query 'ClientVpnEndpoints[].[ClientVpnEndpointId,Status.Code]'
  resd "Transit Gateways (~\$36/mo each)" \
       awsc ec2 describe-transit-gateways --region "$r" \
         --query 'TransitGateways[?State==`available`].[TransitGatewayId,Description]'
  resd "TGW attachments (~\$36/mo each)" \
       awsc ec2 describe-transit-gateway-attachments --region "$r" \
         --query 'TransitGatewayAttachments[?State==`available`].[TransitGatewayAttachmentId,ResourceType,ResourceId]'
  res  "VPC peering connections (data xfer)" \
       awsc ec2 describe-vpc-peering-connections --region "$r" \
         --query 'VpcPeeringConnections[?Status.Code==`active`].VpcPeeringConnectionId'
  res  "Traffic mirror sessions" \
       awsc ec2 describe-traffic-mirror-sessions --region "$r" --query 'TrafficMirrorSessions[].TrafficMirrorSessionId'
  res  "VPC flow logs (CW/S3 ingest cost)" \
       awsc ec2 describe-flow-logs --region "$r" --query 'FlowLogs[].[FlowLogId,LogDestinationType]'
  resd "ALB/NLB/GWLB (~\$16/mo + LCU ea)" \
       awsc elbv2 describe-load-balancers --region "$r" \
         --query 'LoadBalancers[].[LoadBalancerName,Type,Scheme]'
  resd "Classic ELBs (~\$18/mo each)" \
       awsc elb describe-load-balancers --region "$r" \
         --query 'LoadBalancerDescriptions[].LoadBalancerName'
  res  "Direct Connect virtual interfaces" \
       awsc directconnect describe-virtual-interfaces --region "$r" \
         --query 'virtualInterfaces[?virtualInterfaceState==`available`].[virtualInterfaceId,connectionId]'

  # -- Compute ------------------------------------------------------------
  sub "Compute  [${r}]"
  res  "EC2 instances RUNNING" \
       awsc ec2 describe-instances --region "$r" \
         --filters Name=instance-state-name,Values=running \
         --query 'Reservations[].Instances[].[InstanceId,InstanceType,PublicIpAddress]'
  res  "EC2 instances STOPPED (EBS still bills)" \
       awsc ec2 describe-instances --region "$r" \
         --filters Name=instance-state-name,Values=stopped \
         --query 'Reservations[].Instances[].[InstanceId,InstanceType]'
  res  "Dedicated hosts" \
       awsc ec2 describe-hosts --region "$r" --query 'Hosts[?State==`available`].HostId'
  res  "Reserved instances (active)" \
       awsc ec2 describe-reserved-instances --region "$r" \
         --query 'ReservedInstances[?State==`active`].[ReservedInstancesId,InstanceType,InstanceCount]'
  res  "Spot fleet / EC2 fleet requests" \
       awsc ec2 describe-spot-fleet-requests --region "$r" \
         --query 'SpotFleetRequestConfigs[?SpotFleetRequestState==`active`].SpotFleetRequestId'
  res  "Auto Scaling groups" \
       awsc autoscaling describe-auto-scaling-groups --region "$r" \
         --query 'AutoScalingGroups[].[AutoScalingGroupName,DesiredCapacity]'
  res  "Lambda functions" \
       awsc lambda list-functions --region "$r" --query 'Functions[].FunctionName'
  res  "Lightsail instances" \
       awsc lightsail get-instances --region "$r" --query 'instances[].name'
  res  "Elastic Beanstalk environments" \
       awsc elasticbeanstalk describe-environments --region "$r" \
         --query 'Environments[?Status==`Ready`].EnvironmentName'
  res  "EMR clusters (running)" \
       awsc emr list-clusters --region "$r" --active --query 'Clusters[].[Id,Name]'
  res  "Batch compute environments" \
       awsc batch describe-compute-environments --region "$r" --query 'computeEnvironments[].computeEnvironmentName'
  res  "WorkSpaces" \
       awsc workspaces describe-workspaces --region "$r" --query 'Workspaces[].WorkspaceId'
  res  "AppStream fleets" \
       awsc appstream describe-fleets --region "$r" --query 'Fleets[?State==`RUNNING`].Name'

  # -- Containers ---------------------------------------------------------
  sub "Containers  [${r}]"
  resd "EKS clusters (\$73/mo control plane ea)" \
       awsc eks list-clusters --region "$r" --query 'clusters'
  res  "ECS clusters" \
       awsc ecs list-clusters --region "$r" --query 'clusterArns'
  res  "ECR repositories (storage)" \
       awsc ecr describe-repositories --region "$r" --query 'repositories[].repositoryName'
  res  "App Runner services" \
       awsc apprunner list-services --region "$r" --query 'ServiceSummaryList[].ServiceName'

  # -- Storage ------------------------------------------------------------
  sub "Storage  [${r}]"
  res  "EBS volumes (in-use)" \
       awsc ec2 describe-volumes --region "$r" --filters Name=status,Values=in-use \
         --query 'Volumes[].[VolumeId,Size,VolumeType]'
  res  "EBS snapshots (owned)" \
       awsc ec2 describe-snapshots --region "$r" --owner-ids self --query 'Snapshots[].SnapshotId'
  res  "AMIs owned (backed by snapshots)" \
       awsc ec2 describe-images --region "$r" --owners self --query 'Images[].ImageId'
  res  "EFS file systems" \
       awsc efs describe-file-systems --region "$r" --query 'FileSystems[].[FileSystemId,SizeInBytes.Value]'
  res  "FSx file systems" \
       awsc fsx describe-file-systems --region "$r" --query 'FileSystems[].[FileSystemId,FileSystemType]'
  res  "Backup vaults" \
       awsc backup list-backup-vaults --region "$r" --query 'BackupVaultList[].[BackupVaultName,NumberOfRecoveryPoints]'
  res  "Storage Gateways" \
       awsc storagegateway list-gateways --region "$r" --query 'Gateways[].GatewayName'

  # -- Databases ----------------------------------------------------------
  sub "Databases  [${r}]"
  res  "RDS instances" \
       awsc rds describe-db-instances --region "$r" \
         --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,Engine]'
  res  "RDS/Aurora/DocDB/Neptune clusters" \
       awsc rds describe-db-clusters --region "$r" \
         --query 'DBClusters[].[DBClusterIdentifier,Engine,Status]'
  res  "RDS manual snapshots" \
       awsc rds describe-db-snapshots --region "$r" --snapshot-type manual \
         --query 'DBSnapshots[].DBSnapshotIdentifier'
  res  "ElastiCache clusters" \
       awsc elasticache describe-cache-clusters --region "$r" \
         --query 'CacheClusters[].[CacheClusterId,CacheNodeType,Engine]'
  res  "Redshift clusters" \
       awsc redshift describe-clusters --region "$r" \
         --query 'Clusters[].[ClusterIdentifier,NodeType,NumberOfNodes]'
  res  "DynamoDB tables" \
       awsc dynamodb list-tables --region "$r" --query 'TableNames'
  res  "OpenSearch domains" \
       awsc opensearch list-domain-names --region "$r" --query 'DomainNames[].DomainName'
  res  "MemoryDB clusters" \
       awsc memorydb describe-clusters --region "$r" --query 'Clusters[].Name'
  res  "Timestream databases" \
       awsc timestream-write list-databases --region "$r" --query 'Databases[].DatabaseName'
  res  "Keyspaces (Cassandra)" \
       awsc keyspaces list-keyspaces --region "$r" --query 'keyspaces[].keyspaceName'

  # -- Analytics / streaming ----------------------------------------------
  sub "Analytics & streaming  [${r}]"
  res  "Kinesis data streams" \
       awsc kinesis list-streams --region "$r" --query 'StreamNames'
  res  "Kinesis Firehose delivery streams" \
       awsc firehose list-delivery-streams --region "$r" --query 'DeliveryStreamNames'
  res  "MSK (Kafka) clusters" \
       awsc kafka list-clusters --region "$r" --query 'ClusterInfoList[].ClusterName'
  res  "Glue crawlers" \
       awsc glue list-crawlers --region "$r" --query 'CrawlerNames'
  res  "SageMaker endpoints (billed hourly)" \
       awsc sagemaker list-endpoints --region "$r" --query 'Endpoints[].EndpointName'
  res  "SageMaker notebook instances" \
       awsc sagemaker list-notebook-instances --region "$r" \
         --query 'NotebookInstances[?NotebookInstanceStatus==`InService`].NotebookInstanceName'
  res  "MWAA (Airflow) environments" \
       awsc mwaa list-environments --region "$r" --query 'Environments'

  # -- App / integration --------------------------------------------------
  sub "Application & integration  [${r}]"
  res  "API Gateway REST APIs" \
       awsc apigateway get-rest-apis --region "$r" --query 'items[].name'
  res  "API Gateway HTTP/WS APIs" \
       awsc apigatewayv2 get-apis --region "$r" --query 'Items[].Name'
  res  "Step Functions state machines" \
       awsc stepfunctions list-state-machines --region "$r" --query 'stateMachines[].name'
  res  "SQS queues" \
       awsc sqs list-queues --region "$r" --query 'QueueUrls'
  res  "SNS topics" \
       awsc sns list-topics --region "$r" --query 'Topics[].TopicArn'
  res  "EventBridge custom buses" \
       awsc events list-event-buses --region "$r" --query 'EventBuses[?Name!=`default`].Name'
  res  "Amazon MQ brokers" \
       awsc mq list-brokers --region "$r" --query 'BrokerSummaries[].BrokerName'
  res  "Transfer Family servers (~\$216/mo ea)" \
       awsc transfer list-servers --region "$r" --query 'Servers[?State==`ONLINE`].ServerId'
  res  "Connect instances" \
       awsc connect list-instances --region "$r" --query 'InstanceSummaryList[].Id'

  # -- Security / ops -----------------------------------------------------
  sub "Security & operations  [${r}]"
  res  "Secrets Manager secrets (\$0.40/mo ea)" \
       awsc secretsmanager list-secrets --region "$r" --query 'SecretList[].Name'
  res  "KMS customer-managed keys (\$1/mo ea)" \
       awsc kms list-keys --region "$r" --query 'Keys[].KeyId'
  res  "CloudWatch alarms" \
       awsc cloudwatch describe-alarms --region "$r" --query 'MetricAlarms[].AlarmName'
  res  "CloudWatch dashboards (\$3/mo ea)" \
       awsc cloudwatch list-dashboards --region "$r" --query 'DashboardEntries[].DashboardName'
  res  "CloudWatch log groups (ingest+storage)" \
       awsc logs describe-log-groups --region "$r" --query 'logGroups[].logGroupName'
  res  "Log groups with NO retention (grow forever)" \
       awsc logs describe-log-groups --region "$r" \
         --query 'logGroups[?retentionInDays==null].[logGroupName,storedBytes]'
  res  "CloudTrail trails (beyond 1st free)" \
       awsc cloudtrail describe-trails --region "$r" --query 'trailList[].Name'
  res  "Config recorders" \
       awsc configservice describe-configuration-recorders --region "$r" \
         --query 'ConfigurationRecorders[].name'
  res  "GuardDuty detectors" \
       awsc guardduty list-detectors --region "$r" --query 'DetectorIds'
  res  "Inspector2 enabled" \
       awsc inspector2 batch-get-account-status --region "$r" --query 'accounts[?state.status==`ENABLED`].accountId'
  res  "Macie enabled" \
       awsc macie2 get-macie-session --region "$r" --query 'status'
  res  "Security Hub enabled" \
       awsc securityhub describe-hub --region "$r" --query 'HubArn'
  res  "Detective graphs" \
       awsc detective list-graphs --region "$r" --query 'GraphList[].Arn'
  res  "WAF (regional) web ACLs" \
       awsc wafv2 list-web-acls --scope REGIONAL --region "$r" --query 'WebACLs[].Name'
  res  "Directory Service directories" \
       awsc ds describe-directories --region "$r" --query 'DirectoryDescriptions[].[DirectoryId,Type]'

  if [ "$FINDINGS" -eq "$BEFORE" ]; then
    printf '    %sno billable resources found%s\n' "$DIM" "$N"
  fi
done

# ================================================================ WASTE ===

hdr "4. LIKELY WASTE  (safe deletion candidates — verify first)"

for r in $REGIONS; do
  W=$FINDINGS
  printf '\n%s--- %s ---%s\n' "$B" "$r" "$N"
  resd "Unattached EBS volumes" \
       awsc ec2 describe-volumes --region "$r" --filters Name=status,Values=available \
         --query 'Volumes[].[VolumeId,Size,VolumeType,CreateTime]'
  resd "Unassociated Elastic IPs (\$3.60/mo ea)" \
       awsc ec2 describe-addresses --region "$r" \
         --query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]'
  resd "Idle NAT Gateways in empty subnets? (review)" \
       awsc ec2 describe-nat-gateways --region "$r" --filter Name=state,Values=available \
         --query 'NatGateways[].[NatGatewayId,SubnetId]'
  resd "Load balancers with no targets" \
       awsc elbv2 describe-target-groups --region "$r" \
         --query 'TargetGroups[?length(LoadBalancerArns)==`0`].TargetGroupName'
  res  "Stopped EC2 (paying for EBS only)" \
       awsc ec2 describe-instances --region "$r" \
         --filters Name=instance-state-name,Values=stopped \
         --query 'Reservations[].Instances[].[InstanceId,InstanceType]'
  res  "Old gp2 volumes (gp3 is ~20% cheaper)" \
       awsc ec2 describe-volumes --region "$r" --filters Name=volume-type,Values=gp2 \
         --query 'Volumes[].[VolumeId,Size]'
  [ "$FINDINGS" -eq "$W" ] && printf '    %snothing obvious%s\n' "$DIM" "$N"
done

hdr "DONE"
printf 'Total billable/notable items found: %s%s%s\n' "$B" "$FINDINGS" "$N"
cat <<'EOF'

Notes
  * Prices in labels are rough us-east-1 on-demand figures for orientation only.
    Section 1 is the authoritative number — it comes from your real bill.
  * Every public IPv4 address has been chargeable since Feb 2024, attached or not.
  * Gateway endpoints (S3/DynamoDB) are free; Interface endpoints bill per-AZ-hour.
  * Cross-AZ and cross-region data transfer will not show up as a "resource" —
    check the usage-type breakdown in section 1 for DataTransfer- lines.
  * Cost Explorer API calls cost $0.01 each; this script makes 4.

Minimum IAM policy: attach ReadOnlyAccess, or a policy allowing
  ce:GetCostAndUsage, ce:GetCostForecast, plus Describe*/List*/Get* on the
  services above.
EOF
