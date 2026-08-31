# Load Balancer + One EC2 Instance, Built with Terraform

A small, complete Terraform project. It builds an Application Load Balancer that
sends web traffic to a single `t3.micro` EC2 instance running Apache.

The project is split into two reusable modules plus a root configuration that
wires them together:

```
alb-ec2-terraform/
├── main.tf                     # calls both modules, creates IAM + the instance
├── variables.tf                # every input you can set
├── outputs.tf                  # what you get back (the ALB URL, etc.)
├── providers.tf                # AWS provider + optional S3 backend
├── terraform.tfvars.example    # copy to terraform.tfvars and edit
└── modules/
    ├── alb/                    # module 1: load balancer + target group + listener
    └── launch_template/        # module 2: launch template + Apache user data
```

---

## Part 1 — Step by step: get it running

### Before you start

You need four things that already exist in AWS. This project does **not** create
them, because in most companies the networking team owns them:

| Thing | What it is | Example |
|---|---|---|
| A VPC | Your private network inside AWS | `vpc-0123456789abcdef0` |
| Two public subnets | Two "rooms" in that network, in two different Availability Zones | `subnet-0aaa…`, `subnet-0bbb…` |
| An ALB security group | Firewall rule allowing port 80 in from the internet | `sg-0aaa…` |
| An instance security group | Firewall rule allowing port 80 in **from the ALB security group** | `sg-0bbb…` |

You also need Terraform 1.5 or newer and AWS credentials on your machine.

Check both:

```bash
terraform version
aws sts get-caller-identity
```

If the second command prints your account number, your credentials work.

### Step 1 — Get the files

Unzip the project and move into the folder:

```bash
unzip alb-ec2-terraform.zip
cd alb-ec2-terraform
```

### Step 2 — Make your variables file

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` in an editor and replace the fake IDs with your real
ones. The four required values are `vpc_id`, `alb_subnet_ids`,
`instance_subnet_id`, `alb_security_group_ids`, and
`instance_security_group_ids`. Everything else already has a sensible default.

### Step 3 — Initialize

```bash
terraform init
```

This downloads the AWS provider and links up the two local modules. Run it again
any time you add a new module or change the provider version.

### Step 4 — Check the formatting and the syntax

```bash
terraform fmt -recursive
terraform validate
```

`fmt` tidies the spacing. `validate` catches typos before AWS ever sees them.

### Step 5 — See the plan

```bash
terraform plan
```

Terraform prints a list of what it would create. Nothing has been built yet.
Read it. You should see roughly a dozen resources: a load balancer, a target
group, a listener, a launch template, an IAM role, an instance profile, an EC2
instance, and a target group attachment.

### Step 6 — Build it

```bash
terraform apply
```

Type `yes` when it asks. This takes about three minutes, mostly waiting on the
load balancer.

### Step 7 — Visit the site

When the apply finishes, Terraform prints the outputs:

```
alb_url = "http://demo-dev-1234567890.us-east-1.elb.amazonaws.com:80"
```

Open that URL. The first two or three tries may return `503 Service Unavailable`
— that is normal. The ALB will not send traffic to the instance until the health
check has passed twice in a row, which takes about a minute after boot. Wait,
refresh, and you should see the demo page with the instance ID on it.

### Step 8 — Clean up

Leaving this running costs money (an ALB is roughly $16–20 a month even with no
traffic). When you are finished:

```bash
terraform destroy
```

---

## Part 2 — Background: what each piece actually is

**Terraform** reads `.tf` files that describe what you want, compares that to
what already exists, and makes the difference. You describe the end state; it
figures out the API calls.

**Application Load Balancer (ALB)** is a managed AWS service that receives web
requests and forwards them to your servers. It has one stable DNS name, so
clients never need to know your servers' IP addresses. It works at layer 7,
meaning it understands HTTP and can route on hostname or URL path.

**Target group** is the list of servers the ALB forwards to, plus the health
check rules. The ALB itself does not know about instances — it knows about
target groups, and target groups know about instances.

**Listener** is the rule that says "traffic arriving on port 80 goes to this
target group."

**Launch template** is a saved recipe for an EC2 instance: which AMI, which size,
which security groups, which IAM role, and what script to run on first boot. It
does not launch anything by itself. You point an instance or an Auto Scaling
group at it. Keeping this recipe separate is what lets you go from one instance
to fifty later without rewriting anything.

**User data** is a shell script AWS runs as root the first time an instance
boots. Ours installs Apache and writes an `index.html`.

**IAM role and instance profile** give the instance permission to call AWS APIs
without storing access keys on disk. The role holds the permissions; the
instance profile is the wrapper that lets an EC2 instance wear the role.

### How the traffic flows

```
Internet
   │  port 80
   ▼
