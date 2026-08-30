# Module: `s3-bucket`

An S3 bucket with safe defaults: encrypted, versioned, ACLs disabled, and public access blocked.

## Usage

```hcl
module "assets" {
  source      = "../../modules/s3-bucket"
  bucket_name = "myorg-myapp-assets-prod"   # globally unique across ALL AWS

  versioning_enabled  = true
  block_public_access = true

  lifecycle_rules = {
    expire-old-versions = {
      noncurrent_version_expiration_days = 30
    }
  }
}
```

### As an ALB access log target

```hcl
module "alb_logs" {
  source                        = "../../modules/s3-bucket"
  bucket_name                   = "myorg-alb-logs"
  enable_alb_access_logs_policy = true      # required, or delivery fails silently

  lifecycle_rules = {
    expire = { prefix = "", expiration_days = 90 }
  }
}

module "alb" {
  source             = "../../modules/alb"
  access_logs_bucket = module.alb_logs.bucket_id
  access_logs_prefix = "my-app"
}
```

### Granting an instance role access

```hcl
data "aws_iam_policy_document" "read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${module.assets.bucket_arn}/*"]
  }
}

module "app_profile" {
  source          = "../../modules/iam-instance-profile"
  inline_policies = { read-assets = data.aws_iam_policy_document.read.json }
}
```

Pair this with the `vpc` module's free S3 Gateway Endpoint and private instances reach S3 with **no NAT Gateway**.

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `bucket_name` | string | — | Globally unique across every AWS account |
| `versioning_enabled` | bool | `true` | Protects against deletion and ransomware |
| `block_public_access` | bool | `true` | Leave on unless hosting a public site |
| `sse_algorithm` | string | `AES256` | Free. `aws:kms` costs per request |
| `lifecycle_rules` | map(object) | `{}` | How you stop costs growing forever |
| `enable_alb_access_logs_policy` | bool | `false` | Required for ALB log delivery |
| `force_destroy` | bool | `false` | Dangerous outside test environments |

## Gotchas

- **Bucket names are globally unique across every AWS account on earth.** Include your org name or a random suffix.
- **Versioning without lifecycle rules grows forever.** Old versions keep costing storage. Always pair them.
- **The ALB log policy is not optional.** Without it, delivery fails silently — you notice when the bucket is empty. The module includes both the per-region ELB service account and the newer `logdelivery` principal so it works in every region.
- **Incomplete multipart uploads bill invisibly.** The `abort_incomplete_upload_days` default of 7 cleans them up.
- **`BucketOwnerEnforced` disables ACLs entirely** — the modern default, removing a whole class of object-ownership confusion.
