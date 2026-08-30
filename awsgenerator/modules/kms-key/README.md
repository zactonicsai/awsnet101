# Module: `kms-key`

A customer-managed KMS key with a safe default policy.

## Do you actually need one?

Most AWS encryption — EBS, S3, RDS, Secrets Manager — works fine with the **free AWS-managed key**. A customer-managed key costs **$1/month plus $0.03 per 10,000 requests**.

Use one when you need:

- An audit trail of every use in CloudTrail
- To revoke access by changing a single key policy
- Cross-account sharing of encrypted resources
- A compliance rule that requires it

Otherwise leave `kms_key_id = null` in the other modules and save the money.

## Usage

```hcl
module "app_key" {
  source = "../../modules/kms-key"

  alias       = "myapp-prod"
  description = "Encrypts RDS storage and secrets for myapp"

  service_principals = ["rds.amazonaws.com", "secretsmanager.amazonaws.com"]
  user_role_arns     = [module.app_profile.role_arn]
}

module "database" {
  source     = "../../modules/rds"
  kms_key_id = module.app_key.key_arn
}
```

## The most important thing to know

**A key policy is not like other IAM.** If you lock yourself out of a KMS key, AWS Support cannot recover it, and everything encrypted with it becomes permanently unreadable.

That is why the default policy always grants the **account root** full access. This does *not* mean everyone in the account can use the key — it means normal IAM policies are allowed to grant access, which is how you expect AWS to behave. Without it, the key policy becomes the only path to the key and one mistake is unrecoverable.

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `alias` | string | — | Without the `alias/` prefix |
| `enable_key_rotation` | bool | `true` | Free, transparent. Leave on |
| `deletion_window_in_days` | number | `30` | 7–30, validated |
| `service_principals` | list(string) | `[]` | e.g. `rds.amazonaws.com` |
| `user_role_arns` | list(string) | `[]` | Encrypt/decrypt |
| `admin_role_arns` | list(string) | `[]` | Key administration |
| `multi_region` | bool | `false` | Cannot be changed later |

## Gotchas

- **A service cannot encrypt on your behalf without a `service_principals` entry.** RDS creation fails with a permissions error that does not obviously point at the key.
- **Rotation keeps old material**, so previously encrypted data stays readable. There is no downside.
- **Deletion is irreversible** after the window. There is no undo, no support ticket, nothing.
- **Always create an alias.** Raw key IDs are UUIDs and unusable by humans.
