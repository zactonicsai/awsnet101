#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${ROOT_DIR}/.state.env"

# shellcheck source=/dev/null
source "${ROOT_DIR}/config.sh"

if [[ -f "${STATE_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${STATE_FILE}"
fi

awsr() {
  aws --region "${AWS_REGION}" --no-cli-pager "$@"
}

save_state() {
  local key="$1"
  local value="$2"
  touch "${STATE_FILE}"

  # Remove the old value if it already exists.
  local tmp="${STATE_FILE}.tmp"
  grep -v "^${key}=" "${STATE_FILE}" > "${tmp}" || true
  mv "${tmp}" "${STATE_FILE}"

  # %q makes the value safe to source again in Bash.
  printf '%s=%q\n' "${key}" "${value}" >> "${STATE_FILE}"

  # Make the new value available to the current script immediately.
  printf -v "${key}" '%s' "${value}"
  export "${key}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Required command '$1' was not found."
    exit 1
  }
}

require_value() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "${value}" ]]; then
    echo "ERROR: ${name} is empty. A previous create step may not have run."
    exit 1
  fi
}

validate_domain() {
  if [[ "${DOMAIN_NAME}" == CHANGE-ME.* || "${DOMAIN_NAME}" == "CHANGE-ME.example.com" ]]; then
    echo "ERROR: Edit config.sh and set DOMAIN_NAME to a domain you own."
    echo "Example:"
    echo '  DOMAIN_NAME="${DOMAIN_NAME:-example.com}"'
    exit 1
  fi
}

preflight() {
  require_command aws

  echo "Checking AWS credentials..."
  awsr sts get-caller-identity >/dev/null

  echo "AWS Region : ${AWS_REGION}"
  echo "Project    : ${PROJECT_NAME}"
}

tag_name() {
  local resource_id="$1"
  local name="$2"
  awsr ec2 create-tags \
    --resources "${resource_id}" \
    --tags "Key=Name,Value=${name}" "Key=Project,Value=${PROJECT_NAME}"
}
