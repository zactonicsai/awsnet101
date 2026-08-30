#!/usr/bin/env bash
# ============================================================
# User settings
# Edit this file BEFORE running ./create-all.sh
# ============================================================

# AWS Region. us-east-1 is a common low-cost example region.
AWS_REGION="${AWS_REGION:-us-east-1}"

# Short name used in AWS Name tags.
PROJECT_NAME="${PROJECT_NAME:-cheap-web}"

# Network ranges.
VPC_CIDR="${VPC_CIDR:-10.30.0.0/16}"
PUBLIC_SUBNET_CIDR="${PUBLIC_SUBNET_CIDR:-10.30.1.0/24}"
PRIVATE_SUBNET_CIDR="${PRIVATE_SUBNET_CIDR:-10.30.10.0/24}"

# Lowest-cost example: one Availability Zone.
# Leave blank and the scripts choose the first available AZ in your region.
AZ="${AZ:-}"

# Application ports.
LB_PORT="${LB_PORT:-80}"
APP_PORT="${APP_PORT:-8080}"

# ARM/Graviton is normally a very inexpensive EC2 option.
INSTANCE_TYPE="${INSTANCE_TYPE:-t4g.nano}"

# IMPORTANT:
# Change this to a domain you own, for example: example.com
DOMAIN_NAME="${DOMAIN_NAME:-CHANGE-ME.example.com}"

# Public URL becomes: http://app.example.com
RECORD_NAME="${RECORD_NAME:-app.${DOMAIN_NAME}}"
