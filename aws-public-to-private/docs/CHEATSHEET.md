# One-Page Cheat Sheet

Print this. Everything else in the tutorial is explanation; this is the doing.

---

## Build it

```bash
# --- CLI route ---
cd cli
bash 01-network.sh        # VPC, subnets, gateway, routes    FREE    ~10s
bash 02-security.sh       # the two firewalls                FREE    ~5s
bash 03-compute.sh        # hidden servers                   ~$3/mo  ~1m
bash 04-loadbalancer.sh   # ALB + target group + listener    ~$16/mo ~3m
bash 06-verify.sh         # prove it works                   FREE

# --- Terraform route ---
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan            # ALWAYS read this
terraform apply
terraform output website_url
```

## Destroy it (do this!)

```bash
bash cli/99-destroy.sh
# or
cd terraform && terraform destroy
```

---

## The five diagnostic commands

```bash
# 1. THE BIG ONE — are the servers healthy?
aws elbv2 describe-target-health --target-group-arn <TG_ARN> --output table

# 2. Is the load balancer itself alive? (touches no server)
curl -i http://<ALB_DNS>/ping

# 3. Does the real app answer?
curl -i http://<ALB_DNS>/

# 4. Status code only
curl -s -o /dev/null -w '%{http_code}\n' http://<ALB_DNS>/

# 5. What did the server print while booting?
aws ec2 get-console-output --instance-id i-xxx --output text | tail -50
```

---

## Error → cause, at a glance

| You see | It means | Look at |
|---|---|---|
| **503** | No healthy targets | `describe-target-health` |
| **504** | Server too slow to answer | App performance, health check timeout |
| **502** | Server sent garbage | App crashing mid-response |
| **Timeout / no response** | ALB security group blocked you | Is port 80 open to your IP? |
| **`Target.Timeout`** | ALB can't reach the server | App SG must allow ALB SG on app port |
| **`Target.ResponseCodeMismatch`** | Server answered, not with 200 | Health check path, app behavior |
| **`InvalidSubnet`** | Gave fewer than 2 subnets | ALB needs 2 AZs, always |
| **`DependencyViolation`** | Something still uses it | Delete in reverse order |

**The isolation trick:** `/ping` works but `/` fails → your servers are the problem. Both fail → your network is the problem.

---

## The four required load balancer pieces

Miss any one and it silently fails:

1. **Load balancer** — `aws elbv2 create-load-balancer` (2 public subnets, 2 AZs)
2. **Target group** — `aws elbv2 create-target-group` (health check wants **200**)
3. **Register targets** — `aws elbv2 register-targets` ← **the forgotten one**
4. **Listener** — `aws elbv2 create-listener` (no listener = total silence)

---

## Costs at a glance

| Item | Per month |
|---|---|
| VPC / subnets / IGW / routes / security groups | **$0.00** |
| **Application Load Balancer** | **~$16.20** ⚠️ |
| EC2 t4g.nano | ~$3.07 |
| EBS gp3 8 GB | ~$0.64 |
| Route 53 hosted zone | ~$0.50 |
| Route 53 alias queries | **$0.00** |
| ~~NAT Gateway~~ (we avoided it) | ~~~$32.40~~ |

**Build + destroy in one hour ≈ $0.03.**

---

## Find money you forgot about

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output table
aws ec2 describe-addresses --query 'Addresses[?AssociationId==`null`].PublicIp' --output table
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output table
aws ec2 describe-nat-gateways --query 'NatGateways[?State==`available`].NatGatewayId' --output table
```

Anything listed is costing you money right now.

---

## Vocabulary in ten lines

- **VPC** — your fenced-off private network
- **Subnet** — one street inside it
- **Public subnet** — a subnet whose route table sends `0.0.0.0/0` to an internet gateway. *That is the only difference.*
- **Internet Gateway** — the one door in the fence
- **Security Group** — a stateful firewall around one resource; deny by default
- **ALB** — the public receptionist that hides your servers
- **Target group** — the receptionist's list of who's on duty, plus how to check
- **Health check** — asks for a page every 30s; **200 = alive**
- **Listener** — the instruction telling the ALB what to do with arrivals
- **ALIAS record** — Route 53's free, self-updating pointer to an AWS resource
