#!/bin/bash
# =============================================================================
# user_data.sh
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# "User data" is a script AWS runs ONE TIME, automatically, the very first time
# a server boots. Nobody has to log in. It is how you turn a blank virtual
# machine into a working web server without ever touching it.
#
# CRITICAL DESIGN CHOICE:
# This script installs NOTHING from the internet. Not one download.
# Why? Because our servers sit in a private subnet with no internet route, and
# giving them one would require a NAT Gateway at roughly $32/month. Instead we
# use Python 3, which is already baked into the Amazon Linux 2023 image for free.
#
# The ${app_port} and ${response_text} markers are placeholders. Terraform's
# templatefile() function swaps in the real values before this ever reaches AWS.
# =============================================================================

# 'set -euo pipefail' is defensive scripting:
#   -e            stop immediately if any command fails
#   -u            stop if we use a variable that was never set (catches typos)
#   -o pipefail   a failure anywhere in a pipeline fails the whole pipeline
set -euo pipefail

# Send everything this script prints to a log file AND to the console, so you
# can debug later by reading /var/log/user-data.log
exec > >(tee /var/log/user-data.log) 2>&1
echo "=== Bootstrap starting at $(date) ==="

# -----------------------------------------------------------------------------
# STEP 1: Write the tiny web application to disk.
# -----------------------------------------------------------------------------
mkdir -p /opt/webapp

# The "cat > file << MARKER ... MARKER" pattern writes everything between the
# markers into a file. Because Terraform has already substituted our values,
# what lands on disk is plain, finished Python.
cat > /opt/webapp/server.py <<'PYEOF'
"""
A deliberately tiny HTTP server using only Python's standard library.
No pip install. No internet connection. About 25 lines of real logic.
"""
import socket
import socketserver
from http.server import BaseHTTPRequestHandler

PORT = ${app_port}
MESSAGE = "${response_text}"


def local_ip():
    """
    Find this machine's own private IP address WITHOUT using DNS.

    Why the trouble? Our security group allows no outbound traffic at all, so a
    normal name lookup would hang. This trick opens a UDP socket and 'connects'
    it - but UDP connect sends zero packets. It only asks the operating system
    'which of my network cards would you use to reach that address?' and then we
    read the answer. Completely offline, instant, and never fails the app.
    """
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
    # Use HTTP/1.1 so the load balancer can reuse connections (keep-alive),
    # which is faster and reduces load. Content-Length below makes this legal.
    protocol_version = "HTTP/1.1"

    # do_GET runs every time a browser - or the load balancer's health checker -
    # asks for a page with an HTTP GET request.
    def do_GET(self):
        # We include the hostname and IP so that when you refresh the page you
        # can SEE the load balancer alternating between servers. That turns load
        # balancing from magic into something observable.
        body = (
            MESSAGE + "\n"
            "Served by: " + socket.gethostname() + "\n"
            "Private IP: " + local_ip() + "\n"
            "Path requested: " + self.path + "\n"
        ).encode("utf-8")

        # send_response(200) writes the status line "HTTP/1.1 200 OK".
        # 200 is the code meaning "here you go, everything worked."
        # The load balancer's health check is literally just looking for this.
        self.send_response(200)

        # Headers describe the body BEFORE the body is sent.
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()  # blank line meaning "headers finished"

        # Finally, the actual content.
        self.wfile.write(body)

    # Silence default access logging so health checks (every 30 seconds,
    # forever) don't slowly fill up the tiny disk.
    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingTCPServer):
    # Handle several requests at once. Without threading, one slow client could
    # block the health check and the ALB would wrongly decide we are dead.
    daemon_threads = True
    # Let the server restart instantly instead of waiting ~60 seconds for the
    # operating system to release the old socket.
    allow_reuse_address = True


if __name__ == "__main__":
    # "0.0.0.0" means listen on every network interface, not just localhost.
    # If you wrote "127.0.0.1" here, the load balancer could never connect and
    # every single health check would fail. This is a very common beginner bug.
    with Server(("0.0.0.0", PORT), Handler) as httpd:
        httpd.serve_forever()
PYEOF

# -----------------------------------------------------------------------------
# STEP 2: Turn the script into a managed service.
# -----------------------------------------------------------------------------
# systemd is Linux's service manager. Registering with systemd means the app
# restarts automatically if it crashes, and starts again after a reboot.
# Simply running "python3 server.py &" would die and never come back.
cat > /etc/systemd/system/webapp.service <<'SVCEOF'
[Unit]
Description=Tiny demo web server for the AWS routing tutorial
# Wait until the network is genuinely up before trying to bind to a port.
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/webapp/server.py
# Restart=always: if this ever exits for any reason, start it again.
Restart=always
RestartSec=3
# Run as an unprivileged user. If someone found a bug in our web server they
# would land as "nobody" rather than as root. Least privilege, free to apply.
User=nobody
Group=nobody
# Extra hardening - the process only gets a read-only view of the system.
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SVCEOF

# -----------------------------------------------------------------------------
# STEP 3: Start it, and make it permanent.
# -----------------------------------------------------------------------------
systemctl daemon-reload        # re-read the service file we just wrote
systemctl enable --now webapp  # 'enable' = start on every boot; '--now' = start right now too

# Prove it worked, and leave the evidence in the log.
sleep 2
systemctl is-active webapp && echo "SUCCESS: webapp is listening on port ${app_port}"
echo "=== Bootstrap finished at $(date) ==="
