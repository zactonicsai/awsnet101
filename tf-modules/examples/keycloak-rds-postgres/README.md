# Example: Keycloak on EC2 (Docker) with RDS PostgreSQL

A production-shaped identity provider deployment, built entirely from this library's modules.

```
internet -> ALB (public subnets, NACL-protected)
         -> ASG running the Keycloak container (private subnets, firewalld)
         -> RDS PostgreSQL (private subnets, no internet route)
```

Demonstrates Docker via user data, **firewalld** on the host, Secrets Manager for credentials, **Network ACLs with explicit ingress and egress**, and honest handling of the NAT Gateway cost.

---

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply        # ~10 minutes: RDS alone takes 5-8
```

Then:

```bash
terraform output keycloak_url
eval "$(terraform output -raw get_admin_password_command)"   # the admin password
```

Log in at `<url>/admin` with username `admin`.

> **First boot takes 5–10 minutes** after the instance launches. It installs Docker, pulls a ~450 MB image, starts a JVM, and runs database migrations. The ASG grace period is set to 900 seconds for exactly this reason.

---

## Cost — read before applying

| Item | Monthly |
|---|---|
| **NAT Gateway** | **~$32.40** |
| Application Load Balancer | ~$16.20 |
| EC2 t4g.small | ~$12.26 |
| RDS db.t4g.micro | ~$12.41 |
| Storage, secrets | ~$3.00 |
| **Total** | **~$76/month** |

**Roughly $0.11/hour.** Build it, explore it, `terraform destroy`.

### Why a NAT Gateway here, when the other example avoided one

The instances must reach the internet to `dnf install docker` and pull `quay.io/keycloak/keycloak`. There is no way around that with a public container image.

**To eliminate it:** mirror the image into ECR, bake Docker into a custom AMI, and use VPC endpoints instead:

```hcl
module "network" { enable_nat_gateway = false }

module "endpoints" {
  source              = "../../modules/vpc-endpoints"
  interface_endpoints = ["ecr.api", "ecr.dkr", "secretsmanager", "ssm", "ssmmessages", "ec2messages"]
  gateway_endpoints   = ["s3"]     # REQUIRED — ECR layers live in S3
  # ...
}
```

Six interface endpoints across two AZs is ~$86/month — **more than the NAT Gateway.** Endpoints win on security posture, not on price. Do the arithmetic before assuming otherwise.

---

## What the user data does

`scripts/bootstrap-keycloak.sh` is rendered by `templatefile()` before it reaches AWS, then runs once as root:

1. **Install** `docker`, `firewalld`, `jq` from the AL2023 repos
2. **Configure firewalld** — open only 8080, 9000, 7800
3. **Fetch credentials** from Secrets Manager using the instance's IAM role
4. **Write** a root-only `0600` env file
5. **Pull** the Keycloak image, with retries
6. **Register** a systemd unit so it survives crashes and reboots
7. **Wait** for `/health/ready` before finishing

### Why firewalld when security groups already filter?

**Defence in depth.** Security groups are enforced in the AWS network; firewalld on the host. If a security group is ever widened by mistake — a careless console edit, an overly broad Terraform change — the host firewall is still standing. They fail independently.

```bash
firewall-cmd --permanent --zone=public --add-port=8080/tcp   # Keycloak HTTP
firewall-cmd --permanent --zone=public --add-port=9000/tcp   # health/metrics
firewall-cmd --permanent --zone=public --add-port=7800/tcp   # Infinispan clustering
firewall-cmd --reload
```

Port 22 is deliberately **not** opened. There is no key pair and no bastion — shell access is via Session Manager, which needs no inbound port at all.

> `--permanent` writes to disk; without it every rule vanishes on reload. Note also that Docker writes its own iptables rules for published ports and can bypass firewalld's filter chain, so the security group remains the authoritative control and firewalld is the second layer.

### Why credentials are fetched, not injected

Only the secret **ARNs** are passed into user data — and an ARN is not sensitive. The instance authenticates with its IAM role, scoped to exactly two secrets:

```hcl
resources = [
  module.database.master_user_secret_arn,
  module.keycloak_admin.secret_arn,
]
```

Not `"*"`. If this instance is compromised, the attacker gets those two secrets and nothing else.

---

## Keycloak details that catch people out

### Health checks are on a different port

Keycloak serves `/health/ready` on its **management port (9000)**, not the application port (8080).

```hcl
module "keycloak_tg" {
  port              = 8080                    # traffic
  health_check_port = "9000"                  # health  <-- different!
  health_check_path = "/health/ready"
}
```

Point the health check at 8080 and it 404s forever, every target is marked unhealthy, and the ALB returns 503 while Keycloak runs perfectly.

### Proxy headers are mandatory behind an ALB

```bash
KC_HTTP_ENABLED=true        # ALB terminates TLS; internal hop is plain HTTP
KC_PROXY_HEADERS=xforwarded # trust X-Forwarded-* from the ALB
KC_HOSTNAME=https://sso.example.com
```

Without `KC_PROXY_HEADERS`, Keycloak builds redirect URLs from its own internal address and **every login bounces to a private IP the browser cannot reach**.

### Clustering — why `desired_capacity = 1`

Keycloak holds session state in memory. Multiple **unclustered** nodes do not share it, so users get logged out at random as the ALB moves them between instances.

The target group enables sticky sessions, which mitigates but does not fix this. Before raising `desired_capacity`, configure Infinispan properly — `KC_CACHE=ispn` with a JDBC_PING or DNS_PING stack, plus port 7800 between nodes (already open in both the security group and the NACL).

### `t4g.nano` will not work

Keycloak is a JVM application. 512 MB is not enough to start it. `t4g.small` (2 GB) is the realistic minimum.

---

## The NACL layer

Network ACLs are **stateless** — every conversation needs rules in both directions, including the ephemeral high ports replies arrive on.

| Subnet | Ingress | Egress |
|---|---|---|
| Public | 80, 443 from `allowed_cidr` | 8080–9000 to VPC, 80/443 out (NAT) |
| Private | 8080–9000 + 5432 + 7800 from VPC | 443/80 out, 5432 + 7800 to VPC, **DNS 53** |

Plus auto-added ephemeral rules (TCP 1024–65535) in both directions.

**Forget the ephemeral rules and `docker pull` hangs forever** — no error, just silence, because the request leaves and the reply is dropped. Forget DNS egress and nothing resolves at all.

Set `enable_nacls = false` to build without them and compare.

---

## Debugging

```bash
# 1. THE command for any 503
eval "$(terraform output -raw check_target_health)"

