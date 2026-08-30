# Module: `iam-instance-profile`

An IAM role plus the instance profile that wraps it, ready to attach to a launch template.

## Why this matters more than it looks

An instance profile is how a server gets AWS credentials **without anyone storing an access key**. The instance requests short-lived, auto-rotating credentials from the metadata service. Hard-coded keys in a user data script or environment variable are among the most common causes of compromised AWS accounts.

## Usage

```hcl
module "app_profile" {
  source = "../../modules/iam-instance-profile"
  name   = "my-app"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",  # Session Manager
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",   # metrics + logs
  ]
}

module "app_lt" {
  source                    = "../../modules/launch-template"
  iam_instance_profile_name = module.app_profile.instance_profile_name  # NAME, not ARN
}
```

### With a scoped inline policy

Build JSON with the data source, never by hand:

```hcl
data "aws_iam_policy_document" "read_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${module.assets.bucket_arn}/*"]   # this bucket only
  }
}

module "app_profile" {
  source          = "../../modules/iam-instance-profile"
  name            = "my-app"
  inline_policies = { read-assets = data.aws_iam_policy_document.read_bucket.json }
}
```

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `name` | string | — | Prefix for role and profile |
| `managed_policy_arns` | list(string) | `[]` | AWS-managed or your own |
| `inline_policies` | map(string) | `{}` | name => JSON |
| `trusted_service` | string | `ec2.amazonaws.com` | Who may assume the role |
| `permissions_boundary` | string | `null` | Often mandatory in enterprises |

## Key outputs

| Name | Notes |
|---|---|
| `instance_profile_name` | **What the launch-template module wants** |
| `role_arn` | Reference in S3/KMS resource policies |
| `role_name` | Attach further policies externally |

## Gotchas

- **The launch template wants the profile NAME, not the ARN.** Passing the ARN produces a confusing failure.
- **`AmazonSSMManagedInstanceCore` alone is not enough** for Session Manager in a private subnet with no NAT — you also need three VPC interface endpoints (~$7.20/mo each).
- **`managed_policy_arns` uses `for_each`**, so reordering the list is safe.
