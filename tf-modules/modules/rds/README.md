# Module: `rds`

A managed relational database in private subnets, with the master password handled by Secrets Manager.

> **Cost warning:** RDS is one of the pricier AWS services. `db.t4g.micro` is roughly $12/month before storage and backups, and `multi_az = true` doubles it.

## Usage

```hcl
module "db_sg" {
  source = "../../modules/security-group"
  name   = "db"
  vpc_id = module.network.vpc_id

  ingress_rules = {
    postgres_from_app = {
      from_port                    = 5432
      to_port                      = 5432
      referenced_security_group_id = module.app_sg.security_group_id  # not a CIDR
    }
  }
}

module "database" {
  source = "../../modules/rds"
  name   = "myapp"

  subnet_ids         = module.network.private_subnet_ids   # PRIVATE
  security_group_ids = [module.db_sg.security_group_id]

  engine         = "postgres"
  instance_class = "db.t4g.micro"
  db_name        = "myapp"

  manage_master_password  = true    # password never enters Terraform state
  backup_retention_period = 7
}
```

### Giving the app access to the password

```hcl
data "aws_iam_policy_document" "read_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.database.master_user_secret_arn]
  }
}

module "app_profile" {
  source          = "../../modules/iam-instance-profile"
  inline_policies = { db-secret = data.aws_iam_policy_document.read_secret.json }
}
```

The app fetches credentials at runtime. No password in your code, state, or environment.

### Production shape

```hcl
multi_az                     = true    # doubles cost, survives an AZ failure
backup_retention_period      = 30
deletion_protection          = true
skip_final_snapshot          = false
performance_insights_enabled = true
```

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `subnet_ids` | list(string) | — | **Injected.** Private, 2+ AZs, validated |
| `security_group_ids` | list(string) | — | **Injected** |
| `instance_class` | string | `db.t4g.micro` | |
| `manage_master_password` | bool | `true` | Secrets Manager. Strongly preferred |
| `multi_az` | bool | `false` | Doubles cost |
| `backup_retention_period` | number | `7` | **0 disables backups entirely** |
| `storage_encrypted` | bool | `true` | Cannot be enabled later |
| `max_allocated_storage` | number | `100` | Storage autoscaling ceiling |

## Gotchas

- **Encryption cannot be enabled on an existing instance.** You would have to snapshot and restore. Get it right at creation.
- **A DB subnet group needs 2+ AZs even for single-AZ instances**, because AWS needs a failover target if you later enable Multi-AZ.
- **`backup_retention_period = 0` silently disables backups.** Never outside a throwaway environment.
- **`skip_final_snapshot = true` means an accidental destroy is unrecoverable.** Set false in production.
- **`password` is stored in PLAIN TEXT in state** when `manage_master_password = false`. Use the managed option.
- **`apply_immediately = true` can restart the database.** Changes otherwise wait for the maintenance window.
