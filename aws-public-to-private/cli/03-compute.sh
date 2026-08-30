#!/usr/bin/env bash
# =============================================================================
# 03-compute.sh  -  LAUNCH THE SERVERS
# -----------------------------------------------------------------------------
# Launches one EC2 instance per private subnet, each running a tiny Python web
# server that returns plain text with HTTP status 200.
# COST: ~$3.07/month per t4g.nano, plus ~$0.64/month for the 8 GB disk.
#       (Free if you use t3.micro and are inside the 12-month Free Tier.)
# RUN:   bash 03-compute.sh
# =============================================================================

source "$(dirname "$0")/00-config.sh"
preflight

[[ -n "${PRIVATE_SUBNET_1:-}" ]] || die "Subnets not found. Run 01-network.sh first."
[[ -n "${APP_SG:-}" ]]           || die "Security groups not found. Run 02-security.sh first."

say "STEP 10: Finding the newest Amazon Linux 2023 image"

# AMI IDs differ per region AND change with every security patch, so never
# hard-code one. AWS publishes a public pointer in SSM Parameter Store that
# always names the current image. Reading it is free.
#
# t4g.* instances use ARM (Graviton) chips; t3/t2 use x86_64. Pick the matching
# image or the instance will refuse to boot.
if [[ "$INSTANCE_TYPE" == t4g.* ]]; then
  AMI_PARAM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
else
  AMI_PARAM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
fi

AMI_ID=$(aws ssm get-parameter \
  --name "$AMI_PARAM" \
  --query 'Parameter.Value' \
  --output text \
  --region "$AWS_REGION")
save_state AMI_ID "$AMI_ID"
ok "Using AMI: $AMI_ID"

say "STEP 11: Building the bootstrap script"

# "User data" is a script AWS runs once, automatically, on first boot.
# We reuse the exact same script the Terraform version uses. The two ${...}
# placeholders are filled in here with sed instead of Terraform's templatefile().
USER_DATA_SRC="$(dirname "$0")/../terraform/user_data.sh"
[[ -f "$USER_DATA_SRC" ]] || die "Cannot find $USER_DATA_SRC"

USER_DATA_FILE="$(mktemp)"
sed -e "s|\${app_port}|${APP_PORT}|g" \
    -e "s|\${response_text}|${RESPONSE_TEXT}|g" \
    "$USER_DATA_SRC" > "$USER_DATA_FILE"
ok "Bootstrap script prepared at $USER_DATA_FILE"

say "STEP 12: Launching the servers into the PRIVATE subnets"

# launch_one SUBNET_ID NUMBER
launch_one() {
  local subnet="$1" num="$2"
  aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --subnet-id "$subnet" \
    --security-group-ids "$APP_SG" \
    --no-associate-public-ip-address \
    --user-data "file://${USER_DATA_FILE}" \
    --metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=1" \
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-app-${num}},{Key=Project,Value=${PROJECT}}]" \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION"
}
# Flags explained:
#   --no-associate-public-ip-address  belt and braces: no public IP, ever
#   --user-data file://...            the "file://" prefix is required; the CLI
#                                     reads and base64-encodes the file for you
#   HttpTokens=required               forces IMDSv2, blocking SSRF credential theft
#   Encrypted=true                    disk encryption at rest - free, always do it
#   DeleteOnTermination=true          stops orphaned disks quietly costing money

INSTANCE_1=$(launch_one "$PRIVATE_SUBNET_1" 1)
save_state INSTANCE_1 "$INSTANCE_1"
ok "Launched $INSTANCE_1 in $PRIVATE_SUBNET_1"

# Launch a second server in the OTHER Availability Zone for real redundancy.
# Comment these three lines out to save ~$3.70/month while learning.
INSTANCE_2=$(launch_one "$PRIVATE_SUBNET_2" 2)
save_state INSTANCE_2 "$INSTANCE_2"
ok "Launched $INSTANCE_2 in $PRIVATE_SUBNET_2"

# Clean up the temporary file - it is no longer needed.
rm -f "$USER_DATA_FILE"

say "STEP 13: Waiting for the servers to finish booting"
warn "This normally takes 30-60 seconds. The 'wait' command polls for you."

# 'aws ec2 wait' is a built-in poller. It blocks until the condition is true or
# it gives up. Far better than guessing with 'sleep 90'.
aws ec2 wait instance-running --instance-ids "$INSTANCE_1" "$INSTANCE_2" --region "$AWS_REGION"
ok "Both instances report state = running"

# 'running' only means the virtual machine powered on. Our Python service may
# still be starting. The load balancer's health check handles that for us in
# the next script, which is exactly what health checks are for.

say "COMPUTE COMPLETE. Next: bash 04-loadbalancer.sh"
