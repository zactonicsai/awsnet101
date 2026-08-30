#!/usr/bin/env bash
# =============================================================================
# 00-config.sh  -  SETTINGS AND HELPERS
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# This file does not build anything. It holds the settings that every other
# script needs, plus a few helper functions. Every other script starts by
# loading this one, so you change a setting HERE and it applies everywhere.
#
# It also creates a "state file" (.state.env). AWS gives every resource a random
# ID when it's created, and the next script needs those IDs. Since each script
# is a separate program, we write the IDs to a file so they survive.
# Terraform does this bookkeeping for you automatically - doing it by hand here
# shows you exactly how much work Terraform is quietly saving you.
# =============================================================================

# --- Defensive shell settings ------------------------------------------------
set -euo pipefail
#   -e            exit the moment any command fails, instead of blundering on
#   -u            error if we use an undefined variable (catches typos)
#   -o pipefail   a failure anywhere in a pipeline fails the whole pipeline

# =============================================================================
# SETTINGS - edit these
# =============================================================================
export AWS_REGION="${AWS_REGION:-us-east-1}"   # cheapest region for most people
export PROJECT="${PROJECT:-web-demo}"          # name prefix stamped on everything

export VPC_CIDR="10.0.0.0/16"                  # the whole neighborhood (~65k IPs)
export PUBLIC_CIDR_1="10.0.0.0/24"             # public street in AZ #1
export PUBLIC_CIDR_2="10.0.1.0/24"             # public street in AZ #2
export PRIVATE_CIDR_1="10.0.10.0/24"           # private street in AZ #1
export PRIVATE_CIDR_2="10.0.11.0/24"           # private street in AZ #2

export INSTANCE_TYPE="${INSTANCE_TYPE:-t4g.nano}"  # ~$3.07/mo. Use t3.micro for Free Tier.
export APP_PORT="8080"                             # port our Python server listens on
export RESPONSE_TEXT="It works!"                   # the text the website returns

# Who may reach the load balancer. 0.0.0.0/0 = the whole internet.
# To keep your test private: ALLOWED_CIDR="$(curl -s https://checkip.amazonaws.com)/32"
export ALLOWED_CIDR="${ALLOWED_CIDR:-0.0.0.0/0}"

# --- Optional DNS ------------------------------------------------------------
# Leave ENABLE_DNS=false unless you already own a domain with a Route 53
# PUBLIC hosted zone. Everything still works without it.
export ENABLE_DNS="${ENABLE_DNS:-false}"
export HOSTED_ZONE_NAME="${HOSTED_ZONE_NAME:-example.com}"  # your real domain
export SUBDOMAIN="${SUBDOMAIN:-app}"                        # produces app.example.com

# =============================================================================
# STATE FILE - our hand-rolled substitute for Terraform state
# =============================================================================
# BASH_SOURCE[0] is the path of THIS file, so the state file always lands next
# to the scripts no matter which directory you run them from.
export STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state.env"

# save_state KEY VALUE
#   Appends "export KEY=VALUE" to the state file, replacing any older line for
#   the same key so re-running a script doesn't create duplicates.
save_state() {
  local key="$1" value="$2"
  touch "$STATE_FILE"
  # Remove any existing line for this key. The '|| true' stops set -e from
  # aborting when grep finds nothing (grep exits 1 on "no matches").
  grep -v "^export ${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  echo "export ${key}=\"${value}\"" >> "$STATE_FILE"
  echo "  saved ${key} = ${value}"
}

# load_state
#   Reads every saved ID back into the current shell.
load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # 'source' runs the file in the current shell so the exports take effect.
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

# --- Pretty output helpers ---------------------------------------------------
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }   # cyan heading
ok()   { printf '\033[1;32m  OK  %s\033[0m\n' "$*"; }   # green success
warn() { printf '\033[1;33m  !!  %s\033[0m\n' "$*"; }   # yellow warning
die()  { printf '\033[1;31m  XX  %s\033[0m\n' "$*" >&2; exit 1; }  # red, then stop

# --- Preflight check ---------------------------------------------------------
# Fail fast with a clear message instead of a confusing AWS error later.
preflight() {
  command -v aws >/dev/null 2>&1 || die "AWS CLI not found. Install it first - see the README."

  # 'aws sts get-caller-identity' is the standard "am I logged in?" test.
  # It asks AWS "who am I?" and costs nothing.
  aws sts get-caller-identity --output text >/dev/null 2>&1 \
    || die "Not authenticated. Run 'aws configure' first - see the README Step 1."

  # Confirm the CLI is version 2. Version 1 is end-of-life.
  local v
  v="$(aws --version 2>&1 | head -1)"
  case "$v" in
    aws-cli/2.*) : ;;  # good
    *) warn "You appear to be on AWS CLI v1 ($v). v2 is strongly recommended." ;;
  esac
}

# Always load whatever state already exists when this file is sourced.
load_state
