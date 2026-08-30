# Reusable AWS Terraform Modules

A library of composable Terraform modules for core AWS services. Every module **accepts existing resources as inputs** rather than creating its own dependencies, so any of them can drop into any project.

---

## The design rule

> **A module creates one thing. Everything it depends on is passed in.**

This is dependency injection applied to infrastructure. The `alb` module does not create a VPC, subnets, security groups, or target groups — it takes their IDs. That single discipline is what makes these reusable.

```hcl
# Works with the vpc module in this library...
module "alb" {
  source     = "./modules/alb"
  subnet_ids = module.network.public_subnet_ids
}

# ...and works identically with a VPC someone else built in 2019
module "alb" {
  source     = "./modules/alb"
  subnet_ids = ["subnet-0abc123", "subnet-0def456"]
}
```

Three rules follow from it:

1. **No `provider` blocks in child modules.** Only the root module configures providers. A module that configures its own cannot be used across regions or accounts, and cannot be called by another module.
2. **No hard-coded names, regions, or account IDs.** Everything is a variable.
3. **Outputs expose what other modules need.** If module B needs a value from module A, A outputs it explicitly.

---

## Modules

| Module | Creates | Injected dependencies |
|---|---|---|
| [`vpc`](modules/vpc) | VPC, subnets, IGW, routes, optional NAT | *(none — the bootstrap module)* |
| [`security-group`](modules/security-group) | Security group + rules | `vpc_id`, other SG IDs |
| [`iam-instance-profile`](modules/iam-instance-profile) | IAM role + instance profile | policy ARNs/JSON |
| [`launch-template`](modules/launch-template) | Launch template + user data | SG IDs, profile name, AMI |
| [`asg`](modules/asg) | Auto Scaling Group + scaling policy | launch template, subnets, target groups |
| [`target-group`](modules/target-group) | Target group + health check | `vpc_id` |
| [`alb`](modules/alb) | Load balancer + listeners + rules | subnets, SGs, target groups, certificate |
| [`acm-certificate`](modules/acm-certificate) | TLS certificate + DNS validation | `hosted_zone_id` |
| [`route53-record`](modules/route53-record) | DNS records | `zone_id`, alias targets |
| [`s3-bucket`](modules/s3-bucket) | Bucket + encryption + lifecycle | KMS key (optional) |
| [`rds`](modules/rds) | Database + subnet group | subnets, SGs |
| [`network-acl`](modules/network-acl) | Subnet firewall, ingress + egress | `vpc_id`, subnets |
| [`secrets-manager`](modules/secrets-manager) | Secret + generated password | KMS key (optional) |
| [`vpc-endpoints`](modules/vpc-endpoints) | Gateway + interface endpoints | `vpc_id`, subnets, SGs, route tables |
| [`kms-key`](modules/kms-key) | Customer-managed key + alias | role ARNs, service principals |

Each has its own README with usage examples, an input reference, and a gotchas section.

### Why `vpc` is the exception

Something has to create network primitives. If you already have a VPC, **skip that module entirely** and pass your own IDs to the rest.

---

## Examples

| Example | What it shows | Cost |
|---|---|---|
| [`web-app-asg-alb`](examples/web-app-asg-alb) | The minimal shape: ALB -> ASG in private subnets. No NAT | ~$24/mo |
| [`keycloak-rds-postgres`](examples/keycloak-rds-postgres) | Docker via user data, firewalld, RDS Postgres, Secrets Manager, NACLs | ~$76/mo |

## Quick start

```bash
cd examples/web-app-asg-alb
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform plan      # always read this
terraform apply

terraform output website_url
```

The example builds a complete stack: internet → ALB in public subnets → target group → ASG in private subnets, with instances that have no public IP at all.

Tear down with `terraform destroy` — an idle ALB costs ~$16/month whether or not anyone visits.

---

## How they compose

