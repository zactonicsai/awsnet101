# Module: `secrets-manager`

A Secrets Manager secret, optionally with a generated password.

## Why this exists

Applications need credentials, and the two obvious places are both wrong:

- **Hard-coded in user data** — visible to anyone who can describe the launch template
- **A Terraform variable** — lands in state, and usually in shell history too

The right shape: store it here, grant the instance role permission to read it, and have the app fetch it at boot. The value never appears in the launch template, and rotating it requires no redeploy.

## Usage

```hcl
module "app_admin" {
  source = "../../modules/secrets-manager"

  name        = "myapp/prod/admin"
  generate_password = true
  password_length   = 28

  # null is replaced by the generated password
  secret_key_value = {
    username = "admin"
    password = null
  }
}
```

Produces `{"username":"admin","password":"<generated>"}`.

### Granting an instance access to exactly this secret

```hcl
data "aws_iam_policy_document" "read" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.app_admin.secret_arn]   # not "*"
  }
}

module "app_profile" {
  source          = "../../modules/iam-instance-profile"
  inline_policies = { read-secret = data.aws_iam_policy_document.read.json }
}
```

Then pass only the **ARN** into user data — an ARN is not sensitive:

```hcl
user_data_vars = { admin_secret_arn = module.app_admin.secret_arn }
```

And fetch it at boot:

```bash
SECRET=$(aws secretsmanager get-secret-value --secret-id "$ARN" --query SecretString --output text)
USERNAME=$(echo "$SECRET" | jq -r .username)
PASSWORD=$(echo "$SECRET" | jq -r .password)
```

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `name` | string | — | Use a path convention: `app/env/purpose` |
| `generate_password` | bool | `false` | Value **does** land in state — see below |
| `secret_key_value` | map(string) | `null` | JSON object; nulls get the password |
| `secret_string` | string | `null` | Literal value |
| `recovery_window_in_days` | number | `7` | 0 for immediate deletion in test |
| `read_principal_arns` | list(string) | `[]` | Resource-policy read access |

## Gotchas

- **Generated passwords are stored in Terraform state.** Far better than Git, but state must be treated as secret: encrypted S3 backend, restricted access, never committed. For the strongest option use RDS's `manage_master_password`, where the value never touches Terraform at all.
- **`recovery_window_in_days > 0` reserves the name.** Recreating a secret with the same name fails until the window expires. Use `0` in test environments.
- **`ignore_changes = [secret_string]`** is set, so an external rotation is not reverted on the next apply.
- **Special characters are restricted by default** to avoid values that break shell quoting or JDBC connection strings.
- **Cost:** $0.40/secret/month plus $0.05 per 10,000 calls.
