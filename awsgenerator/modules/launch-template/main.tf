# =============================================================================
# MODULE: launch-template
# -----------------------------------------------------------------------------
# A launch template is a saved recipe for creating EC2 instances: which image,
# which size, which security groups, which bootstrap script. It creates NO
# instances by itself.
#
# WHY TEMPLATES INSTEAD OF LAUNCHING INSTANCES DIRECTLY:
# An Auto Scaling Group needs a recipe it can replay whenever it adds capacity
# or replaces a failed machine. The template is that recipe. It is also
# VERSIONED -- every change creates a new numbered version, so you can roll an
# ASG forward to a new version or pin it back to a known-good one.
#
# This module accepts existing security groups, an existing instance profile,
# and an existing AMI. It creates nothing but the template itself.
# =============================================================================

# Resolve the newest Amazon Linux 2023 AMI, but only when the caller did not
# supply one. AWS publishes these public SSM pointers and reading them is free.
data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.al2023[0].value

  # Render the bootstrap script from whichever input was supplied.
  # templatefile() substitutes ${...} placeholders at plan time, so the script
  # that reaches AWS is already complete -- no runtime templating needed.
  rendered_user_data = (
    var.user_data_template_path != null
    ? templatefile(var.user_data_template_path, var.user_data_vars)
    : var.user_data
  )
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-"
  description   = "Launch template for ${var.name}"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  # base64encode is required: EC2 expects user data pre-encoded.
  # The null check keeps the argument absent (rather than an empty string)
  # when no script was supplied.
  user_data = local.rendered_user_data != null ? base64encode(local.rendered_user_data) : null

  # NOTE: there is no "replace on change" setting here -- that is an
  # aws_instance argument and does not exist on launch templates. Editing the
  # script instead produces a NEW TEMPLATE VERSION automatically. Nothing
  # happens to running instances until something rolls them, which is exactly
  # what the asg module's instance_refresh does when you pass latest_version.

  vpc_security_group_ids = var.security_group_ids

  dynamic "iam_instance_profile" {
    # for_each over a 0-or-1 element list is how you make a whole block optional.
    for_each = var.iam_instance_profile_name != null ? [1] : []
    content {
      name = var.iam_instance_profile_name
    }
  }

  dynamic "network_interfaces" {
    # Only emit this block when the caller explicitly forces a public IP
    # setting. Omitting it lets the instance inherit the subnet default, which
    # is almost always what you want.
    for_each = var.associate_public_ip_address != null ? [1] : []
    content {
      associate_public_ip_address = var.associate_public_ip_address
      security_groups             = var.security_group_ids
      delete_on_termination       = true
    }
  }

  # --- Root volume ---------------------------------------------------------
  block_device_mappings {
    # /dev/xvda is the root device for Amazon Linux. Other distributions differ
    # (Ubuntu uses /dev/sda1); a mismatch silently creates a SECOND volume and
    # leaves the root disk at its default size.
    device_name = "/dev/xvda"

    ebs {
      volume_size = var.root_volume_size
      volume_type = var.root_volume_type
      encrypted   = var.root_volume_encrypted
      kms_key_id  = var.kms_key_id

      # Without this, terminating an instance leaves an orphaned volume
      # billing forever. A very common source of mystery AWS charges.
      delete_on_termination = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.extra_block_devices
    content {
      device_name = block_device_mappings.value.device_name
      ebs {
        volume_size           = block_device_mappings.value.volume_size
        volume_type           = block_device_mappings.value.volume_type
        encrypted             = block_device_mappings.value.encrypted
        delete_on_termination = block_device_mappings.value.delete_on_termination
        kms_key_id            = var.kms_key_id
      }
    }
  }

  # --- Instance metadata service -------------------------------------------
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.http_tokens
    http_put_response_hop_limit = var.http_put_response_hop_limit
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  # Tags do NOT flow from the template to what it launches automatically.
  # You must declare tag_specifications per resource type, or your instances
  # and volumes come out untagged and invisible in Cost Explorer.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.instance_tags, { Name = var.name })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.instance_tags, { Name = "${var.name}-volume" })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(var.instance_tags, { Name = "${var.name}-eni" })
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}
