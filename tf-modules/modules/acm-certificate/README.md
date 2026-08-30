# Module: `acm-certificate`

A free TLS certificate validated automatically through DNS, written into a hosted zone you already own.

## Why always add this

ACM certificates cost **nothing** with a load balancer or CloudFront, and **renew themselves forever** with no human involvement. There is no good reason to run production on plain HTTP.

## Usage

```hcl
data "aws_route53_zone" "main" {
  name         = "example.com"
  private_zone = false
}

module "cert" {
  source = "../../modules/acm-certificate"

  domain_name               = "app.example.com"
  subject_alternative_names = ["www.example.com"]
  hosted_zone_id            = data.aws_route53_zone.main.zone_id
}

module "alb" {
  source          = "../../modules/alb"
  certificate_arn = module.cert.certificate_arn   # waits for ISSUED
}
```

### Wildcard

```hcl
domain_name               = "example.com"
subject_alternative_names = ["*.example.com"]
```

Covers `example.com` plus every direct subdomain, but **not** `a.b.example.com` — wildcards match one level only.

### CloudFront needs us-east-1

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "cf_cert" {
  source    = "../../modules/acm-certificate"
  providers = { aws = aws.us_east_1 }
  # ...
}
```

This works because the module declares no provider of its own — the reason child modules must never contain `provider` blocks.

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `domain_name` | string | — | Primary domain |
| `subject_alternative_names` | list(string) | `[]` | Extra domains |
| `hosted_zone_id` | string | — | **Injected.** Where validation records go |
| `validation_method` | string | `DNS` | Always DNS. EMAIL needs a human every renewal |
| `wait_for_validation` | bool | `true` | Keep true |

## Key outputs

| Name | Notes |
|---|---|
| `certificate_arn` | Routed through the validation resource so dependents wait for issuance |
| `validation_record_fqdns` | Must stay in place or renewal silently stops |

## Gotchas

- **Same region as the load balancer.** CloudFront is the exception — us-east-1 only.
- **`certificate_arn` deliberately comes from the validation resource.** Same string, but it forces Terraform to wait; otherwise the listener is created first and fails with a certificate-not-issued error.
- **Validation records must never be deleted.** Renewal fails silently and you find out when the certificate expires.
- **Duplicate validation options are deduplicated.** A cert for `example.com` + `*.example.com` yields two identical records; creating both is an error.
- **You must own the zone.** DNS validation proves control of the domain.
