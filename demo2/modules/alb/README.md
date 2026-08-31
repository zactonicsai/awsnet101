# Module: `alb`

Creates an Application Load Balancer, one HTTP target group, and one HTTP
listener that forwards to it.

The module deliberately does **not** create a VPC, subnets, or security groups.
You pass those in, so the module works in any existing account.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_lb` | The load balancer itself |
| `aws_lb_target_group` | The pool of instances, plus health check settings |
| `aws_lb_listener` | Rule sending port 80 traffic to the target group |

## Usage

Minimum:

```hcl
module "alb" {
  source = "./modules/alb"

  name               = "demo-dev"
  vpc_id             = var.vpc_id
  subnet_ids         = var.alb_subnet_ids
  security_group_ids = var.alb_security_group_ids
}
```

With the common options set:

```hcl
module "alb" {
  source = "./modules/alb"

  name               = "demo-dev"
  vpc_id             = "vpc-0123456789abcdef0"
  subnet_ids         = ["subnet-0aaa…", "subnet-0bbb…"]
  security_group_ids = ["sg-0aaa…"]

  listener_port        = 80
  target_port          = 8080
  health_check_path    = "/health"
  health_check_matcher = "200-299"
  internal             = false

  tags = {
    Project   = "demo"
    ManagedBy = "terraform"
  }
}
```

Attach an instance to the target group from the calling configuration:

```hcl
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = module.alb.target_group_arn
  target_id        = aws_instance.web.id
  port             = 8080
}
```

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|:---:|---|
| `name` | string | — | yes | Base name. Keep to 28 characters or fewer; `-tg` is appended for the target group |
| `vpc_id` | string | — | yes | VPC for the target group |
| `subnet_ids` | list(string) | — | yes | At least two subnets, in different AZs |
| `security_group_ids` | list(string) | — | yes | Security groups for the ALB |
| `internal` | bool | `false` | no | `true` for a private ALB |
| `listener_port` | number | `80` | no | Port clients connect to |
| `target_port` | number | `80` | no | Port on the instances |
| `health_check_path` | string | `"/"` | no | Path requested by the health check |
| `health_check_matcher` | string | `"200"` | no | Status codes counted as healthy |
| `health_check_interval` | number | `30` | no | Seconds between checks |
| `health_check_timeout` | number | `5` | no | Seconds before a check is a failure |
| `healthy_threshold` | number | `2` | no | Passes needed to become healthy |
| `unhealthy_threshold` | number | `2` | no | Failures needed to become unhealthy |
| `deregistration_delay` | number | `60` | no | Drain time before removing a target |
| `idle_timeout` | number | `60` | no | Idle connection timeout |
| `enable_deletion_protection` | bool | `false` | no | Blocks `terraform destroy` when true |
| `tags` | map(string) | `{}` | no | Tags for all resources here |

## Outputs

| Name | Description |
|---|---|
| `alb_arn` | ARN of the load balancer |
| `alb_dns_name` | Public DNS name — open this in a browser |
| `alb_zone_id` | Hosted zone ID, for Route 53 alias records |
| `target_group_arn` | Pass this to an attachment or an Auto Scaling group |
| `target_group_name` | Name of the target group |
| `listener_arn` | ARN of the HTTP listener |

## Notes

- An ALB needs subnets in **two or more Availability Zones**. A `validation`
  block enforces the count, but Terraform cannot check the AZs — AWS will reject
  the apply if both subnets share an AZ.
- The ALB security group must allow inbound on `listener_port`. The instance
  security group must allow inbound on `target_port` **from the ALB security
  group**.
- `target_type` is `instance`. For containers on Fargate or for IP targets you
  would need `ip` instead; that is out of scope for this module.
- Adding HTTPS means creating an ACM certificate and a second
  `aws_lb_listener` on port 443 with `certificate_arn` set. This module does not
  do that, on purpose, since it would require you to own a domain.
