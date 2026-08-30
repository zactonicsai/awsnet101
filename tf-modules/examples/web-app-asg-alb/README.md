# Example: Web app on an ASG behind an ALB

A complete working stack built entirely from this library's modules.

```
internet -> ALB (public subnets) -> target group -> ASG (private subnets)
```

The instances have **no public IP address at all**. The load balancer is the only thing the internet ever touches.

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Wait ~60 seconds for health checks, then:

```bash
curl -i $(terraform output -raw alb_dns_name | sed 's|^|http://|')
```

You should see `HTTP/1.1 200 OK` and text served from a machine whose only address is `10.0.10.x` — an address that does not exist on the public internet.

## What gets built

| Order | Module | Creates | Cost |
|---|---|---|---|
| 1 | `vpc` | VPC, 2 public + 2 private subnets, IGW, routes, S3 endpoint | $0 |
| 2 | `security-group` ×2 | ALB group and app group, referencing each other | $0 |
| 3 | `iam-instance-profile` | Role with Session Manager access | $0 |
| 4 | `launch-template` | AL2023 recipe + templated bootstrap script | $0 |
| 5 | `target-group` | Health check demanding HTTP 200 | $0 |
| 6 | `alb` | Load balancer, listener, `/ping` debug rule | ~$16.20/mo |
| 7 | `asg` | 2 instances, auto-registered into the target group | ~$7.42/mo |
| 8 | `route53-record` | Optional alias record | $0.50/mo |

**Roughly $24/month if left running. About 5 cents if you destroy it the same day.**

No NAT Gateway is created — the bootstrap script downloads nothing, saving ~$32/month.

## The bootstrap script

`scripts/bootstrap.sh` is rendered by `templatefile()` before it reaches AWS:

```hcl
user_data_template_path = "${path.module}/scripts/bootstrap.sh"
user_data_vars = {
  app_port      = tostring(var.app_port)
  response_text = var.response_text
}
```

`${app_port}` inside the script becomes a real value at plan time. It writes a small Python server (Python 3 ships in Amazon Linux 2023, so nothing is downloaded) and registers it with systemd so it restarts on crash and survives reboots.

## Deploying a change

Edit `scripts/bootstrap.sh`, then:

```bash
terraform apply
```

Because the example passes `launch_template_version = module.app_lt.latest_version`, the change produces a **visible diff**, creates a new template version, and triggers an ASG instance refresh that rolls the fleet with no downtime.

Watch it:

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name $(terraform output -raw asg_name)
```

## Debugging

```bash
# 1. THE command. Any 503 starts here.
eval "$(terraform output -raw check_target_health)"

# 2. Does the load balancer itself answer? (touches no instance)
curl -i "$(terraform output -raw ping_url)"

# 3. What did the instance print while booting?
aws ec2 get-console-output --instance-id i-xxx --output text | tail -50
```

| `/ping` | `/` | Conclusion |
|---|---|---|
| 200 | 200 | Working |
| 200 | 503 | Networking fine — instances or health check broken |
| fails | fails | Security group, subnets, routes, or DNS |

## Using your own VPC

Delete the `module "network"` block and replace its references:

```hcl
module "alb" {
  subnet_ids = ["subnet-0aaa", "subnet-0bbb"]   # your public subnets
}

module "app_asg" {
  subnet_ids = ["subnet-0ccc", "subnet-0ddd"]   # your private subnets
}

module "app_sg" {
  vpc_id = "vpc-0abc123"
}
```

Nothing else changes. That is the whole point of the injection pattern.

## Adding HTTPS

```hcl
data "aws_route53_zone" "main" {
  name = "example.com"
}

module "cert" {
  source         = "../../modules/acm-certificate"
  domain_name    = "app.example.com"
  hosted_zone_id = data.aws_route53_zone.main.zone_id
}

module "alb" {
  # ...
  certificate_arn = module.cert.certificate_arn
}
```

Then add port 443 to `module.alb_sg`'s ingress rules. The certificate is free and renews itself.

## Clean up

```bash
terraform destroy
```
