# Module: `security-group`

A generic security group with rules as data. Creates only the group and its rules — the VPC is injected, and rule sources can reference groups created anywhere.

## The pattern worth copying

Reference **other security groups**, not IP ranges:

```hcl
module "alb_sg" {
  source = "../../modules/security-group"
  name   = "alb"
  vpc_id = var.vpc_id

  ingress_rules = {
    http = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" }
  }
  egress_rules = {
    to_app = {
      from_port                    = 8080
      to_port                      = 8080
      referenced_security_group_id = module.app_sg.security_group_id
    }
  }
}

module "app_sg" {
  source = "../../modules/security-group"
  name   = "app"
  vpc_id = var.vpc_id

  ingress_rules = {
    from_alb = {
      from_port                    = 8080
      to_port                      = 8080
      referenced_security_group_id = module.alb_sg.security_group_id  # not a CIDR
    }
  }
  # No egress at all. Replies still work — security groups are stateful.
}
```

Why this beats `cidr_ipv4 = "10.0.0.0/24"`:

- Load balancer IPs change constantly; a group reference never goes stale
- A rogue instance in the same subnet still cannot connect
- The rule documents its own intent

> The two modules above reference each other. Terraform resolves this fine because the *rules* are separate resources from the *groups* — a genuine benefit of the one-resource-per-rule style.

## Rule sources

Give exactly one per rule. A validation block enforces it.

| Field | Use for |
|---|---|
| `cidr_ipv4` / `cidr_ipv6` | IP ranges |
| `referenced_security_group_id` | **Preferred.** Another tier |
| `prefix_list_id` | AWS-managed lists (e.g. CloudFront) |
| `self = true` | Members of this same group (cluster gossip) |

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `name` | string | — | Used as `name_prefix`; AWS appends a suffix |
| `vpc_id` | string | — | **Injected** |
| `ingress_rules` | map(object) | `{}` | Keyed by name — renaming a key recreates that rule |
| `egress_rules` | map(object) | `{}` | Empty = no outbound at all |
| `allow_all_egress` | bool | `false` | Shortcut for unrestricted outbound |

## Gotchas

- **Map keys are `for_each` keys.** Renaming `http` to `web` destroys and recreates that rule. Choose stable keys.
- **`ip_protocol = "-1"`** (all protocols) must omit ports entirely. `allow_all_egress` handles this.
- **Empty `egress_rules` is often correct.** Stateful means replies work regardless.
- **`description` cannot be changed** without replacing the group. `create_before_destroy` is set for this reason.
