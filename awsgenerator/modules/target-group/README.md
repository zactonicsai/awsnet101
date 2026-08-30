# Module: `target-group`

A target group and its health check policy. **Deliberately does not register targets.**

## Why registration is excluded

Registration belongs to whoever owns the compute:

- An **ASG** registers itself via `target_group_arns` — pass this module's output
- **One-off instances** use `aws_lb_target_group_attachment` in your root module
- **Lambda** uses `aws_lambda_permission` plus an attachment

Keeping registration out is what lets one module serve ASGs, containers, Lambda, and static instances alike.

## Usage

```hcl
module "app_tg" {
  source = "../../modules/target-group"

  name   = "app"                    # max 6 chars used; auto-truncated
  vpc_id = module.network.vpc_id
  port   = 8080

  health_check_path    = "/healthz"
  health_check_matcher = "200"
}

module "app_asg" {
  source            = "../../modules/asg"
  target_group_arns = [module.app_tg.target_group_arn]   # the link
}
```

### Registering a static instance

```hcl
resource "aws_lb_target_group_attachment" "one_off" {
  target_group_arn = module.app_tg.target_group_arn
  target_id        = aws_instance.legacy.id
  port             = 8080
}
```

## The health check is a password, and the password is 200

Every 30 seconds the load balancer requests `health_check_path`. A `200` keeps the target in rotation; two consecutive failures remove it. A server returning 404 or 500 is treated as **dead** even while running perfectly.

| Input | Default | Notes |
|---|---|---|
| `health_check_path` | `/` | Point at something that verifies real dependencies |
| `health_check_matcher` | `200` | `200-299` is more forgiving |
| `health_check_interval` | `30` | Seconds between checks |
| `health_check_timeout` | `5` | Must be **less than** interval |
| `healthy_threshold` | `2` | Passes before traffic resumes |
| `unhealthy_threshold` | `2` | Failures before traffic stops |

> A check hitting a static page passes even when your database is down. A good health endpoint verifies the dependencies the app actually needs.

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `vpc_id` | string | — | **Injected.** Must match the targets' VPC |
| `port` | number | `80` | Need not match the listener port |
| `target_type` | string | `instance` | `instance` / `ip` / `lambda` / `alb` |
| `deregistration_delay` | number | `30` | AWS default 300 makes destroys feel frozen |
| `stickiness_enabled` | bool | `false` | Only for in-memory session state |
| `slow_start_duration` | number | `0` | 30–900s ramp for JIT-warming apps |

## Gotchas

- **`name_prefix` caps at 6 characters** for target groups (32 for the full name). The module truncates and strips invalid characters automatically rather than failing at apply.
- **Lambda target groups must omit port, protocol, and vpc_id.** Handled conditionally.
- **`create_before_destroy` is required** because a target group referenced by a listener cannot be deleted.
- **Port translation is normal.** Public on 80, targets on 8080. Your app then never needs root to bind a low port.
