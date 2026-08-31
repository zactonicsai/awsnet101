# Module: `launch_template`

Creates one `aws_launch_template` with user data that installs Apache and serves
a simple page. A launch template is a recipe, not a running server — point an
`aws_instance` or an `aws_autoscaling_group` at it to actually launch something.

Security groups and the IAM instance profile are passed in by the caller.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_launch_template` | AMI, size, security groups, IAM profile, disk, and boot script |

The boot script (`user_data.sh.tftpl`) installs `httpd`, writes
`/var/www/html/index.html` showing the instance ID and Availability Zone, writes
`/var/www/html/health` containing `ok`, and starts the service.

## Usage

Minimum:

```hcl
module "launch_template" {
  source = "./modules/launch_template"

  name               = "demo-dev"
  ami_id             = data.aws_ami.amazon_linux_2023.id
  security_group_ids = var.instance_security_group_ids
}
```

Typical:

```hcl
module "launch_template" {
  source = "./modules/launch_template"

  name               = "demo-dev"
  ami_id             = data.aws_ami.amazon_linux_2023.id
  instance_type      = "t3.micro"
  security_group_ids = ["sg-0bbb…"]
  key_name           = ""                    # no SSH; use SSM
  http_port          = 80

  iam_instance_profile_name = aws_iam_instance_profile.instance.name

  page_title = "demo (dev)"
  page_body  = "Served by Apache."

  tags = { Project = "demo" }
}
```

Launch one instance from it:

```hcl
resource "aws_instance" "web" {
  subnet_id = var.instance_subnet_id

  launch_template {
    id      = module.launch_template.launch_template_id
    version = "$Latest"
  }
}
```

Or scale it out later with an Auto Scaling group instead:

```hcl
resource "aws_autoscaling_group" "web" {
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = var.alb_subnet_ids
  target_group_arns   = [module.alb.target_group_arn]

  launch_template {
    id      = module.launch_template.launch_template_id
    version = "$Latest"
  }
}
```

Use your own boot script instead of the built-in one:

```hcl
module "launch_template" {
  # …
  user_data_override = file("${path.root}/scripts/my_bootstrap.sh")
}
```

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|:---:|---|
| `name` | string | — | yes | Base name for the template and its instances |
| `ami_id` | string | — | yes | AMI to boot. Built-in user data expects Amazon Linux 2023 or 2 |
| `instance_type` | string | `"t3.micro"` | no | EC2 size |
| `security_group_ids` | list(string) | — | yes | Security groups for the instances |
| `iam_instance_profile_name` | string | `""` | no | Instance profile name; `""` attaches none |
| `key_name` | string | `""` | no | SSH key pair; `""` launches without one |
| `http_port` | number | `80` | no | Port Apache listens on. Must match the target group |
| `page_title` | string | `"Hello from Terraform"` | no | Heading on the demo page |
| `page_body` | string | see `variables.tf` | no | Paragraph on the demo page |
| `user_data_override` | string | `""` | no | Raw script replacing the built-in one |
| `root_device_name` | string | `"/dev/xvda"` | no | Root device name |
| `root_volume_size` | number | `8` | no | Root volume size in GiB |
| `root_volume_type` | string | `"gp3"` | no | Root volume type |
| `enable_detailed_monitoring` | bool | `false` | no | 1-minute CloudWatch metrics (extra cost) |
| `tags` | map(string) | `{}` | no | Tags for the template, instances, and volumes |

## Outputs

| Name | Description |
|---|---|
| `launch_template_id` | ID to reference from `aws_instance` or an ASG |
| `launch_template_arn` | ARN of the template |
| `launch_template_name` | Generated name |
| `latest_version` | Latest version number |

## Notes

- **User data runs only on first boot.** Editing `page_title` creates a new
  launch template version but does not change a running instance. Replace the
  instance to see the change: `terraform taint aws_instance.web && terraform apply`.
- `http_tokens = "required"` enforces IMDSv2. If a tool on the instance reads
  metadata without requesting a token first, it will fail — fix the tool rather
  than weakening this.
- The root volume is encrypted with the default AWS-managed key. Set a
  `kms_key_id` in `main.tf` if you need a customer-managed key.
- `name_prefix` is used instead of `name` so Terraform can create a replacement
  template before destroying the old one.
- The template writes tags to instances and volumes through
  `tag_specifications`. Tags set on an `aws_instance` resource take precedence
  over these.
