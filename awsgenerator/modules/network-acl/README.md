# Module: `network-acl`

A Network ACL — a firewall at the **subnet** boundary, evaluated before traffic reaches any security group.

## The three differences from a security group

| | Security Group | **Network ACL** |
|---|---|---|
| Scope | One resource | A whole subnet |
| State | **Stateful** — replies automatic | **Stateless** — every direction needs a rule |
| Rules | Allow only | Allow **and deny** |
| Order | All evaluated together | **Numbered, first match wins** |

**Stateless is the one that bites.** A security group remembers it let a request in and permits the reply automatically. A NACL does not. Every conversation needs rules in *both* directions — including the ephemeral high ports replies arrive on.

## Usage

```hcl
module "private_nacl" {
  source = "../../modules/network-acl"

  name       = "app-private"
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  ingress_rules = {
    app      = { rule_number = 100, from_port = 8080, to_port = 8080, cidr_block = "10.0.0.0/16" }
    postgres = { rule_number = 110, from_port = 5432, to_port = 5432, cidr_block = "10.0.0.0/16" }
  }

  egress_rules = {
    https_out = { rule_number = 100, from_port = 443, to_port = 443, cidr_block = "0.0.0.0/0" }
    postgres  = { rule_number = 110, from_port = 5432, to_port = 5432, cidr_block = "10.0.0.0/16" }
    dns_udp   = { rule_number = 120, protocol = "udp", from_port = 53, to_port = 53, cidr_block = "10.0.0.0/16" }
  }

  # Added automatically. Turn off only if you know exactly what you are doing.
  add_ephemeral_ingress_rule = true
  add_ephemeral_egress_rule  = true
}
```

### Explicitly blocking an abusive range

Something a security group simply cannot do:

```hcl
ingress_rules = {
  block_bad_actor = { rule_number = 10, action = "deny", protocol = "-1", cidr_block = "198.51.100.0/24" }
  allow_http      = { rule_number = 100, from_port = 80, to_port = 80, cidr_block = "0.0.0.0/0" }
}
```

Rule 10 is evaluated first and matches, so that range never reaches rule 100.

## Ephemeral ports — the classic failure

When an instance makes an outbound request, the OS picks a random high source port and the reply returns to **that** port. A stateless NACL sees the reply as brand-new inbound traffic and drops it unless a rule allows it.

**Symptom:** `dnf install` hangs. `curl` hangs. `docker pull` hangs. Nothing errors — it just never finishes, because the request left and the answer was silently discarded.

The module adds TCP 1024–65535 rules in both directions by default (rule 900). Linux uses 32768–60999 and NAT Gateways use 1024–65535, so the wider range covers both.

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `vpc_id` | string | — | **Injected** |
| `subnet_ids` | list(string) | `[]` | **Injected.** Associating REPLACES the subnet's current ACL |
| `ingress_rules` | map(object) | `{}` | `rule_number` sets order |
| `egress_rules` | map(object) | `{}` | **Not optional** — stateless |
| `add_ephemeral_ingress_rule` | bool | `true` | Leave on |
| `ephemeral_rule_number` | number | `900` | High, so explicit rules win |

## Gotchas

- **Leave gaps in rule numbers** (100, 200, 300) so you can insert later without renumbering everything.
- **Rule 32767 is the implicit DENY ALL** and cannot be redefined. Validated.
- **Associating a subnet replaces its ACL.** Get the rules right *before* associating anything you care about — a wrong NACL on a live subnet is an instant outage.
- **`protocol = "-1"` must omit ports.** Handled conditionally.
- **Don't forget DNS.** UDP 53 outbound, or nothing resolves and every symptom looks like something else.
- **Use security groups for day-to-day access control.** NACLs are defence in depth and coarse blocking. They are stateless and far easier to get subtly wrong.
