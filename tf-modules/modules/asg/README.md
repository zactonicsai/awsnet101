# Module: `asg`

An Auto Scaling Group that launches instances from an existing launch template into existing subnets and registers them into existing target groups.

## Why an ASG instead of plain instances

1. **Self-healing** — a failed instance is replaced with no human involved
2. **Automatic target registration** — no more forgotten `register-targets`, the single most common cause of a mystery 503
3. **Zero-downtime deploys** — instance refresh rolls the fleet gradually
4. **Elasticity** — optional policies add and remove capacity with demand

## Usage

```hcl
module "app_asg" {
  source = "../../modules/asg"
  name   = "my-app"

  launch_template_id      = module.app_lt.launch_template_id
  launch_template_version = module.app_lt.latest_version   # visible diffs

  subnet_ids        = module.network.private_subnet_ids    # PRIVATE
  target_group_arns = [module.app_tg.target_group_arn]     # the LB link

  min_size         = 2
  max_size         = 6
  desired_capacity = 2

  health_check_type       = "ELB"
  enable_instance_refresh = true
}
```

### With autoscaling

```hcl
module "app_asg" {
  # ...
  desired_capacity = null          # let the autoscaler own it

  enable_target_tracking = true
  target_tracking_metric = "cpu"
  target_tracking_value  = 60      # hold average CPU near 60%
}
```

Or scale on load balancer traffic:

```hcl
  target_tracking_metric  = "alb_requests"
  target_tracking_value   = 1000   # requests per instance
  alb_arn_suffix          = module.alb.arn_suffix
  target_group_arn_suffix = module.app_tg.arn_suffix
```

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `launch_template_id` | string | — | **Injected** |
| `launch_template_version` | string | `$Latest` | Pass `latest_version` for visible diffs |
| `subnet_ids` | list(string) | — | **Injected.** Private, 2+ AZs |
| `target_group_arns` | list(string) | `[]` | **Injected.** The load balancer link |
| `health_check_type` | string | `ELB` | See below |
| `health_check_grace_period` | number | `300` | Seconds before checks count |
| `enable_instance_refresh` | bool | `true` | Rolling deploys |
| `enable_target_tracking` | bool | `false` | Autoscaling |

## `EC2` vs `ELB` health checks

| | Replaces on |
|---|---|
| `EC2` | Hypervisor-level VM failure only |
| `ELB` | **Also** load balancer health check failure |

Use `ELB` whenever target groups are attached. With `EC2`, an instance whose *application* crashed stays in service forever — the VM is healthy, so the ASG sees no problem, while the load balancer refuses to send it traffic.

## Gotchas

- **`desired_capacity` is in `ignore_changes`.** Otherwise every `terraform apply` would drag the fleet back to the number in your code and undo autoscaling. To change it deliberately, edit the value and use the console/CLI, or remove the lifecycle rule.
- **Grace period too short = infinite replacement loop.** Instances get killed mid-bootstrap, replaced, killed again. If your user data takes 4 minutes, set at least 300.
- **`min_healthy_percentage = 100` needs headroom.** The refresh must add an instance before removing one, so `max_size` must exceed `desired_capacity`.
- **`min_elb_capacity` makes apply wait** for real health, so a successful apply means a working site, not just a created ASG.