```
                      route53-record
                            |  alias
                            v
  acm-certificate ----> [  alb  ] <---- security-group (public)
                            |                   |
                            | default_action    | egress to
                            v                   v
                     [ target-group ]    security-group (app)
                            ^                   ^
                            | target_group_arns |
                            |                   | vpc_security_group_ids
                       [   asg   ] -----> [ launch-template ]
                            |                   |
                            | subnet_ids        | iam_instance_profile_name
                            v                   v
                       [   vpc   ]     iam-instance-profile
```

Every arrow is an explicit input. Terraform derives the creation order from these references — you never write `depends_on` for any of it.

---

## Using a module in your own project

Modules can be sourced from a local path, a Git repository, or a registry:

```hcl
# Local
module "app_sg" {
  source = "./modules/security-group"
}

# Git, pinned to a tag — best practice for shared libraries
module "app_sg" {
  source = "git::https://github.com/yourorg/tf-modules.git//modules/security-group?ref=v1.2.0"
}
```

**Always pin a version** on shared modules. An unpinned `source` means someone else's commit can change your infrastructure on your next `apply`.

---

## Conventions used throughout

| Convention | Reason |
|---|---|
| `name_prefix` over `name` | AWS cannot rename most resources in place; a fixed name plus `create_before_destroy` deadlocks |
| `create_before_destroy` on attached resources | Build the replacement before removing the original |
| `for_each` over `count` for collections | Reordering a list with `count` destroys and recreates unrelated resources |
| Rules as separate resources | Individually addressable, one line per change in `plan` |
| `validation` blocks on inputs | Fail at plan time with a clear message, not at apply with an AWS error |
| Every variable has a `description` | It is the module's real documentation |
| Encryption on by default | Free on EBS, S3, and RDS. No reason to opt in |
| Tags on everything | Cost Explorer can only break down what is tagged |

---

## Cost notes

The expensive items, so nothing surprises you:

| Resource | Cost | Notes |
|---|---|---|
| VPC, subnets, IGW, routes, security groups | **$0** | Always free |
| **NAT Gateway** | **~$32/mo each** | Usually the biggest line item. Off by default |
| **Application Load Balancer** | **~$16.20/mo** | Bills the same idle or busy |
| EC2 `t4g.nano` | ~$3.07/mo | ARM, cheapest current generation |
| EBS gp3 8 GB | ~$0.64/mo | Cheaper *and* faster than gp2 |
| RDS `db.t4g.micro` | ~$12/mo | Doubles with `multi_az` |
| Route 53 hosted zone | $0.50/mo | Alias queries are free |
| **S3 Gateway Endpoint** | **$0** | Often removes the need for NAT |
| ACM certificate | **$0** | With ALB or CloudFront |
| Interface VPC endpoint | ~$7.20/mo **each, per AZ** | Adds up faster than NAT — do the arithmetic |
| Secrets Manager secret | $0.40/mo | Plus $0.05 per 10k calls |
| Customer-managed KMS key | $1.00/mo | The AWS-managed key is free and usually enough |

Before building anything, set a budget alert: Billing → Budgets → zero-spend or $5 monthly.

---

## Two firewall layers, and when to use which

| | `security-group` | `network-acl` |
|---|---|---|
| Scope | One resource | A whole subnet |
| State | **Stateful** — replies automatic | **Stateless** — both directions needed |
| Rules | Allow only | Allow **and deny** |
| Order | All together | Numbered, first match wins |
| Use for | **Day-to-day access control** | Defence in depth, coarse blocking |

Reach for security groups first — they reference each other, they are stateful, and they are much harder to get subtly wrong. Add NACLs as a second layer, or when you need an explicit `deny` that a security group cannot express.

## Requirements

- Terraform >= 1.9 (or OpenTofu >= 1.8)
- AWS provider >= 6.0
- Credentials via `aws configure`, an IAM role, or environment variables

## Validating changes

```bash
terraform fmt -recursive -check
terraform validate

cd examples/web-app-asg-alb
terraform init && terraform validate
```
