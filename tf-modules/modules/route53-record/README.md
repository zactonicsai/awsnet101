# Module: `route53-record`

DNS records inside a hosted zone you already own. **Does not create hosted zones.**

## Why zones are excluded

Creating a hosted zone assigns four random nameservers you must copy to your registrar by hand. If automation ever destroys and recreates that zone, you get four **different** nameservers and your domain stops resolving until someone updates the registrar again.

Create zones once, manually. Automate only the records inside them.

```hcl
data "aws_route53_zone" "main" {
  name         = "example.com"
  private_zone = false
}
```

## Usage

```hcl
module "dns" {
  source  = "../../modules/route53-record"
  zone_id = data.aws_route53_zone.main.zone_id

  records = {
    app = {
      name          = "app.example.com"
      type          = "A"
      alias_name    = module.alb.alb_dns_name
      alias_zone_id = module.alb.alb_zone_id     # the LB's zone, not yours
    }
    root = {
      name          = "example.com"             # ALIAS is legal at the root
      type          = "A"
      alias_name    = module.alb.alb_dns_name
      alias_zone_id = module.alb.alb_zone_id
    }
    spf = {
      name   = "example.com"
      type   = "TXT"
      ttl    = 300
      values = ["v=spf1 include:_spf.google.com -all"]
    }
  }
}
```

## ALIAS vs CNAME vs A

| | A record | CNAME | **ALIAS** |
|---|---|---|---|
| Points at | An IP | Another name | An AWS resource |
| Works for a load balancer? | No — IPs change | Yes, but | **Yes** |
| Legal at the zone root? | Yes | **No — forbidden** | **Yes** |
| Query cost | $0.40/M | $0.40/M | **Free** |
| Follows IP changes? | No | Yes | **Yes** |

A load balancer has no fixed IP, so an A record is impossible. A CNAME works for a subdomain but is illegal at the root. **For any AWS resource, prefer ALIAS.**

## Key inputs

| Name | Type | Notes |
|---|---|---|
| `zone_id` | string | **Injected** |
| `records` | map(object) | Keyed by stable name |

Each record is **either** standard (`values` + `ttl`) **or** alias (`alias_name` + `alias_zone_id`). Validation blocks enforce exactly one.

## Gotchas

- **`alias_zone_id` is the TARGET's zone**, not your domain's. Every ALB lives in a hidden AWS zone and exposes the ID as `alb_zone_id`. Passing your own is the most common Route 53 mistake.
- **TTL and `values` are illegal alongside an alias block.** Handled conditionally.
- **`allow_overwrite = false` by default.** Set true when adopting a record that already exists, or apply fails with a conflict.
- **DNS propagation is not instant.** Your resolver may cache an old answer for minutes.
