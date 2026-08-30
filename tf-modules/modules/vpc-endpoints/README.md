# Module: `vpc-endpoints`

Lets resources in private subnets reach AWS services without an internet gateway or NAT Gateway. Traffic stays on the AWS network.

## Two kinds, and the difference is financial

| | Gateway | Interface |
|---|---|---|
| Services | **S3 and DynamoDB only** | Everything else |
| Mechanism | Route table entry | A real ENI per subnet |
| Cost | **FREE** | **~$7.20/mo per endpoint per AZ** |

## The arithmetic people get wrong

| Option | Cost | Covers |
|---|---|---|
| NAT Gateway | ~$32/mo + $0.045/GB | **Every** destination, including Docker Hub |
| 3 interface endpoints × 2 AZs | **~$43/mo** | Exactly three AWS services |

Endpoints are not automatically the cheap choice. They win when you need one or two services and want traffic off the public internet. **NAT wins when you need general outbound access** — pulling container images from quay.io or Docker Hub, calling third-party APIs, installing OS packages.

## Usage

```hcl
# Free — always worth enabling
module "endpoints" {
  source = "../../modules/vpc-endpoints"

  name              = "myapp"
  vpc_id            = module.network.vpc_id
  gateway_endpoints = ["s3"]
  route_table_ids   = module.network.private_route_table_ids
}
```

### Session Manager without a NAT Gateway

```hcl
module "ssm_sg" {
  source = "../../modules/security-group"
  name   = "vpce"
  vpc_id = module.network.vpc_id

  ingress_rules = {
    https = {
      from_port                    = 443
      to_port                      = 443
      referenced_security_group_id = module.app_sg.security_group_id
    }
  }
}

module "endpoints" {
  source = "../../modules/vpc-endpoints"

  name               = "myapp"
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.ssm_sg.security_group_id]

  interface_endpoints = ["ssm", "ec2messages", "ssmmessages"]
  gateway_endpoints   = ["s3"]
  route_table_ids     = module.network.private_route_table_ids
}
```

~$43/month for shell access with no NAT and no open port 22.

### Pulling images from ECR privately

```hcl
interface_endpoints = ["ecr.api", "ecr.dkr"]
gateway_endpoints   = ["s3"]   # REQUIRED — image layers live in S3
```

Omitting the S3 gateway endpoint means the API calls succeed and the layer download hangs. Very confusing, entirely avoidable.

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `vpc_id` | string | — | **Injected** |
| `subnet_ids` | list(string) | `[]` | **Injected.** One ENI each — you pay per subnet |
| `security_group_ids` | list(string) | `[]` | **Injected.** Must allow 443 inbound |
| `route_table_ids` | list(string) | `[]` | **Injected.** For gateway endpoints |
| `interface_endpoints` | list(string) | `[]` | Billed |
| `gateway_endpoints` | list(string) | `[]` | Free. Validated to s3/dynamodb |
| `private_dns_enabled` | bool | `true` | Real hostnames resolve privately |

## Gotchas

- **Interface endpoints need a security group allowing 443** from the calling instances, or every API call times out with no useful error.
- **You pay per subnet.** Listing four subnets doubles the cost of listing two.
- **`private_dns_enabled` requires `enable_dns_hostnames` and `enable_dns_support`** on the VPC.
- **ECR needs the S3 gateway endpoint too.** Layers are stored in S3.
- **The `vpc` module already creates an S3 gateway endpoint** via `enable_s3_gateway_endpoint`. Don't create a second one for the same route tables.
