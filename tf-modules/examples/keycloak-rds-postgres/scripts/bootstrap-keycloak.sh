#!/bin/bash
# =============================================================================
# bootstrap-keycloak.sh
# -----------------------------------------------------------------------------
# Runs ONCE, as root, on first boot. Rendered by templatefile() first, so every
# ${...} below is already a real value by the time this executes.
#
# WHAT IT DOES, IN ORDER:
#   1. Install Docker and firewalld from the AL2023 repositories
#   2. Configure firewalld to open only the ports Keycloak needs
#   3. Fetch database and admin credentials from Secrets Manager
#   4. Run the official Keycloak container, pointed at RDS PostgreSQL
#   5. Register it with systemd so it survives crashes and reboots
#
# NOTE: this script REQUIRES outbound internet access, because it downloads
# Docker packages and pulls the Keycloak image from quay.io. That is why the
# example enables a NAT Gateway (~$32/month). See the README for how to avoid
# that cost by mirroring the image into ECR.
# =============================================================================

set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1
echo "=== Keycloak bootstrap starting $(date) ==="

# Terraform-injected values, captured as shell variables so the rest of the
# script reads normally.
AWS_REGION="${aws_region}"
DB_SECRET_ARN="${db_secret_arn}"
ADMIN_SECRET_ARN="${admin_secret_arn}"
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_NAME="${db_name}"
KEYCLOAK_IMAGE="${keycloak_image}"
HTTP_PORT="${http_port}"
MGMT_PORT="${management_port}"
HOSTNAME_URL="${hostname_url}"

# -----------------------------------------------------------------------------
# STEP 1: Install packages
# -----------------------------------------------------------------------------
echo "--- installing docker, firewalld, jq ---"
dnf install -y docker firewalld jq

# jq parses the JSON that Secrets Manager returns. Without it we would be
# parsing JSON with grep, which breaks the moment a password contains a brace.

systemctl enable --now docker

# -----------------------------------------------------------------------------
# STEP 2: firewalld
# -----------------------------------------------------------------------------
# WHY BOTHER, when security groups already filter traffic?
# Defence in depth. Security groups are enforced in the AWS network, firewalld
# on the host itself. If a security group is ever widened by mistake -- a
# careless console edit, an overly broad Terraform change -- the host firewall
# is still standing. They fail independently, which is the whole point.
#
# ORDERING NOTE: Docker writes its own iptables rules for published ports and
# can bypass firewalld's filter chain. We therefore publish container ports
# bound to the host and rely on the security group as the authoritative control,
# treating firewalld as the second layer rather than the only one.
echo "--- configuring firewalld ---"
systemctl enable --now firewalld

# Wait for the daemon to accept commands; firewall-cmd fails if it races ahead.
for i in $(seq 1 15); do
  firewall-cmd --state >/dev/null 2>&1 && break
  echo "  waiting for firewalld ($i/15)"
  sleep 2
done

# --permanent writes to disk; without it every rule vanishes on reload.
# We add permanent rules, then --reload to activate them all at once.
firewall-cmd --permanent --zone=public --add-port=$${HTTP_PORT}/tcp
firewall-cmd --permanent --zone=public --add-port=$${MGMT_PORT}/tcp

# Keycloak clustering (Infinispan/JGroups) uses 7800 between nodes. Harmless
# with a single instance, required the moment you run more than one.
firewall-cmd --permanent --zone=public --add-port=7800/tcp

# Deliberately NOT opened: 22 (SSH). There is no key pair and no bastion --
# shell access is via SSM Session Manager, which needs no inbound port at all.

firewall-cmd --reload
echo "--- firewalld active rules ---"
firewall-cmd --list-all

# -----------------------------------------------------------------------------
# STEP 3: Fetch credentials
# -----------------------------------------------------------------------------
# The instance authenticates with its IAM role, so no credentials are stored
# anywhere on disk, in the launch template, or in this script. Only the secret
# ARNs are passed in, and an ARN is not sensitive.
echo "--- fetching credentials from Secrets Manager ---"

get_secret() {
  aws secretsmanager get-secret-value \
    --secret-id "$1" \
    --region "$${AWS_REGION}" \
    --query SecretString \
    --output text
}

# RDS-managed secrets are JSON: {"username":"...","password":"..."}
DB_SECRET_JSON="$(get_secret "$${DB_SECRET_ARN}")"
DB_USER="$(echo "$${DB_SECRET_JSON}" | jq -r .username)"
DB_PASS="$(echo "$${DB_SECRET_JSON}" | jq -r .password)"

ADMIN_SECRET_JSON="$(get_secret "$${ADMIN_SECRET_ARN}")"
KC_ADMIN_USER="$(echo "$${ADMIN_SECRET_JSON}" | jq -r .username)"
KC_ADMIN_PASS="$(echo "$${ADMIN_SECRET_JSON}" | jq -r .password)"

echo "  retrieved DB user: $${DB_USER}"
echo "  retrieved admin user: $${KC_ADMIN_USER}"

# -----------------------------------------------------------------------------
# STEP 4: Write the environment file
# -----------------------------------------------------------------------------
# Secrets go in a root-only file rather than on the docker command line,
# because anything on the command line is visible to every user via `ps`.
install -d -m 0700 /etc/keycloak
umask 077

