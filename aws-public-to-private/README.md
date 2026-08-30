# From the Internet to a Private Server: A Complete AWS Tutorial

**What you will build:** a real, public web address that anyone in the world can visit — where the actual server answering the request is hidden inside a private network with no connection to the internet at all.

**Reading level:** middle school. No prior AWS knowledge assumed.
**Time:** about 45 minutes.
**Cost:** about **5 cents** if you build it and delete it the same day. About **$20/month** if you leave it running.

---

## Table of Contents

1. [The Big Picture (start here)](#1-the-big-picture)
2. [The Pizza Restaurant Analogy](#2-the-pizza-restaurant-analogy)
3. [Every Word You Need to Know](#3-every-word-you-need-to-know)
4. [Before You Start](#4-before-you-start)
5. [**Quick Start: Build It in 5 Commands**](#5-quick-start-build-it-in-5-commands)
6. [The Long Way: Every Step Explained](#6-the-long-way-every-step-explained)
7. [How a Single Request Travels](#7-how-a-single-request-travels)
8. [Doing It With Terraform Instead](#8-doing-it-with-terraform-instead)
9. [What This Costs, Exactly](#9-what-this-costs-exactly)
10. [Cheaper and Fancier Variations](#10-cheaper-and-fancier-variations)
11. [When It Breaks: Troubleshooting](#11-when-it-breaks-troubleshooting)
12. [Best Practices and the Reasons Behind Them](#12-best-practices-and-the-reasons-behind-them)
13. [CLI vs Terraform: Pros and Cons](#13-cli-vs-terraform-pros-and-cons)
14. [Cleaning Up (do not skip this)](#14-cleaning-up)
15. [Where to Go Next](#15-where-to-go-next)

---

## 1. The Big Picture

Here is the problem this whole tutorial solves.

You have a web server. You want people on the internet to be able to visit it. The obvious solution is to put the server directly on the internet and give it a public address.

**That obvious solution is a bad idea.** A server sitting directly on the internet gets scanned by automated attack bots within minutes. Every open port is a door someone will try. If your server has a bug, an attacker is already touching it.

The professional solution is a **middleman**. You put one carefully-locked machine on the internet, and hide everything else behind it.

```
                          THE INTERNET
                       (everyone, including
                        people you distrust)
                               |
                               |  visitor types http://app.example.com
                               v
                     +-------------------+
                     |    ROUTE 53       |   "What is the address
                     |   (phone book)    |    for that name?"
                     +-------------------+
                               |
                               v
        +==============================================+
        |  YOUR VPC  (your own fenced-off area of AWS) |
        |                                              |
        |    +------------------------------------+    |
        |    |   INTERNET GATEWAY (the one gate)  |    |
        |    +------------------------------------+    |
        |                     |                        |
        |   - - - - - - - - - | - - - - - - - - - -    |
        |   PUBLIC SUBNETS    v                        |
        |   +--------------------------------------+   |
        |   |     APPLICATION LOAD BALANCER        |   |
        |   |     (the bouncer / receptionist)     |   |
        |   |  * has a public address              |   |
        |   |  * only accepts port 80              |   |
        |   |  * checks servers are alive          |   |
        |   +--------------------------------------+   |
        |          |                      |            |
        |   - - - -|- - - - - - - - - - - |- - - - -   |
        |   PRIVATE SUBNETS               |            |
        |          v                      v            |
        |   +-------------+       +-------------+      |
        |   |  SERVER 1   |       |  SERVER 2   |      |
        |   | 10.0.10.42  |       | 10.0.11.17  |      |
        |   |             |       |             |      |
        |   | NO PUBLIC   |       | NO PUBLIC   |      |
        |   | ADDRESS.    |       | ADDRESS.    |      |
        |   | Unreachable |       | Unreachable |      |
        |   | from the    |       | from the    |      |
        |   | internet.   |       | internet.   |      |
        |   +-------------+       +-------------+      |
        |    Availability          Availability        |
        |      Zone A                Zone B            |
        |   (data center 1)       (data center 2)      |
        +==============================================+
```

Traffic flows **one direction only**: inward, through a single controlled door. Your servers can answer questions, but they can never start a conversation with the outside world. If someone breaks into your application, they land in a room with no exit.

---

## 2. The Pizza Restaurant Analogy

Every piece of AWS jargon in this tutorial maps onto something in a pizza restaurant. Keep this table in mind and the rest becomes easy.

| AWS Thing | Restaurant Thing | What it really does |
|---|---|---|
| **Region** | Which city the restaurant is in | A geographic area, e.g. Northern Virginia |
| **Availability Zone** | Two separate buildings on different blocks | Physically separate data centers. If one floods, the other keeps working |
| **VPC** | The whole property, with a fence around it | Your own private network inside AWS |
| **Subnet** | One room in the building | A slice of the network. Public = has a door to the street. Private = interior room, no street door |
| **Internet Gateway** | The front door to the street | The only way traffic enters or leaves the property |
| **Route Table** | The signs on the walls | Tell traffic which way to go. **This is the ONLY thing that makes a subnet public** |
| **Security Group** | A locked door on one specific room | A firewall around one machine. Denies everything unless you say "allow" |
| **EC2 Instance** | A chef in the back kitchen | A virtual computer that does the real work |
| **Load Balancer** | The host at the front desk | Greets everyone, checks which chefs are free, hands off the order |
| **Target Group** | The host's clipboard of chefs on duty | The list of servers, plus how to check they are still standing |
| **Health Check** | Host peeks in the kitchen every 30 seconds | "Still alive?" If a chef doesn't answer twice in a row, they get crossed off the list |
| **Listener** | The host's instruction card | "When someone walks in the door, take them to a chef on the clipboard" |
| **Route 53** | The phone book | Turns "Tony's Pizza" into a street address |
| **Alias Record** | A phone book entry that auto-updates | If the restaurant moves, the entry follows it automatically |

**The one sentence that matters most:** the host stands at the front desk where customers can see them. The chefs work in a back kitchen with no street entrance. Customers never meet a chef, and that is the entire point.

---

## 3. Every Word You Need to Know

### IP addresses and CIDR

An **IP address** is a computer's phone number: `10.0.10.42`.

A **CIDR block** is a way to write a *range* of addresses. It looks like `10.0.0.0/16`.

The number after the slash tells you how much of the address is locked in place. Bigger number = smaller range.

| CIDR | Number of addresses | Restaurant equivalent |
|---|---|---|
| `10.0.0.0/16` | ~65,536 | The whole property |
| `10.0.0.0/24` | 256 | One room |
| `10.0.0.42/32` | Exactly 1 | One specific chair |
| `0.0.0.0/0` | Every address on earth | "Anyone, anywhere" |

You will see `0.0.0.0/0` constantly. It means **the entire internet**. When you use it in a *firewall* rule, be certain that is what you want. When you use it in a *route*, it just means "the default direction for anything not local."

> **Why 10.0.x.x?** Certain ranges (`10.x`, `172.16-31.x`, `192.168.x`) are reserved as **private** — they are not routable on the public internet and every company reuses them internally. This is why your home Wi-Fi is probably `192.168.1.something`.

### HTTP status codes

When a web server answers, it sends a three-digit number saying how it went.

| Code | Meaning | In this tutorial |
|---|---|---|
| **200** | OK — here's your page | ✅ What we want. The health check requires exactly this |
| 301/302 | Moved — go look over there | Redirects |
| 403 | Forbidden — you're not allowed | Permissions problem |
| 404 | Not found — no such page | Wrong path |
| **502** | Bad Gateway | The ALB reached your server but got gibberish back |
| **503** | Service Unavailable | **The ALB has no healthy servers.** By far your most likely error |
| **504** | Gateway Timeout | The ALB reached your server but it never replied in time |

Memorize **503**. It is what you get when the load balancer works perfectly but every server failed its health check. It means "my networking is fine, my servers are the problem."

### Public vs Private subnet — the actual difference

This trips up almost everyone, so read it twice.

There is **no checkbox** in AWS labeled "make this subnet public." A subnet is public for exactly one reason:

> **Its route table contains a route sending `0.0.0.0/0` to an Internet Gateway.**

That's it. That is the entire difference. Same hardware, same everything — one has a road sign pointing at the exit, the other doesn't.

---

## 4. Before You Start

### What you need

1. **An AWS account.** [Sign up here](https://aws.amazon.com/free/). Requires a credit card. New accounts get a Free Tier for 12 months.
2. **AWS CLI version 2** installed.
3. **Terraform 1.9+** — only if you want to do the Terraform version.
4. A terminal (Terminal on Mac/Linux, or WSL/PowerShell on Windows).

### Installing the AWS CLI

```bash
# macOS
brew install awscli

# Linux (x86_64)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Windows: download and run the MSI installer from
# https://awscli.amazonaws.com/AWSCLIV2.msi

# Confirm it worked — you want to see "aws-cli/2.x.x"
aws --version
```

### Logging in

```bash
aws configure
```

It asks four questions:

| Question | What to type |
|---|---|
| AWS Access Key ID | Your key (see below) |
| AWS Secret Access Key | Your secret |
| Default region name | `us-east-1` |
| Default output format | `json` |

**Getting your keys — and doing it safely:**

AWS strongly recommends you **do not** create access keys for your root account (the email you signed up with). Instead:

1. Open the **IAM** console → **Users** → **Create user**
2. Name it something like `cli-admin`
3. Attach the `AdministratorAccess` policy (fine for learning; too broad for a real job)
4. Open the new user → **Security credentials** → **Create access key** → choose **Command Line Interface**
5. Copy both values immediately — the secret is shown exactly once

> ⚠️ **Never** commit access keys to Git, paste them in a chat, or put them in a script. If one leaks, bots find it within minutes and mine cryptocurrency on your credit card. If that happens, delete the key in IAM immediately.

Verify you're logged in:

```bash
aws sts get-caller-identity
```

You should see your account number and user ARN. If you see an error, `aws configure` didn't take.

### Set a billing alarm first

Before creating anything that costs money, protect yourself:

1. Console → **Billing and Cost Management** → **Budgets** → **Create budget**
2. Choose **Zero spend budget** or set a **Monthly cost budget** of `$5`
3. Enter your email

Now AWS emails you the moment you're on track to spend more than expected. This takes two minutes and has saved countless people from a shocking bill.

---

## 5. Quick Start: Build It in 5 Commands

This is the one full example, start to finish. Read section 6 afterward for what each piece actually did.

```bash
# 1. Go into the CLI folder
cd cli

# 2. Build the network — VPC, subnets, gateway, routes   (free, ~10 seconds)
bash 01-network.sh

# 3. Build the firewalls                                  (free, ~5 seconds)
bash 02-security.sh

# 4. Launch the hidden servers                            (~1 minute)
bash 03-compute.sh

# 5. Build the load balancer and connect everything       (~3 minutes)
bash 04-loadbalancer.sh
```

The last script prints your URL. Wait about a minute for the health checks to pass, then:

```bash
bash 06-verify.sh
```

You should see:

```
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8

It works!
Served by: ip-10-0-10-42.ec2.internal
Private IP: 10.0.10.42
Path requested: /
```

**Look at that output carefully.** You just loaded a page from a machine whose only address is `10.0.10.42` — an address that does not exist on the public internet and cannot be reached from it. The load balancer carried your request across that boundary.

**Optional — attach your own domain** (skip if you don't own one):

```bash
ENABLE_DNS=true HOSTED_ZONE_NAME=yourdomain.com SUBDOMAIN=app bash 05-dns.sh
```

**When you're done — this is not optional:**

```bash
bash 99-destroy.sh
```

---

## 6. The Long Way: Every Step Explained

Now the same thing, one concept at a time.

### Step 1 — The VPC (free)

```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16
```

A **VPC** is your own private slice of AWS's network. Nothing inside it can reach the internet, and nothing on the internet can reach in, until you explicitly build a path.

You then have to switch on two DNS settings that are off by default:

```bash
aws ec2 modify-vpc-attribute --vpc-id vpc-xxx --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id vpc-xxx --enable-dns-hostnames
```

They must be two separate calls — AWS rejects both flags at once. Without them the load balancer misbehaves in confusing ways.

### Step 2 — Availability Zones (free)

An **Availability Zone (AZ)** is a physically separate data center: different building, different power, different network. `us-east-1a` and `us-east-1b` are miles apart.

**An Application Load Balancer requires at least two AZs.** This is not optional. AWS wants your site to survive a data center failure, so it refuses to build a single-AZ load balancer.

### Step 3 — Subnets (free)

We create four:

| Subnet | CIDR | AZ | Purpose |
|---|---|---|---|
| public-1 | 10.0.0.0/24 | AZ A | Load balancer network card |
| public-2 | 10.0.1.0/24 | AZ B | Load balancer network card |
| private-1 | 10.0.10.0/24 | AZ A | Server 1 |
| private-2 | 10.0.11.0/24 | AZ B | Server 2 |

> **Why do the public subnets need to be so big?** They don't. `/24` gives 256 addresses when the ALB only needs about 8. But addresses inside a VPC are free and there is no benefit to being stingy. Leave room to grow.

> **AWS silently takes 5 addresses from every subnet** — the first four and the last one — for its own routing and DNS. A `/24` gives you 251 usable, not 256.

Public subnets get one extra setting:

```bash
aws ec2 modify-subnet-attribute --subnet-id subnet-xxx --map-public-ip-on-launch
```

Private subnets deliberately do **not** get this.

### Step 4 — The Internet Gateway (free)

```bash
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --internet-gateway-id igw-xxx --vpc-id vpc-xxx
```

The gate in the fence. Creating and attaching it opens **nothing** — it is inert until a route table points at it. Think of it as installing a door but not yet telling anyone where the door is.

### Step 5 — Route tables (free) — the most important step

```bash
# PUBLIC route table
aws ec2 create-route-table --vpc-id vpc-xxx
aws ec2 create-route \
  --route-table-id rtb-public \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id igw-xxx
```

Read that route out loud: *"anything headed for anywhere in the world leaves through the internet gateway."*

**That single command is what makes a subnet public.** Nothing else.

```bash
# PRIVATE route table — notice there is no create-route at all
aws ec2 create-route-table --vpc-id vpc-xxx
```

Empty on purpose. AWS automatically adds one invisible route for `10.0.0.0/16` (the VPC itself) that you cannot remove. That local route is what lets the load balancer in a public subnet reach the servers in a private subnet — internal traffic never needs the gateway.

> 💰 **Where the $32/month usually goes.** Most tutorials add a **NAT Gateway** here so private servers can download software updates. A NAT Gateway costs about **$32/month plus $0.045 per GB**, making it the single most expensive item in a typical small setup. We avoid it entirely by using software that is already on the machine. See section 10 for when you actually need one.

Finally, associate each table with its subnets. A route table attached to nothing does nothing.

### Step 6 — Security groups (free)

A **security group** is a firewall wrapped around individual resources, not around a subnet.

**Two rules to memorize:**

1. **Deny by default.** Everything is blocked unless a rule allows it. You only ever write "allow" rules.
2. **Stateful.** If a request is allowed in, the reply is automatically allowed back out. You never write a rule for the response.

We create two groups:

```bash
# ALB group: let the internet in on port 80
aws ec2 authorize-security-group-ingress \
  --group-id sg-alb --protocol tcp --port 80 --cidr 0.0.0.0/0

# App group: let ONLY THE LOAD BALANCER in on port 8080
aws ec2 authorize-security-group-ingress \
  --group-id sg-app --protocol tcp --port 8080 --source-group sg-alb
```

**`--source-group` is the single most valuable security idea in this tutorial.** Instead of allowing an IP range, we allow *another security group*. Read it as: *"allow anything wearing the load balancer's badge."*

Why this beats using an IP range:
- Load balancer IPs change constantly; a badge never does
- If someone launches a rogue server in the same subnet, it still can't connect — it isn't wearing the badge
- It documents intent. `--source-group sg-alb` says what you mean; `10.0.0.0/24` doesn't

We also **remove** the default allow-all-outbound rule from the app servers. They need to download nothing, so they get no way out at all. They can still reply to the load balancer, because security groups are stateful.

| | Security Group | Network ACL |
|---|---|---|
| Wraps | One resource | A whole subnet |
| Rules | Allow only | Allow **and** deny |
| Memory | Stateful | Stateless (write both directions) |
| Use it for | Almost everything | Rare, coarse blocking |

Beginners should use security groups and leave NACLs at their defaults.

### Step 7 — The servers (~$3.07/month each)

```bash
aws ec2 run-instances \
  --image-id ami-xxx \
  --instance-type t4g.nano \
  --subnet-id subnet-private-1 \
  --security-group-ids sg-app \
  --no-associate-public-ip-address \
  --user-data file://bootstrap.sh
```

Three ideas here:

**The AMI.** An **Amazon Machine Image** is a hard-drive snapshot used as a template. AMI IDs are different in every region and change with every security patch, so **never hard-code one**. We read AWS's public pointer instead:

```bash
aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  --query 'Parameter.Value' --output text
```

That always returns today's newest Amazon Linux 2023 image. It's free to read.

**User data.** A script AWS runs **once**, automatically, on first boot. It's how a blank machine becomes a web server with nobody logging in. Ours writes a ~25-line Python program and registers it with `systemd` so it restarts on crash and survives reboots.

Our script downloads **nothing**. Python 3 is already in the Amazon Linux image. That's what lets us skip the NAT Gateway.

**No public IP.** `--no-associate-public-ip-address` plus a private subnet means these machines have no internet-facing address at all.

> **Choosing an instance type.** `t4g.nano` uses ARM (Graviton) chips at ~$3.07/month — the cheapest option, and it's what we default to. If your account is under 12 months old, `t3.micro` is **free** for 750 hours/month. ARM and Intel need *different AMIs*, which our scripts handle automatically. If you hand-pick a `t4g` type with an x86 image, the instance simply won't boot.

### Step 8 — The load balancer (~$16.20/month) ⚠️

This is where the money goes and where the magic happens. **Four separate pieces** must all exist:

#### 8a. The load balancer itself

```bash
aws elbv2 create-load-balancer \
  --name web-demo-alb \
  --type application \
  --scheme internet-facing \
  --subnets subnet-public-1 subnet-public-2 \
  --security-groups sg-alb
```

> **Note the command is `elbv2`, not `elb`.** `elbv2` covers modern ALBs and NLBs. Plain `elb` is the retired Classic Load Balancer. Mixing them up produces baffling errors.

- `--scheme internet-facing` gives it public IPs. `internal` would hide it inside the VPC.
- `--type application` means Layer 7 — it understands HTTP paths, hostnames, and headers.
- Two subnets in two AZs are **mandatory**.

#### 8b. The target group

```bash
aws elbv2 create-target-group \
  --name web-demo-tg \
  --protocol HTTP --port 8080 \
  --vpc-id vpc-xxx \
  --target-type instance \
  --health-check-path / \
  --matcher HttpCode=200 \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2
```

The target group is the clipboard: who's on duty, and how to check they're still standing.

**The health check is the heart of it.** Every 30 seconds the ALB quietly requests `/` from every server. If it gets **HTTP 200**, that server stays on the list. Two failures in a row and it's crossed off — traffic instantly stops going there, with no human involved. Two successes and it's back.

This is why the tutorial insists on "returns simple text with a 200 response code." **200 is the password.** A server returning 404 or 500 is treated as dead, even though it's clearly running.

> Note the public arrives on **port 80** while the ALB forwards to **port 8080**. Those don't have to match. Port translation is completely normal.

#### 8c. Registering the targets — the step everyone forgets

```bash
aws elbv2 register-targets \
  --target-group-arn arn:... \
  --targets Id=i-xxx,Port=8080 Id=i-yyy,Port=8080
```

Creating servers and creating a target group does **not** connect them. Without this command, everything looks perfect in the console and your website returns **503** forever.

#### 8d. The listener

```bash
aws elbv2 create-listener \
  --load-balancer-arn arn:... \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=arn:...
```

The listener is the ALB's ear. **Without a listener, the load balancer exists but answers nothing at all** — no error, no response, just silence.

#### 8e. Bonus: a debugging rule

```bash
aws elbv2 create-rule \
  --listener-arn arn:... \
  --priority 100 \
  --conditions Field=path-pattern,Values=/ping \
  --actions 'Type=fixed-response,FixedResponseConfig={MessageBody="pong",StatusCode=200,ContentType=text/plain}'
```

This makes the ALB answer `/ping` **by itself**, never touching a server. It's a superb diagnostic:

- `/ping` works but `/` returns 503 → your **servers or health check** are broken
- Both fail → your **security group, subnets, or routes** are broken

That single fact splits your problem space in half instantly.

### Step 9 — DNS (optional, $0.50/month)

Your site already works at `web-demo-alb-1234567890.us-east-1.elb.amazonaws.com`. Ugly, but functional.

To use `app.example.com` you need a **hosted zone** — a container holding all DNS records for one domain.

**Create the hosted zone by hand, once.** Then let scripts manage only the records inside it. Here's why that matters: creating a zone assigns 4 random nameservers that you must copy to your domain registrar. If automation ever deletes and recreates the zone, you get 4 *different* nameservers and **your domain goes dark** until you manually update the registrar again. Our scripts therefore *look up* your zone rather than create it.

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id ZXXXXXXXXXXXX \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "app.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "dualstack.web-demo-alb-123.us-east-1.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

**Why an ALIAS and not a CNAME:**

| | A record | CNAME | **ALIAS** |
|---|---|---|---|
| Points at | An IP address | Another name | An AWS resource |
| Works for a load balancer? | ❌ ALB IPs change | ⚠️ Yes, but | ✅ Yes |
| Works at the domain root? | ✅ | ❌ **Illegal** | ✅ |
| Query cost | $0.40/M | $0.40/M | **Free** |
| Follows IP changes? | ❌ | ✅ | ✅ |

A load balancer has **no fixed IP** — AWS swaps them as it scales. So a plain A record is impossible. A CNAME works for a subdomain but is illegal at the root (`example.com` itself). An ALIAS is Amazon's own record type that solves both problems and is free to query. **For any AWS resource, always prefer ALIAS.**

> Two traps: the `HostedZoneId` *inside* `AliasTarget` is the **ALB's** hidden zone ID (`CanonicalHostedZoneId`), not your domain's. Confusing those two is the most common Route 53 mistake. And the `dualstack.` prefix asks for both IPv4 and IPv6 — it's the recommended form and costs nothing.

---

## 7. How a Single Request Travels

Someone in Tokyo types `http://app.example.com`. Here is every hop:

```
 1. BROWSER      "What is the IP for app.example.com?"
                        |
 2. DNS          Route 53 sees an ALIAS record, looks up the
                 load balancer, and returns its current public IPs.
                 (Free, because it's an alias to an AWS resource.)
                        |
 3. INTERNET     The request travels to that IP, arriving at an
                 AWS edge router, then into your VPC.
                        |
 4. IGW          The Internet Gateway lets it in because the public
                 subnet's route table has 0.0.0.0/0 -> igw.
                        |
 5. SG CHECK     ALB security group: "Port 80 from 0.0.0.0/0?
                 Yes, that's allowed." ✅
                 (Any other port would be silently dropped here.)
                        |
 6. LISTENER     ALB listener on port 80 wakes up.
                 Is the path /ping? No -> use the default action:
                 forward to the target group.
                        |
 7. TARGET       Target group checks its clipboard.
    GROUP        Server 1: healthy ✅   Server 2: healthy ✅
                 Round-robin picks Server 1.
                        |
 8. ROUTE        ALB opens a NEW connection to 10.0.10.42:8080.
                 This uses the VPC's automatic local route —
                 no internet gateway involved, it's all internal.
                        |
 9. SG CHECK     App security group: "Port 8080 from something
                 wearing the ALB badge? Yes." ✅
                        |
10. APP          Python server's do_GET() runs. Builds the text,
                 sends status 200, sends the body.
                        |
11. RETURN       Reply flows back to the ALB (allowed automatically —
                 security groups are stateful), then out through the
                 IGW, across the ocean, to the browser in Tokyo.
                        |
12. DISPLAY      "It works!" appears on screen.

    Total elapsed time: roughly 50 milliseconds.
```

**Notice step 8.** The load balancer does not "forward" your original connection. It terminates it and opens a brand-new one to the server. That's why the server never sees the visitor's real IP directly — it arrives in the `X-Forwarded-For` header instead. This connection break is also part of the security benefit: the outside world's packets never physically touch your server.

**Notice step 7.** If both servers were unhealthy, the ALB would have nowhere to send the request and would return **503** on its own. That's why 503 means "my servers are broken," not "my network is broken."

---

## 8. Doing It With Terraform Instead

The CLI scripts teach you what happens. Terraform is what you'd actually use at work.

```bash
cd terraform

# Copy the example settings and edit them
cp terraform.tfvars.example terraform.tfvars

# Download the AWS provider plugin (one time, per project)
terraform init

# Check your syntax without contacting AWS
terraform validate

# See exactly what WILL be created — creates nothing yet.
# ALWAYS read the plan. This is the habit that prevents disasters.
terraform plan

# Build it. Type 'yes' when prompted.
terraform apply

# Get your URL back any time
terraform output website_url
```

When you're done — one command deletes everything, in the correct order:

```bash
terraform destroy
```

**That last line is the whole argument for Terraform.** Our hand-written `99-destroy.sh` is 150 lines of careful dependency ordering, retry loops, and circular-reference untangling. Terraform builds that dependency graph automatically from the fact that `aws_lb.main` references `aws_subnet.public`.

### File map

| File | What's in it |
|---|---|
| `versions.tf` | Which Terraform and provider versions are allowed |
| `variables.tf` | All the settings knobs, with validation |
| `network.tf` | VPC, subnets, internet gateway, route tables |
| `security.tf` | The two security groups and their rules |
| `compute.tf` | The EC2 instances |
| `alb.tf` | Load balancer, target group, listener, /ping rule |
| `dns.tf` | Optional Route 53 alias record |
| `outputs.tf` | The URL and helpful commands, printed at the end |
| `user_data.sh` | The bootstrap script (shared with the CLI version) |

### Terraform ideas worth knowing

```hcl
# COUNT — make N copies. count.index is 0, then 1, then 2...
resource "aws_subnet" "public" {
  count      = length(var.public_subnet_cidrs)
  cidr_block = var.public_subnet_cidrs[count.index]
}

# SPLAT — "the .id of every one of them"
subnets = aws_subnet.public[*].id

# IMPLICIT DEPENDENCY — because this line mentions aws_vpc.main,
# Terraform knows the VPC must exist first. You never write an
# ordering instruction; the references ARE the ordering.
vpc_id = aws_vpc.main.id

# CONDITIONAL CREATION — count 1 or 0 is Terraform's "only if"
count = var.enable_dns ? 1 : 0

# DATA SOURCE — read something that already exists instead of making it
data "aws_availability_zones" "available" {
  state = "available"
}
```

> **On Terraform state:** `terraform apply` writes a file called `terraform.tfstate` recording what it built. **Guard it.** Delete it and Terraform forgets your infrastructure exists (leaving it running and billing). It can also contain sensitive values, so never commit it to Git — our `.gitignore` blocks it. On a real team you'd store state remotely in S3 with DynamoDB locking so two people can't apply at once.

---

## 9. What This Costs, Exactly

Prices are `us-east-1`, accurate as of this writing. **Always confirm against the [AWS Pricing Calculator](https://calculator.aws/)** — prices change.

| Resource | Price | Free tier? |
|---|---|---|
| VPC, subnets, route tables | **$0.00** | Always free |
| Internet Gateway | **$0.00** | Always free |
| Security groups | **$0.00** | Always free |
| **Application Load Balancer** | **~$16.20/mo** ($0.0225/hr) | ❌ **Not free. The big one.** |
| ALB capacity units (LCU) | ~$0.01/mo at demo traffic | Tiny for a demo |
| EC2 `t4g.nano` | ~$3.07/mo ($0.0042/hr) | ❌ |
| EC2 `t3.micro` | ~$7.59/mo | ✅ **750 hrs/mo free for 12 months** |
| EBS gp3, 8 GB | ~$0.64/mo | ✅ 30 GB free for 12 months |
| Route 53 hosted zone | **$0.50/mo** | ❌ |
| Route 53 alias queries | **$0.00** | ✅ Always free to AWS resources |
| Data transfer out | $0.09/GB after 100 GB/mo free | ✅ First 100 GB free |
| ~~NAT Gateway~~ | ~~$32.40/mo + $0.045/GB~~ | **We avoided this entirely** |

### Realistic totals

| Scenario | Monthly | Notes |
|---|---|---|
| **Built and destroyed in 1 hour** | **~$0.03** | Do this while learning |
| **Built and destroyed same day (8 hrs)** | **~$0.20** | Still trivial |
| 1 server, no DNS, running 24/7 | ~$19.91 | |
| 2 servers + DNS, running 24/7 | ~$24.12 | Production-shaped |
| **If you'd used a NAT Gateway** | **+$32.40** | More than the rest combined |

### Where beginners actually get burned

1. **Forgetting to destroy.** An idle ALB bills identically to a busy one. `bash 99-destroy.sh`.
2. **NAT Gateways.** Two of them (one per AZ, as most guides recommend) is $65/month.
3. **Elastic IPs left unattached.** An EIP is free while attached, ~$3.60/mo while sitting idle.
4. **Orphaned EBS volumes.** A deleted instance can leave its disk behind, billing forever. Our config sets `DeleteOnTermination=true`.
5. **Old snapshots.** They quietly accumulate.

Check for leftovers:

```bash
# Any load balancers still running?
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output table

# Any unattached (billing!) Elastic IPs?
aws ec2 describe-addresses --query 'Addresses[?AssociationId==`null`].PublicIp' --output table

# Any orphaned disks?
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].{ID:VolumeId,GB:Size}' --output table
```

---

## 10. Cheaper and Fancier Variations

### Variation A: No servers at all — $16.70/month

Delete the EC2 instances entirely and let the load balancer answer directly:

```hcl
default_action {
  type = "fixed_response"
  fixed_response {
    content_type = "text/plain"
    message_body = "It works!"
    status_code  = "200"
  }
}
```

**Pros:** cheapest possible version with an ALB; nothing to patch or maintain; instant.
**Cons:** it isn't a real application — it can't do anything dynamic.
**Use it for:** health endpoints, maintenance pages, testing your DNS and TLS setup before the app is ready.

### Variation B: Lambda targets — ~$16.70/month, real logic, no servers

A target group can have `target_type = "lambda"`. The ALB invokes a function instead of contacting a server.

**Pros:** no servers to patch; generous free tier (1M requests/month); scales to zero.
**Cons:** cold starts add latency; the ALB is still the dominant cost; a different mental model.
**Use it for:** low, spiky traffic where you'd rather not own a machine.

### Variation C: Skip the load balancer entirely — ~$3/month

One EC2 instance in a *public* subnet with an Elastic IP.

**Pros:** by far the cheapest; simplest to reason about.
**Cons:** ❌ **no private subnet, so the server is directly exposed**; single point of failure; no health checks; no easy HTTPS. This throws away everything this tutorial is teaching.
**Use it for:** a throwaway personal experiment. Never for anything real.

### Variation D: Network Load Balancer instead — ~$16.20/month

**Pros:** slightly cheaper at high volume; much lower latency; handles millions of connections; gets a static IP.
**Cons:** Layer 4 only — no path routing, no host routing, no fixed responses.
**Use it for:** raw TCP, gaming, or extreme throughput. **For a website, use the ALB.**

### Variation E: CloudFront in front — adds ~$1-5/month

A CDN caching your content at ~600 edge locations worldwide.

**Pros:** dramatically faster for distant users; free TLS certificate; absorbs traffic spikes; free DDoS protection via AWS Shield Standard; can *reduce* your bill by cutting origin traffic.
**Cons:** another moving part; cache invalidation is its own skill.
**Use it for:** any site with a real global audience.

### Variation F: Adding HTTPS — free certificate

Right now everything is plain HTTP, which is fine for a lesson and **unacceptable for anything real**. Anyone on the network path can read the traffic.

The fix is genuinely free:

```bash
# 1. Request a certificate (AWS Certificate Manager — $0 for ALB use)
aws acm request-certificate \
  --domain-name app.example.com \
  --validation-method DNS

# 2. Add the CNAME record ACM gives you to Route 53 to prove ownership
# 3. Create a listener on port 443 with the certificate attached
# 4. Change the port 80 listener to redirect to 443
```

The redirect action looks like:

```hcl
default_action {
  type = "redirect"
  redirect {
    port        = "443"
    protocol    = "HTTPS"
    status_code = "HTTP_301"
  }
}
```

ACM certificates are free when used with an ALB and **renew themselves automatically**. There is no reason to run production on HTTP.

### When you DO need a NAT Gateway

We skipped it, but be honest about when it's required. You need one if your private servers must:

- Install or update software packages from the internet
- Call third-party APIs (Stripe, Twilio, an external database)
- Send outbound webhooks

**Cheaper alternatives before you reach for one:**

| Option | Cost | Good for |
|---|---|---|
| **VPC Gateway Endpoint** (S3, DynamoDB) | **Free** | Reaching S3 or DynamoDB privately |
| VPC Interface Endpoint | ~$7.20/mo each | Reaching a specific AWS service |
| Bake dependencies into a custom AMI | Free | Software that rarely changes |
| **One** NAT Gateway shared across AZs | ~$32/mo | Accepting reduced resilience to save money |
| One NAT per AZ | ~$65/mo | Real production |

The S3 Gateway Endpoint being free is worth remembering — it's a genuinely free way to give private servers S3 access.

---

## 11. When It Breaks: Troubleshooting

### Start here, always

```bash
aws elbv2 describe-target-health --target-group-arn <your-tg-arn> --output table
```

**This one command solves most problems.** If `State` isn't `healthy`, nothing else matters yet.

| State | Meaning | Do this |
|---|---|---|
| `initial` | Still running first checks | Wait 60 seconds |
| `healthy` | ✅ Working | Problem is elsewhere |
| `unhealthy` | Answered wrong, or not at all | See the table below |
| `unused` | Registered but no listener routes to it | Create the listener |
| `draining` | Being removed on purpose | Normal during changes |

### Diagnosing an unhealthy target

The `Reason` field is specific and useful:

| Reason | What it means | Fix |
|---|---|---|
| `Target.Timeout` | ALB got no answer at all | **Almost always the security group.** Does the app SG allow the ALB SG on the app port? |
| `Target.ResponseCodeMismatch` | Server replied, but not with 200 | Your app returns 404/500, or the health check path is wrong |
| `Target.FailedHealthChecks` | Connection refused | App isn't running, or is bound to `127.0.0.1` instead of `0.0.0.0` |
| `Target.NotInUse` | Wrong AZ or state | Target group is in a different VPC than the instance |
| `Elb.InternalError` | AWS-side hiccup | Wait, then retry |

### The full error table

| Symptom | Most likely cause | Fix |
|---|---|---|
| **503 Service Unavailable** | No healthy targets | Run `describe-target-health` |
| **504 Gateway Timeout** | Server reached but too slow | Check the app; raise health check timeout |
| **502 Bad Gateway** | Malformed response from the server | App is crashing mid-response |
| **Connection times out entirely** | ALB security group blocking you | Is port 80 open to your IP? Check `ALLOWED_CIDR` |
| **`could not resolve host`** | DNS problem | Wait for propagation; try `dig +short yourdomain.com` |
| **`InvalidSubnet: at least two subnets`** | Only gave one subnet | ALBs require 2 AZs. Not negotiable |
| **`DependencyViolation` on delete** | Something still references it | Delete in the right order — see `99-destroy.sh` |
| **`InvalidGroup.InUse`** | SG attached, or referenced by another SG | Remove cross-references first |
| **`UnauthorizedOperation`** | IAM permissions missing | Your user needs EC2, ELB, and Route 53 permissions |
| **Instance won't boot** | ARM/x86 mismatch | `t4g.*` needs an **arm64** AMI |
| **Website works, custom domain doesn't** | DNS not propagated, or wrong zone ID | Check the `AliasTarget.HostedZoneId` is the **ALB's**, not yours |

### The isolation trick

```bash
curl -i http://<alb-dns>/ping    # answered by the ALB itself
curl -i http://<alb-dns>/        # answered by your servers
```

| `/ping` | `/` | Conclusion |
|---|---|---|
| ✅ 200 | ✅ 200 | Everything works |
| ✅ 200 | ❌ 503 | **Networking is fine.** Servers or health check are broken |
| ❌ fails | ❌ fails | **Servers are irrelevant.** Security group / subnets / routes / DNS |

This cuts your search space in half in five seconds.

### How to actually see inside a private server

There's no SSH — the machine has no public IP and no bastion. Two options:

**Option 1 — read the console output (free, works now):**

```bash
aws ec2 get-console-output --instance-id i-xxx --output text | tail -50
```

Our bootstrap script logs to the console, so you'll see whether it succeeded.

**Option 2 — Session Manager (~$21.60/month, do not leave on):**

Real shell access needs three VPC interface endpoints (`ssm`, `ssmmessages`, `ec2messages`) at ~$7.20/month each, plus an IAM role on the instance. Powerful, but for a tutorial it triples your bill. Use option 1.

---

## 12. Best Practices and the Reasons Behind Them

### Security

✅ **Put application servers in private subnets.** If a server can't be reached, it can't be attacked directly.

✅ **Reference security groups, not IP ranges.** `--source-group sg-alb` survives IP changes and blocks rogue neighbors.

✅ **Least privilege everywhere.** Open port 8080 to one security group, not port 0-65535 to `0.0.0.0/0`. Our app runs as user `nobody`, not root.

✅ **Force IMDSv2** (`HttpTokens=required`). This closes an entire family of attacks where a web bug is used to steal the server's AWS credentials. Free.

✅ **Encrypt disks at rest.** Free. There is no argument against it.

✅ **Use HTTPS in production.** ACM certificates are free and auto-renewing.

❌ **Never hard-code credentials.** Use IAM roles for AWS access and Secrets Manager or Parameter Store for everything else.

❌ **Never open SSH (port 22) to `0.0.0.0/0`.** Bots find it in minutes. Use Session Manager instead.

### Reliability

✅ **Always span at least two Availability Zones.** It's free insurance, and the ALB forces it anyway.

✅ **Make health checks meaningful.** A check hitting a static page passes even when your database is down. A good check verifies dependencies too.

✅ **Match the deregistration delay to your slowest request.** Default 300s is safe but slow; too short cuts off users mid-request.

✅ **Consider an Auto Scaling Group.** Instead of fixed instances, an ASG replaces failures automatically and adjusts capacity with demand. It's the natural next step after this tutorial.

### Cost

✅ **Tag everything.** Our config auto-tags with `Project`, `Environment`, `ManagedBy`. Cost Explorer can then break down spend by tag.

✅ **Set a budget alert before building.**

✅ **Destroy practice environments daily.**

✅ **Prefer gp3 over gp2** — cheaper *and* faster. There's no reason to use gp2 anymore.

✅ **Prefer Graviton (`t4g`)** — roughly 20% cheaper for the same performance.

✅ **Question every NAT Gateway.** It's usually the largest line item on a small AWS bill.

### Operations

✅ **Use Infrastructure as Code.** Manual console clicking is unrepeatable, undocumented, and unreviewable.

✅ **Read `terraform plan` every single time.** The plan is your last chance to catch a destructive change.

✅ **Store Terraform state remotely** (S3 + DynamoDB lock) once more than one person is involved.

✅ **Enable ALB access logs to S3** when you go to production — you cannot debug traffic you didn't record.

---

## 13. CLI vs Terraform: Pros and Cons

| | AWS CLI scripts | Terraform |
|---|---|---|
| **Learning value** | ⭐⭐⭐⭐⭐ You see each API call | ⭐⭐⭐ Declarative, hides the sequence |
| **Speed to write** | Slow — order and IDs are manual | Fast — references imply order |
| **Repeatable?** | ⚠️ Re-running creates duplicates | ✅ Idempotent by design |
| **Preview changes?** | ❌ None | ✅ `terraform plan` |
| **Teardown** | ❌ 150 lines of ordering and retries | ✅ `terraform destroy` |
| **Drift detection** | ❌ | ✅ Plan shows manual changes |
| **Extra tool needed?** | ✅ CLI only | ❌ Install Terraform |
| **Good for** | Learning, one-off queries, glue scripts | Real infrastructure |

**Honest recommendation:** work through the CLI scripts once so the moving parts are real to you. Then use Terraform for everything afterward. The CLI stays useful for *inspecting* things — `describe-target-health` will be in your fingers forever.

**Other options worth knowing:** **CloudFormation** (AWS-native, no extra tool, AWS-only), **AWS CDK** (write infrastructure in TypeScript or Python, compiles to CloudFormation), **Pulumi** (like CDK but multi-cloud), and **OpenTofu** (a fully open-source fork of Terraform, drop-in compatible — every `.tf` file here works with it unchanged).

---

## 14. Cleaning Up

**Do not skip this.** An idle load balancer costs the same as a busy one.

```bash
# Terraform
cd terraform && terraform destroy

# CLI
cd cli && bash 99-destroy.sh
```

Then verify nothing survived:

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output table
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output table
aws ec2 describe-vpcs --filters Name=tag:Project,Values=web-demo \
  --query 'Vpcs[].VpcId' --output text
aws ec2 describe-addresses --query 'Addresses[?AssociationId==`null`].PublicIp' --output table
```

All empty means you're clean. Check the Billing console in 24 hours to be certain.

**Why teardown order matters:** AWS refuses to delete anything another resource depends on. Delete inside-out:

```
DNS record -> listener -> load balancer -> target group -> instances ->
security groups -> route tables -> subnets -> internet gateway -> VPC
```

Get it wrong and you get `DependencyViolation`. The security groups are the sneakiest part: ours reference *each other*, so the cross-references must be revoked before either can be deleted. Terraform works all of this out on its own.

---

## 15. Where to Go Next

**Immediate next steps, roughly in order of value:**

1. **Add HTTPS** with a free ACM certificate — the single biggest real-world improvement.
2. **Add an Auto Scaling Group** so failed servers replace themselves.
3. **Add CloudFront** for global speed and free DDoS protection.
4. **Turn on ALB access logs** to S3.
5. **Add CloudWatch alarms** on `UnHealthyHostCount` and `TargetResponseTime`.
6. **Move Terraform state to S3** with DynamoDB locking.
7. **Replace EC2 with ECS Fargate** — containers, no servers to patch.
8. **Add a WAF** if you're handling anything sensitive.

**Concepts worth studying next:** VPC Peering and Transit Gateway (connecting networks), PrivateLink (private access to services), Auto Scaling policies, blue/green deployments with weighted target groups, and IAM roles in real depth.

**Official documentation:**

- [VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/)
- [Application Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS Pricing Calculator](https://calculator.aws/)

---

## The Five Ideas to Remember

If you forget everything else:

1. **A subnet is "public" only because its route table sends `0.0.0.0/0` to an Internet Gateway.** Nothing else makes it public.
2. **A load balancer needs four things to work:** the ALB, a target group, *registered* targets, and a listener. Miss any one and you get silence or a 503.
3. **The health check is a password, and the password is `200`.** A server that returns anything else is treated as dead.
4. **Reference security groups, not IP addresses.** `--source-group` is the most valuable habit in AWS networking.
5. **Destroy what you build.** An idle load balancer costs $16/month forever.

---

*Built for learning. Every file in this project is commented line by line — open them and read along.*
