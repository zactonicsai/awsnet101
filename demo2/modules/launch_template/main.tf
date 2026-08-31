terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  # Use the caller's custom user data if given, otherwise render the built-in
  # "install Apache and serve a page" script.
  user_data_rendered = var.user_data_override != "" ? var.user_data_override : templatefile(
    "${path.module}/user_data.sh.tftpl",
    {
      page_title = var.page_title
      page_body  = var.page_body
      http_port  = var.http_port
    }
  )
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name}-"
  description   = "Launch template for ${var.name}"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  # Security groups are supplied by the caller.
  vpc_security_group_ids = var.security_group_ids

  user_data = base64encode(local.user_data_rendered)

  # IAM instance profile is created in the root module and passed in by name.
  dynamic "iam_instance_profile" {
    for_each = var.iam_instance_profile_name != "" ? [1] : []
    content {
      name = var.iam_instance_profile_name
    }
  }

  block_device_mappings {
    device_name = var.root_device_name
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IMDSv2 required - current AWS security best practice.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = var.name })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-root" })
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}
