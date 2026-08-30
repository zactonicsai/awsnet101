#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

preflight
require_value VPC_ID

if [[ -z "${NLB_SG_ID:-}" ]]; then
  NLB_SG_ID="$(awsr ec2 create-security-group \
    --group-name "${PROJECT_NAME}-nlb-sg" \
    --description "Internet to Network Load Balancer" \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-nlb-sg},{Key=Project,Value=${PROJECT_NAME}}]" \
    --query 'GroupId' \
    --output text)"
  save_state NLB_SG_ID "${NLB_SG_ID}"

  awsr ec2 authorize-security-group-ingress \
    --group-id "${NLB_SG_ID}" \
    --ip-permissions "IpProtocol=tcp,FromPort=${LB_PORT},ToPort=${LB_PORT},IpRanges=[{CidrIp=0.0.0.0/0,Description='Public HTTP to NLB'}]" >/dev/null
fi

if [[ -z "${EC2_SG_ID:-}" ]]; then
  EC2_SG_ID="$(awsr ec2 create-security-group \
    --group-name "${PROJECT_NAME}-ec2-sg" \
    --description "Only NLB can reach private EC2 app port" \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-ec2-sg},{Key=Project,Value=${PROJECT_NAME}}]" \
    --query 'GroupId' \
    --output text)"
  save_state EC2_SG_ID "${EC2_SG_ID}"

  # Security-group-to-security-group rule:
  # only traffic arriving through this NLB security group reaches the EC2 app.
  awsr ec2 authorize-security-group-ingress \
    --group-id "${EC2_SG_ID}" \
    --ip-permissions "IpProtocol=tcp,FromPort=${APP_PORT},ToPort=${APP_PORT},UserIdGroupPairs=[{GroupId=${NLB_SG_ID},Description='NLB to private EC2'}]" >/dev/null
fi

echo "NLB security group: ${NLB_SG_ID}"
echo "EC2 security group: ${EC2_SG_ID}"
