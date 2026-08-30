# =============================================================================
# EXAMPLE: web-app-asg-alb
# -----------------------------------------------------------------------------
# A complete, working stack composed entirely from the modules in this library:
#
#   internet -> ALB (public subnets) -> target group -> ASG (private subnets)
#
# Read this file top to bottom. Notice that EVERY module receives IDs produced
# by another module. No module reaches out and creates something another module
# owns -- that discipline is what makes them reusable.
#
# Swap module.network for your own vpc_id and subnet_ids and everything below
# works unchanged against an existing network.
# =============================================================================

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# The ROOT module configures the provider. The child modules never do -- that
# is what lets you point this whole stack at another region or account.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# 1. NETWORK
# -----------------------------------------------------------------------------
# The only module that creates rather than consumes. Delete this block and pass
# your own IDs below if you already have a VPC.
module "network" {
  source = "../../modules/vpc"

  name       = var.project_name
  cidr_block = "10.0.0.0/16"

  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  # Left false deliberately. Our bootstrap downloads nothing, so the instances
  # need no outbound internet -- saving ~$32/month.
  enable_nat_gateway = false

  # Free, and often removes the only reason people enable NAT at all.
  enable_s3_gateway_endpoint = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# 2. SECURITY GROUPS
# -----------------------------------------------------------------------------
# Two groups that reference EACH OTHER. This is the pattern worth copying: the
# app tier trusts a security group, not an IP range.
module "alb_sg" {
  source = "../../modules/security-group"

  name        = "${var.project_name}-alb"
  description = "Public entry point for ${var.project_name}"
  vpc_id      = module.network.vpc_id

  ingress_rules = {
    http = {
      description = "HTTP from the internet"
      from_port   = 80
      to_port     = 80
      cidr_ipv4   = var.allowed_cidr
    }
  }

  egress_rules = {
    to_app = {
      description                  = "Reach the app tier"
      from_port                    = var.app_port
      to_port                      = var.app_port
      referenced_security_group_id = module.app_sg.security_group_id
    }
  }

  tags = local.tags
}

module "app_sg" {
  source = "../../modules/security-group"

  name        = "${var.project_name}-app"
  description = "Application tier for ${var.project_name}"
  vpc_id      = module.network.vpc_id

  ingress_rules = {
    from_alb = {
      description = "Only the load balancer may reach us"
      from_port   = var.app_port
      to_port     = var.app_port
      # A security group ID, NOT a CIDR. Survives IP changes and blocks any
      # rogue instance that happens to share the subnet.
      referenced_security_group_id = module.alb_sg.security_group_id
    }
  }

  # No egress rules at all. The app cannot initiate any outbound connection.
  # It can still REPLY to the load balancer, because security groups are
  # stateful. This is the tightest setting that still works.
  allow_all_egress = false

  tags = local.tags
}

# -----------------------------------------------------------------------------
# 3. IAM
# -----------------------------------------------------------------------------
# Session Manager access with no SSH key, no key pair, and no open port 22.
module "app_profile" {
  source = "../../modules/iam-instance-profile"

  name = "${var.project_name}-app"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# 4. LAUNCH TEMPLATE
# -----------------------------------------------------------------------------
module "app_lt" {
  source = "../../modules/launch-template"

  name          = "${var.project_name}-app"
  instance_type = var.instance_type
  architecture  = startswith(var.instance_type, "t4g.") ? "arm64" : "x86_64"

  # The script is rendered with these values before it reaches AWS.
  user_data_template_path = "${path.module}/scripts/bootstrap.sh"
  user_data_vars = {
    app_port      = tostring(var.app_port)
    response_text = var.response_text
  }

  security_group_ids        = [module.app_sg.security_group_id]
  iam_instance_profile_name = module.app_profile.instance_profile_name

  instance_tags = local.tags
  tags          = local.tags
}

# -----------------------------------------------------------------------------
# 5. TARGET GROUP
# -----------------------------------------------------------------------------
module "app_tg" {
  source = "../../modules/target-group"

  name   = "app"
  vpc_id = module.network.vpc_id
  port   = var.app_port

  # 200 is the password. Anything else and the instance is treated as dead.
  health_check_path    = "/"
  health_check_matcher = "200"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# 6. LOAD BALANCER
# -----------------------------------------------------------------------------
module "alb" {
  source = "../../modules/alb"

  name               = "${var.project_name}-alb"
  internal           = false
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.alb_sg.security_group_id]

  default_target_group_arn = module.app_tg.target_group_arn

  # Answered by the load balancer itself, touching no server.
  # If /ping works but / returns 503, the problem is your instances, not your
  # network. That one fact cuts debugging time in half.
  listener_rules = {
    ping = {
      priority     = 100
      path_pattern = ["/ping"]
      fixed_response = {
        message_body = "pong - the load balancer itself is alive"
        status_code  = "200"
      }
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# 7. AUTO SCALING GROUP
# -----------------------------------------------------------------------------
# This is where everything converges. The ASG launches instances from the
# template, into the private subnets, and registers each one into the target
# group automatically -- no register-targets call ever again.
module "app_asg" {
  source = "../../modules/asg"

  name = "${var.project_name}-app"

  launch_template_id = module.app_lt.launch_template_id
  # Passing the real version number (not "$Latest") means a bootstrap script
  # edit shows up as a visible diff and triggers an instance refresh.
  launch_template_version = module.app_lt.latest_version

  subnet_ids        = module.network.private_subnet_ids
  target_group_arns = [module.app_tg.target_group_arn]

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # ELB health checking means a crashed APP gets the instance replaced, not
  # just a crashed virtual machine.
  health_check_type = "ELB"

  enable_instance_refresh = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# 8. DNS  (optional)
# -----------------------------------------------------------------------------
data "aws_route53_zone" "main" {
  count = var.enable_dns ? 1 : 0

  name         = var.hosted_zone_name
  private_zone = false
}

module "dns" {
  source = "../../modules/route53-record"
  count  = var.enable_dns ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id

  records = {
    app = {
      name       = "${var.subdomain}.${var.hosted_zone_name}"
      type       = "A"
      alias_name = module.alb.alb_dns_name
      # The LOAD BALANCER's zone, not yours. Getting this wrong is the most
      # common Route 53 mistake there is.
      alias_zone_id = module.alb.alb_zone_id
    }
  }
}
