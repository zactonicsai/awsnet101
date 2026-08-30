# Lowest-Cost AWS CLI Web Stack

This project creates a small AWS web stack using separate Bash/AWS CLI scripts.

## Architecture

```text
Internet
   |
   | http://app.example.com
   v
Route 53 public hosted zone
   |
   | A Alias
   v
Internet-facing Network Load Balancer
   |
   | TCP 80
   v
Target Group
   |
   | TCP 8080
   v
EC2 t4g.nano
PRIVATE subnet
NO public IPv4
NO NAT Gateway
```

## Why this is inexpensive

- One Availability Zone instead of two.
- Network Load Balancer instead of an Application Load Balancer.
- One small `t4g.nano` Graviton EC2.
- One 8 GiB gp3 root disk.
- No NAT Gateway.
- No Elastic IP on EC2.
- HTTP for the simple lab example, so no certificate setup is required.

> This is a **cost-focused lab/small-service design**, not a high-availability production design.
> One Availability Zone means one AZ failure can make the site unavailable.

## Important networking idea

An internet-facing load balancer cannot live only in a private subnet.

This project therefore creates:

1. **Public subnet** — contains the internet-facing NLB.
2. **Private subnet** — contains EC2.
3. **Internet Gateway** — public route table points here.
4. **Private route table** — deliberately has no `0.0.0.0/0` route.
5. **No NAT Gateway** — avoids the NAT hourly cost.

The EC2 instance is still reachable by the NLB because both are inside the same VPC.

## Prerequisites

Install/configure:

```bash
aws --version
aws configure
aws sts get-caller-identity
```

The scripts are written for Bash and AWS CLI v2.

## 1. Configure your domain

Edit:

```text
config.sh
```

At minimum, change:

```bash
DOMAIN_NAME="${DOMAIN_NAME:-example.com}"
```

The default record is automatically:

```text
app.example.com
```

You can also change:

```bash
RECORD_NAME="${RECORD_NAME:-www.example.com}"
```

## 2. Make scripts executable

```bash
chmod +x *.sh create/*.sh destroy/*.sh
```

## 3. Create everything

```bash
./create-all.sh
```

The scripts run in this order:

```text
01 VPC
02 public + private subnets
03 Internet Gateway + route tables
04 security groups
05 private EC2
06 target group
07 Network Load Balancer
08 listener
09 Route 53 hosted zone + Alias
```

## 4. Route 53 hosted zone behavior

The Route 53 script first looks for an existing public hosted zone with the exact domain name.

### If the hosted zone already exists

It reuses it.

The destroy scripts delete only the Alias created by this project.

### If no hosted zone exists

The script creates one.

It prints the Route 53 name servers.

If the domain is registered somewhere else, such as another registrar, update that registrar to use those Route 53 name servers.

Until the registrar delegates DNS to those name servers, your public URL will not resolve correctly.

## 5. Test

See current status:

```bash
./show-status.sh
```

Check target health:

```bash
source .state.env

aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region us-east-1
```

Test the NLB directly:

```bash
source .state.env
curl -v "http://$NLB_DNS_NAME/"
```

Test Route 53:

```bash
curl -v http://app.example.com/
```

Replace the example name with your real record.

## The private EC2 demo server

Amazon Linux 2023 includes Python.

The EC2 user-data creates:

```text
/opt/cheapweb/index.html
```

and runs:

```bash
python3 -m http.server 8080
```

as a systemd service.

It does not need `dnf install`, `yum install`, or Internet access.

## Security groups

### NLB security group

Allows:

```text
Internet -> TCP 80 -> NLB
```

### EC2 security group

Allows only:

```text
NLB security group -> TCP 8080 -> EC2
```

No SSH/22 rule is created.

## Why there is no SSH

The EC2 is intentionally private and has no public IP.

This keeps the example simple and inexpensive.

If you need administrative access later, add an AWS-supported private-access method such as EC2 Instance Connect Endpoint or Systems Manager networking. Do not expose SSH/22 to the whole Internet.

## Destroy everything

Run:

```bash
./destroy-all.sh
```

Deletion order is important:

```text
Route 53 Alias
Listener
NLB
Target Group
EC2
Security Groups
Route Tables / Internet Gateway
Subnets
VPC
```

The script waits for the NLB and EC2 to disappear before deleting resources that depend on them.

## Individual create scripts

```text
create/01-vpc.sh
create/02-subnets.sh
create/03-internet-gateway-routing.sh
create/04-security-groups.sh
create/05-ec2.sh
create/06-target-group.sh
create/07-network-load-balancer.sh
create/08-listener.sh
create/09-route53.sh
```

You can run them individually, but run them in number order.

## Individual destroy scripts

```text
destroy/01-route53.sh
destroy/02-listener.sh
destroy/03-network-load-balancer.sh
destroy/04-target-group.sh
destroy/05-ec2.sh
destroy/06-security-groups.sh
destroy/07-internet-gateway-routing.sh
destroy/08-subnets.sh
destroy/09-vpc.sh
```

Run them in number order.

## State file

The scripts save AWS IDs to:

```text
.state.env
```

Example:

```bash
VPC_ID=vpc-...
PUBLIC_SUBNET_ID=subnet-...
PRIVATE_SUBNET_ID=subnet-...
INSTANCE_ID=i-...
TARGET_GROUP_ARN=arn:...
LOAD_BALANCER_ARN=arn:...
HOSTED_ZONE_ID=Z...
```

Do not delete `.state.env` until you have destroyed the stack.

## Production improvements

For production, consider:

- at least two Availability Zones
- two or more application instances
- Auto Scaling Group
- HTTPS/TLS with AWS Certificate Manager
- stronger monitoring
- AWS WAF if using an ALB/CloudFront design
- Systems Manager or another controlled management path
- backups
- alarms and budgets
