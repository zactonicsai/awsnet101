#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

preflight
require_value PRIVATE_SUBNET_ID
require_value EC2_SG_ID

if [[ -n "${INSTANCE_ID:-}" ]] && awsr ec2 describe-instances --instance-ids "${INSTANCE_ID}" >/dev/null 2>&1; then
  STATE="$(awsr ec2 describe-instances --instance-ids "${INSTANCE_ID}" --query 'Reservations[0].Instances[0].State.Name' --output text)"
  if [[ "${STATE}" != "terminated" ]]; then
    echo "EC2 already exists: ${INSTANCE_ID} (${STATE})"
    exit 0
  fi
fi

echo "Looking up the latest Amazon Linux 2023 ARM64 AMI..."
AMI_ID="$(awsr ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  --query 'Parameter.Value' \
  --output text)"
save_state AMI_ID "${AMI_ID}"

USER_DATA_FILE="${ROOT_DIR}/.user-data.sh"
cat > "${USER_DATA_FILE}" <<EOF
#!/bin/bash
set -eux

mkdir -p /opt/cheapweb

cat > /opt/cheapweb/index.html <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>AWS Private EC2 Demo</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 760px; margin: 60px auto; padding: 20px; }
    h1 { color: #123b63; }
    code { background: #f1f1f1; padding: 2px 5px; }
  </style>
</head>
<body>
  <h1>Hello from private EC2</h1>
  <p>This EC2 instance has no public IPv4 address.</p>
  <p>Traffic path: Route 53 → Network Load Balancer → Target Group → private EC2.</p>
</body>
</html>
HTML

cat > /etc/systemd/system/cheapweb.service <<'UNIT'
[Unit]
Description=Simple Python demo web server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/cheapweb
ExecStart=/usr/bin/python3 -m http.server ${APP_PORT} --bind 0.0.0.0 --directory /opt/cheapweb
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now cheapweb.service
EOF

echo "Launching ${INSTANCE_TYPE} into PRIVATE subnet ${PRIVATE_SUBNET_ID}..."
INSTANCE_ID="$(awsr ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --subnet-id "${PRIVATE_SUBNET_ID}" \
  --security-group-ids "${EC2_SG_ID}" \
  --associate-public-ip-address false \
  --user-data "file://${USER_DATA_FILE}" \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,DeleteOnTermination=true}' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-web},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'Instances[0].InstanceId' \
  --output text)"

rm -f "${USER_DATA_FILE}"
save_state INSTANCE_ID "${INSTANCE_ID}"

awsr ec2 wait instance-running --instance-ids "${INSTANCE_ID}"

PRIVATE_IP="$(awsr ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)"
save_state PRIVATE_IP "${PRIVATE_IP}"

echo "EC2 instance : ${INSTANCE_ID}"
echo "Private IP   : ${PRIVATE_IP}"
echo "Public IP    : NONE"
