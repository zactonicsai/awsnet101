# Module: `alb`

An Application Load Balancer with HTTP and optional HTTPS listeners, plus arbitrary routing rules. Target groups, security groups, subnets, and certificates are all injected.

## The four pieces a working load balancer needs

| # | Piece | Owned by | Skip it and you get |
|---|---|---|---|
| 1 | Load balancer | **this module** | Nothing receives traffic |
| 2 | Target group | `target-group` module | Nowhere to forward |
| 3 | Registered targets | `asg` module | **503 forever** |
| 4 | Listener | **this module** | **Total silence, no error** |

Miss any one and every component still reports as healthy. This table is worth remembering.

## Usage

```hcl
module "alb" {
  source = "../../modules/alb"

  name               = "my-app-alb"
  internal           = false                              # public
  subnet_ids         = module.network.public_subnet_ids   # 2+ AZs
  security_group_ids = [module.alb_sg.security_group_id]

  default_target_group_arn = module.app_tg.target_group_arn
}
```

### With HTTPS

Supplying a certificate creates a 443 listener and turns port 80 into a redirect:

```hcl
module "alb" {
  # ...
  certificate_arn        = module.cert.certificate_arn
  redirect_http_to_https = true
  ssl_policy             = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}
```

### Path routing and a debug endpoint

```hcl
listener_rules = {
  api = {
    priority         = 10
    path_pattern     = ["/api/*"]
    target_group_arn = module.api_tg.target_group_arn
  }
  ping = {
    priority       = 100
    path_pattern   = ["/ping"]
    fixed_response = { message_body = "pong", status_code = "200" }
  }
}
```

That `/ping` rule is answered by the load balancer itself, touching no server:

| `/ping` | `/` | Conclusion |
|---|---|---|
| 200 | 200 | Everything works |
| 200 | 503 | **Networking is fine.** Instances or health check broken |
| fails | fails | **Instances are irrelevant.** Security group, subnets, routes, or DNS |

Five seconds of testing halves your search space.

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `subnet_ids` | list(string) | — | **Injected.** 2+ required, validated |
| `security_group_ids` | list(string) | — | **Injected** |
| `internal` | bool | `false` | The public/private door switch |
| `default_target_group_arn` | string | `null` | **Injected.** Null serves a fixed response |
| `certificate_arn` | string | `null` | **Injected.** Non-null creates HTTPS |
| `listener_rules` | map(object) | `{}` | Lower priority evaluated first |
| `access_logs_bucket` | string | `null` | Enable in production |
| `enable_deletion_protection` | bool | `false` | Set true in production |

## Key outputs

| Name | Notes |
|---|---|
| `alb_dns_name` | Works without any custom domain |
| `alb_zone_id` | **The LB's hidden zone**, for alias records — not yours |
| `arn_suffix` | For CloudWatch metrics and request-based scaling |
| `url` | Ready-to-open |

## Gotchas

- **Action type strings are hyphenated; block names are underscored.** `type = "fixed-response"` with `fixed_response { }`. This mirrors the AWS API (`FixedResponseConfig`) and catches nearly everyone. Same for `authenticate-oidc`, `authenticate-cognito`, `jwt-validation`. Only `forward` and `redirect` look identical either way.
- **Rules attach to the HTTPS listener when a redirect is active.** Attaching them to the redirecting HTTP listener means they never match. The module handles this via `primary_listener_arn`.
- **`alb_zone_id` is not your domain's zone ID.** The most common Route 53 mistake.
- **Two AZs, always.** Validated up front rather than failing at apply.
- **~$16.20/month whether busy or idle.** Destroy practice environments.