# 2. Does the ALB itself answer? (touches no instance)
curl -i "$(terraform output -raw alb_dns_name | sed 's|^|http://|')/ping"

# 3. Find the instances
eval "$(terraform output -raw list_instances_command)"

# 4. Shell in — no SSH key, no open port 22
aws ssm start-session --target i-xxxxx

# 5. On the instance:
sudo tail -100 /var/log/user-data.log     # the bootstrap log
sudo docker logs keycloak                 # Keycloak's own output
sudo systemctl status keycloak
sudo firewall-cmd --list-all
curl -s localhost:9000/health/ready
```

| Symptom | Likely cause |
|---|---|
| 503, targets `unhealthy` | Health check on 8080 instead of 9000 |
| 503, targets `initial` for >10 min | Still pulling the image / running migrations. Check `user-data.log` |
| `Target.Timeout` | App SG missing the 9000 rule from the ALB SG |
| Login redirects to a private IP | `KC_PROXY_HEADERS` or `KC_HOSTNAME` wrong |
| `docker pull` hangs | NAT Gateway missing, or NACL ephemeral rules missing |
| Container exits immediately | Instance too small — `t4g.nano` cannot run a JVM |
| DB connection refused | Check the RDS security group references the app SG |

---

## Production checklist

This example is deliberately a starting point. Before real use:

- [ ] **HTTPS.** Add `acm-certificate` and pass `certificate_arn` to the ALB. Keycloak over plain HTTP is not acceptable for an identity provider
- [ ] **Restrict `allowed_cidr`.** An IdP is a high-value target
- [ ] `enable_deletion_protection = true`
- [ ] Set `hostname_url` to a real domain via the `route53-record` module
- [ ] Configure Infinispan clustering before scaling past one node
- [ ] Pin an exact image digest, not a floating tag
- [ ] Enable ALB access logs to an S3 bucket
- [ ] `multi_az = true` on the database
- [ ] Raise `backup_retention_period` to 30
- [ ] CloudWatch alarms on `UnHealthyHostCount`

---

## Clean up

```bash
terraform destroy
```

With `enable_deletion_protection = true` you must disable it first — that is the point of it.