ALB (in alb_subnet_ids, guarded by alb_security_group_ids)
   │  forwards via listener
   ▼
Target group  ──health checks──►  GET /health
   │
   ▼
EC2 instance (in instance_subnet_id, guarded by instance_security_group_ids)
   running Apache, installed by launch template user data
```

The single most common reason this setup fails is the instance security group.
It must allow inbound traffic **from the ALB's security group**, not from
`0.0.0.0/0` and not from a CIDR block. In the console that is a rule with source
type "Custom" and the ALB security group ID as the value.

---

## Part 3 — Variables, `vars`, and `tfvars` explained

This trips up almost everyone at first, so here it is in full.

### `variables.tf` declares. `terraform.tfvars` supplies.

`variables.tf` is the **form**: it lists what questions exist, what type each
answer must be, and what the default answer is if you say nothing.

```hcl
variable "instance_type" {
  description = "EC2 size."
  type        = string
  default     = "t3.micro"
}
```

`terraform.tfvars` is the **filled-in form**: it gives actual values.

```hcl
instance_type = "t3.small"
```

A variable with no `default` is required — Terraform will stop and prompt you if
you never supply it. In this project `vpc_id`, `alb_subnet_ids`,
`instance_subnet_id`, `alb_security_group_ids`, and
`instance_security_group_ids` are required. Everything else is optional.

### Where values can come from, weakest to strongest

Later entries win over earlier ones:

1. The `default` in `variables.tf`
2. `terraform.tfvars` and `*.auto.tfvars` (loaded automatically)
3. A file named on the command line: `-var-file="prod.tfvars"`
4. A single value on the command line: `-var="instance_type=t3.small"`
5. An environment variable: `export TF_VAR_instance_type=t3.small`

That last form is how you pass secrets in CI without writing them to a file.
Note the `TF_VAR_` prefix and that the rest of the name is lowercase, matching
the variable name exactly.

### Using one project for several environments

Make one tfvars file per environment and pick at apply time:

```bash
terraform apply -var-file="dev.tfvars"
terraform apply -var-file="prod.tfvars"
```

`dev.tfvars` might set `instance_type = "t3.micro"` while `prod.tfvars` sets
`t3.large` and a different VPC. Same code, different inputs.

Files ending in `.auto.tfvars` load automatically, like `terraform.tfvars` does.
Files with any other name must be named with `-var-file`.

### How the root passes values into the modules

Inside `main.tf`, a `module` block sets the module's variables by name:

```hcl
module "alb" {
  source = "./modules/alb"

  name               = local.name              # from a local expression
  vpc_id             = var.vpc_id              # straight from your tfvars
  subnet_ids         = var.alb_subnet_ids      # straight from your tfvars
  security_group_ids = var.alb_security_group_ids
  target_port        = var.app_port
}
```

So a value travels: `terraform.tfvars` → root `var.*` → module input → resource
argument. Modules cannot read the root's variables directly; everything must be
handed over explicitly. That is a feature, not an annoyance — it is what makes a
module reusable.

Values come back out through `output` blocks:

```hcl
target_group_arn = module.alb.target_group_arn
```

That line in `main.tf` is what connects the two modules together: the target
group made by the ALB module becomes the destination for the instance built from
the launch template module.

### The `locals` block

```hcl
locals {
  name   = "${var.project_name}-${var.environment}"   # "demo-dev"
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
}
```

A local is a calculated value, not an input. You cannot set it from a tfvars
file. Use locals for things derived from variables, like a naming convention or
an "if the user left this blank, look it up instead" fallback.

---

## Part 4 — The full variable reference

### Required

| Variable | Type | What it is |
|---|---|---|
| `vpc_id` | string | VPC that holds everything |
| `alb_subnet_ids` | list(string) | Two or more subnets in different AZs for the ALB |
| `instance_subnet_id` | string | Subnet for the one EC2 instance |
| `alb_security_group_ids` | list(string) | Firewall for the ALB |
| `instance_security_group_ids` | list(string) | Firewall for the instance |

### Optional

| Variable | Default | What it is |
|---|---|---|
| `aws_region` | `us-east-1` | Region to deploy into |
| `project_name` | `demo` | Name prefix for resources |
| `environment` | `dev` | Second half of the name prefix |
| `instance_type` | `t3.micro` | EC2 size |
| `ami_id` | `""` | Empty means look up newest Amazon Linux 2023 |
| `key_name` | `""` | SSH key pair name; empty means no SSH |
| `listener_port` | `80` | Port the ALB accepts traffic on |
| `app_port` | `80` | Port Apache listens on |
| `health_check_path` | `/health` | Path the health check requests |
| `create_instance_profile` | `true` | Whether to build the IAM role |
| `instance_managed_policy_arns` | `["…AmazonSSMManagedInstanceCore"]` | Policies attached to the role |
| `instance_inline_policy_json` | `""` | Extra inline policy as a JSON string |
| `tags` | `{}` | Tags applied to everything |

### Adding permissions to the instance

To let the instance read one S3 bucket, add this to `terraform.tfvars`:

```hcl
instance_inline_policy_json = <<-JSON
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:ListBucket"],
        "Resource": [
          "arn:aws:s3:::my-bucket",
          "arn:aws:s3:::my-bucket/*"
        ]
      }
    ]
  }
