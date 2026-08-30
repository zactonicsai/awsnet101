# Module: `launch-template`

A versioned recipe for creating EC2 instances: image, size, security groups, IAM profile, storage, and the user data script that configures them on first boot. **Creates no instances itself.**

## Why templates instead of `aws_instance`

An Auto Scaling Group needs a recipe it can replay whenever it adds capacity or replaces a failure. Templates are also **versioned** — every change creates a numbered version, so you can roll forward or pin back to a known-good one.

## Usage with user data

Two ways to supply the bootstrap script.

### Inline (simple, static)

```hcl
module "app_lt" {
  source        = "../../modules/launch-template"
  name          = "my-app"
  instance_type = "t4g.nano"

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
  EOT

  security_group_ids = [module.app_sg.security_group_id]
}
```

### Templated (values known only at apply time) — recommended

```hcl
module "app_lt" {
  source = "../../modules/launch-template"
  name   = "my-app"

  user_data_template_path = "${path.module}/scripts/bootstrap.sh"
  user_data_vars = {
    app_port    = "8080"
    bucket_name = module.assets.bucket_id     # not known until apply
    db_endpoint = module.database.address
  }

  security_group_ids        = [module.app_sg.security_group_id]
  iam_instance_profile_name = module.app_profile.instance_profile_name
}
```

In `scripts/bootstrap.sh`, `${app_port}` and `${bucket_name}` are substituted by `templatefile()` **before** the script ever reaches AWS. All `user_data_vars` values must be strings — use `tostring(var.port)` for numbers.

> **Escaping:** to keep a literal `${...}` in the script (a shell variable, say), write `$${...}`. Bash `$(command)` needs no escaping.

## Key inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `ami_id` | string | `null` | Null auto-resolves latest AL2023 via SSM |
| `architecture` | string | `arm64` | **Must match `instance_type`** |
| `instance_type` | string | `t4g.nano` | |
| `user_data` | string | `null` | Raw script. Module base64-encodes it |
| `user_data_template_path` | string | `null` | Mutually exclusive with `user_data` |
| `user_data_vars` | map(string) | `{}` | All values must be strings |
| `security_group_ids` | list(string) | `[]` | **Injected** |
| `iam_instance_profile_name` | string | `null` | **Injected.** Name, not ARN |
| `http_tokens` | string | `required` | IMDSv2. Blocks SSRF credential theft |
| `root_volume_size` | number | `8` | GB. Minimum for AL2023 |

## Key outputs

| Name | Notes |
|---|---|
| `launch_template_id` | Pass to the `asg` module |
| `latest_version` | Pass as `launch_template_version` for visible diffs |
| `user_data_rendered` | Sensitive. Inspect with `terraform console` |

## Gotchas

- **User data runs ONCE, on first boot.** Editing it does nothing to instances that already exist. The edit creates a new *template version*; the ASG's instance refresh is what actually rolls the fleet onto it. Pass `launch_template_version = module.app_lt.latest_version` so the change is visible in `plan` and triggers that refresh.
- **ARM/x86 mismatch = silent boot failure.** A `t4g.*` type with an x86_64 AMI simply never comes up. Derive it: `architecture = startswith(var.instance_type, "t4g.") ? "arm64" : "x86_64"`.
- **Never hard-code an AMI ID.** They differ per region and change with every patch.
- **`/dev/xvda` is the root device for Amazon Linux.** Ubuntu uses `/dev/sda1` — a mismatch silently creates a *second* volume and leaves root at its default size.
- **Tags do not propagate automatically.** This module sets `tag_specifications` for instances, volumes, and ENIs so nothing comes out untagged.
