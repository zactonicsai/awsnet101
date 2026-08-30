# Module: `vpc`

Creates the network foundation: VPC, public and private subnets across multiple AZs, an internet gateway, route tables, and optional NAT gateways, flow logs, and a free S3 endpoint.

## The one exception in this library

Every other module **consumes** existing resources. This one **creates** them, because something has to. If you already have a VPC, **skip this module entirely** and pass your own IDs into the others — they neither know nor care what produced them.

```hcl
module "app_sg" {
  source = "../../modules/security-group"
  vpc_id = "vpc-0abc123"                      # your existing VPC
}

module "alb" {
  source     = "../../modules/alb"
  subnet_ids = ["subnet-0aaa", "subnet-0bbb"] # your existing subnets
}
```

## Usage

```hcl
module "network" {
  source = "../../modules/vpc"

  name       = "my-app"
  cidr_block = "10.0.0.0/16"

  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway         = false  # saves ~$32/month
  enable_s3_gateway_endpoint = true   # free

  tags = { Project = "my-app" }
}
```

### Private-only network (no internet at all)

```hcl
module "isolated" {
  source               = "../../modules/vpc"
  name                 = "isolated"
  cidr_block           = "10.1.0.0/16"
  private_subnet_cidrs = ["10.1.0.0/24", "10.1.1.0/24"]
  # No public_subnet_cidrs -> no internet gateway is created
}
```

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `name` | string | — | Prefix for every resource |
| `cidr_block` | string | — | Hard to change later; be generous |
| `availability_zones` | list(string) | `[]` | Empty = auto-select. Pin explicitly in production |
| `public_subnet_cidrs` | list(string) | `[]` | Empty disables public subnets and the IGW |
| `private_subnet_cidrs` | list(string) | `[]` | Empty disables private subnets |
| `enable_nat_gateway` | bool | `false` | **~$32/mo each.** Usually your biggest line item |
| `single_nat_gateway` | bool | `true` | One shared NAT vs one per AZ |
| `enable_s3_gateway_endpoint` | bool | `true` | Free. Often removes the need for NAT |
| `enable_flow_logs` | bool | `false` | CloudWatch ingestion costs apply |

## Key outputs

| Name | Feeds into |
|---|---|
| `vpc_id` | `security-group`, `target-group`, `rds` |
| `public_subnet_ids` | `alb` |
| `private_subnet_ids` | `asg`, `rds` |
| `nat_public_ips` | Give to third parties for outbound allow-listing |
| `private_route_table_ids` | Extra VPC endpoints |

## Gotchas

- **Two AZs minimum.** An ALB refuses to build with fewer. `az_count` validates this.
- **AWS takes 5 addresses per subnet** — a `/24` gives 251 usable, not 256.
- **NAT gateways go in public subnets.** Putting one in a private subnet creates a gateway with no path out.
- **`enable_dns_hostnames` must stay true** or load balancers misbehave in ways that look like application bugs.