JSON
```

Or attach a managed policy by ARN:

```hcl
instance_managed_policy_arns = [
  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
]
```

---

## Part 5 — Best practices used here, and the trade-offs

**IMDSv2 is required.** The launch template sets `http_tokens = "required"`. The
old metadata service could be tricked by a server-side request forgery bug into
handing out credentials. IMDSv2 requires a token first, which closes that hole.
Downside: very old SDKs and hand-written `curl` scripts that don't request a
token will break. Fix the script, don't turn this off.

**Root volume is encrypted.** Costs nothing, prevents an audit finding.

**No SSH key by default.** `AmazonSSMManagedInstanceCore` lets you connect with
`aws ssm start-session --target i-0abc…` instead. No port 22 open, no key file to
lose, and every session is logged. Downside: the instance needs a route to the
SSM endpoints (a NAT gateway, an internet gateway, or VPC endpoints), so in a
fully isolated subnet you will need those endpoints.

**`create_before_destroy` on the launch template and target group.** Both have
names that must be unique. Without this, replacing one fails because Terraform
tries to create the new one before releasing the old name.

**Subnets, security groups, and the VPC are inputs, not resources.** Modules that
create their own networking are hard to drop into an existing account. Passing
them in means this project works whether your VPC came from Terraform, from
CloudFormation, or from someone clicking around in 2019.

**Names are built from `project_name` and `environment`.** Two deploys of the
same code into the same account will not collide as long as the environment
differs.

### Choices worth knowing about

**One `aws_instance` vs. an Auto Scaling group.** This project creates one
instance and attaches it to the target group directly, which is simple and easy
to read — the right call for a demo or a single-server internal tool. An Auto
Scaling group would replace the instance automatically when it fails and let you
scale out, at the cost of more moving parts. Because the launch template is
already its own module, switching later means swapping `aws_instance` and
`aws_lb_target_group_attachment` for one `aws_autoscaling_group` block that
references `module.launch_template.launch_template_id` and
`module.alb.target_group_arn`. Nothing inside the modules changes.

**HTTP vs. HTTPS.** This listens on plain HTTP, which keeps the example short
and needs no certificate. Anything real should use an ACM certificate on a 443
listener and redirect 80 to 443. That requires owning a domain name, which is
why it is not the default here.

**Version pinned to `~> 5.0`.** You get bug fixes and new features within
version 5 but not the breaking changes in 6.x. Loose pins mean surprise
diffs; overly tight pins mean you never get fixes. A commited `.terraform.lock.hcl`
is what actually guarantees repeatable runs.

**Local state vs. S3 backend.** State is on your laptop by default, which is fine
for learning and wrong for a team — two people applying at once will corrupt each
other's work. The commented backend block in `providers.tf` moves state to S3
with `use_lockfile = true`, which is the current way to lock state (the old
DynamoDB lock table is no longer needed).

---

## Part 6 — Troubleshooting

| Symptom | Likely cause |
|---|---|
| `503 Service Unavailable` forever | Instance security group does not allow `app_port` from the ALB security group |
| Target stuck in `unhealthy` | Apache failed to start, or `health_check_path` doesn't exist. Check `sudo cat /var/log/cloud-init-output.log` on the instance |
| `at least two subnets in different AZs` | Both subnets in `alb_subnet_ids` are in the same AZ |
| Site loads but shows the Apache test page | `index.html` was not written; check cloud-init output |
| `InvalidGroup.NotFound` | A security group ID belongs to a different VPC than `vpc_id` |
| Page never changes after editing user data | User data runs only on **first** boot. Run `terraform taint aws_instance.web` then apply, to get a fresh instance |

To read the boot log:

```bash
aws ssm start-session --target $(terraform output -raw instance_id)
sudo cat /var/log/cloud-init-output.log
```

---

## Module documentation

- [`modules/alb/README.md`](modules/alb/README.md)
- [`modules/launch_template/README.md`](modules/launch_template/README.md)