cat > /etc/keycloak/keycloak.env <<ENVEOF
KC_DB=postgres
KC_DB_URL_HOST=$${DB_HOST}
KC_DB_URL_PORT=$${DB_PORT}
KC_DB_URL_DATABASE=$${DB_NAME}
KC_DB_USERNAME=$${DB_USER}
KC_DB_PASSWORD=$${DB_PASS}

# Bootstrap admin. Keycloak 26 renamed these from KEYCLOAK_ADMIN /
# KEYCLOAK_ADMIN_PASSWORD; the new names only create the account on FIRST
# startup against an empty database, and are ignored afterwards.
KC_BOOTSTRAP_ADMIN_USERNAME=$${KC_ADMIN_USER}
KC_BOOTSTRAP_ADMIN_PASSWORD=$${KC_ADMIN_PASS}

# --- Running behind a load balancer ---------------------------------------
# The ALB terminates TLS and forwards plain HTTP inside the VPC, so Keycloak
# must be told to accept HTTP and to trust the X-Forwarded-* headers. Without
# KC_PROXY_HEADERS, Keycloak builds redirect URLs using its own internal
# address and every login bounces to a private IP the browser cannot reach.
KC_HTTP_ENABLED=true
KC_PROXY_HEADERS=xforwarded
KC_HOSTNAME=$${HOSTNAME_URL}
KC_HTTP_PORT=$${HTTP_PORT}

# Health and metrics endpoints live on the MANAGEMENT port (9000 by default),
# not the main HTTP port. This catches people out constantly: the target group
# health check must point at the management port, or it 404s forever.
KC_HEALTH_ENABLED=true
KC_METRICS_ENABLED=true
KC_HTTP_MANAGEMENT_PORT=$${MGMT_PORT}
ENVEOF

chmod 0600 /etc/keycloak/keycloak.env

# -----------------------------------------------------------------------------
# STEP 5: Pull the image
# -----------------------------------------------------------------------------
echo "--- pulling $${KEYCLOAK_IMAGE} ---"
# Retry: NAT gateways and registries occasionally hiccup, and a failed pull
# here would leave the instance permanently broken until it is replaced.
for attempt in 1 2 3 4 5; do
  if docker pull "$${KEYCLOAK_IMAGE}"; then
    echo "  pull succeeded on attempt $${attempt}"
    break
  fi
  echo "  pull failed, retrying in 15s ($${attempt}/5)"
  sleep 15
done

# -----------------------------------------------------------------------------
# STEP 6: systemd unit
# -----------------------------------------------------------------------------
# Running `docker run -d` from user data would work exactly once. systemd gives
# us restart-on-crash and restart-on-reboot, which is the difference between a
# demo and something that stays up.
cat > /etc/systemd/system/keycloak.service <<'SVCEOF'
[Unit]
Description=Keycloak (Docker)
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
TimeoutStartSec=600

# Remove any container left from a previous run. "-" prefixes mean "ignore
# failure", which matters on the very first boot when there is nothing to stop.
ExecStartPre=-/usr/bin/docker stop keycloak
ExecStartPre=-/usr/bin/docker rm keycloak

# --rm and foreground mode let systemd supervise the process directly.
ExecStart=/usr/bin/docker run --rm --name keycloak \
  --env-file /etc/keycloak/keycloak.env \
  -p KEYCLOAK_HTTP_PORT:KEYCLOAK_HTTP_PORT \
  -p KEYCLOAK_MGMT_PORT:KEYCLOAK_MGMT_PORT \
  KEYCLOAK_IMAGE_PLACEHOLDER \
  start --optimized=false

ExecStop=/usr/bin/docker stop keycloak

[Install]
WantedBy=multi-user.target
SVCEOF

# Substitute the real values into the unit file. We use a quoted heredoc above
# so the shell does not mangle systemd's own syntax, then patch afterwards.
sed -i \
  -e "s|KEYCLOAK_HTTP_PORT|$${HTTP_PORT}|g" \
  -e "s|KEYCLOAK_MGMT_PORT|$${MGMT_PORT}|g" \
  -e "s|KEYCLOAK_IMAGE_PLACEHOLDER|$${KEYCLOAK_IMAGE}|g" \
  /etc/systemd/system/keycloak.service

systemctl daemon-reload
systemctl enable --now keycloak

# -----------------------------------------------------------------------------
# STEP 7: Wait for readiness
# -----------------------------------------------------------------------------
# Keycloak runs database migrations on first start against an empty schema,
# which can take a couple of minutes. The ASG health check grace period must be
# longer than this, or instances get killed mid-migration and replaced forever.
echo "--- waiting for Keycloak to report ready ---"
for i in $(seq 1 60); do
  if curl -fsS "http://localhost:$${MGMT_PORT}/health/ready" >/dev/null 2>&1; then
    echo "SUCCESS: Keycloak is ready after $${i} attempts"
    break
  fi
  echo "  not ready yet ($${i}/60)"
  sleep 10
done

echo "--- final status ---"
systemctl is-active keycloak && echo "keycloak service: active"
docker ps --filter name=keycloak --format '{{.Names}} {{.Status}}' || true
echo "=== Keycloak bootstrap finished $(date) ==="
