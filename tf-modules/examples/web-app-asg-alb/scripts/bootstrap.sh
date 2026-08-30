#!/bin/bash
# =============================================================================
# bootstrap.sh -- rendered by templatefile() before it ever reaches AWS
# -----------------------------------------------------------------------------
# ${app_port} and ${response_text} are Terraform placeholders. By the time this
# script runs on the instance they are already real values.
#
# This script downloads NOTHING. Python 3 ships inside Amazon Linux 2023, so
# the instances need no internet access -- which is exactly what lets us leave
# enable_nat_gateway = false and save ~$32/month.
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1
echo "=== bootstrap starting $(date) ==="

mkdir -p /opt/webapp

cat > /opt/webapp/server.py <<'PYEOF'
import socket
import socketserver
from http.server import BaseHTTPRequestHandler

PORT = ${app_port}
MESSAGE = "${response_text}"


def local_ip():
    """Find our own IP without DNS -- a UDP 'connect' sends no packets, it just
    asks the kernel which interface would be used to reach that address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        finally:
            s.close()
    except Exception:
        return "unknown"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        body = (
            MESSAGE + "\n"
            "Served by: " + socket.gethostname() + "\n"
            "Private IP: " + local_ip() + "\n"
            "Path: " + self.path + "\n"
        ).encode("utf-8")
        # 200 is what the target group health check demands. Anything else and
        # the ASG replaces this instance, forever, in a loop.
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    # 0.0.0.0, never 127.0.0.1. Binding to localhost works perfectly when you
    # test on the box and is completely invisible to the load balancer.
    with Server(("0.0.0.0", PORT), Handler) as httpd:
        httpd.serve_forever()
PYEOF

cat > /etc/systemd/system/webapp.service <<'SVCEOF'
[Unit]
Description=Demo web server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/webapp/server.py
Restart=always
RestartSec=3
User=nobody
Group=nobody
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now webapp
sleep 2
systemctl is-active webapp && echo "SUCCESS: listening on ${app_port}"
echo "=== bootstrap finished $(date) ==="
