############################################
# AMI lookup
# Used only when var.ami_id is left empty.
############################################
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  name   = "${var.project_name}-${var.environment}"
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
}

############################################
# IAM role, policies, and instance profile
# Roles and policies live in the root module,
# driven by variables (see variables.tf).
############################################
data "aws_iam_policy_document" "ec2_assume_role" {
  count = var.create_instance_profile ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  count = var.create_instance_profile ? 1 : 0

  name               = "${local.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role[0].json
}

# AWS-managed policies, listed by ARN in var.instance_managed_policy_arns.
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = var.create_instance_profile ? toset(var.instance_managed_policy_arns) : toset([])

  role       = aws_iam_role.instance[0].name
  policy_arn = each.value
}

# Optional extra inline policy, e.g. read access to one S3 bucket.
resource "aws_iam_role_policy" "inline" {
  count = var.create_instance_profile && var.instance_inline_policy_json != "" ? 1 : 0

  name   = "${local.name}-ec2-inline"
  role   = aws_iam_role.instance[0].id
  policy = var.instance_inline_policy_json
}

resource "aws_iam_instance_profile" "instance" {
  count = var.create_instance_profile ? 1 : 0

  name = "${local.name}-ec2-profile"
  role = aws_iam_role.instance[0].name
}

############################################
# Module 1: the load balancer
############################################
module "alb" {
  source = "./modules/alb"

  name               = local.name
  vpc_id             = var.vpc_id
  subnet_ids         = var.alb_subnet_ids         # provided by you
  security_group_ids = var.alb_security_group_ids # provided by you

  listener_port     = var.listener_port
  target_port       = var.app_port
  health_check_path = var.health_check_path

  tags = var.tags
}

############################################
# Module 2: the launch template
############################################
module "launch_template" {
  source = "./modules/launch_template"

  name               = local.name
  ami_id             = local.ami_id
  instance_type      = var.instance_type
  security_group_ids = var.instance_security_group_ids # provided by you
  key_name           = var.key_name
  http_port          = var.app_port

  iam_instance_profile_name = var.create_instance_profile ? aws_iam_instance_profile.instance[0].name : ""

  page_title = "${var.project_name} (${var.environment})"
  page_body  = "Served by Apache, installed by launch template user data."

  tags = var.tags
}

############################################
# One EC2 instance built from the launch template
############################################
resource "aws_instance" "web" {
  subnet_id = var.instance_subnet_id # provided by you

  launch_template {
    id      = module.launch_template.launch_template_id
    version = "$Latest"
  }

  tags = merge(var.tags, { Name = "${local.name}-web" })
}

############################################
# Register the instance with the target group
############################################
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = module.alb.target_group_arn
  target_id        = aws_instance.web.id
  port             = var.app_port
}
