# =============================================================================
# EXAMPLE: Keycloak on EC2 (Docker) with RDS PostgreSQL
# -----------------------------------------------------------------------------
#   internet -> ALB (public subnets, NACL-protected)
#            -> ASG running the Keycloak container (private subnets)
#            -> RDS PostgreSQL (private subnets, no internet route)
#
# Demonstrates: Docker via user data, firewalld on the host, Secrets Manager
# for credentials, Network ACLs with explicit ingress AND egress, and a NAT
# Gateway (with an honest note about its cost).
# =============================================================================

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    })
  }
}

locals {
  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })

  public_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
  private_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]

  # Keycloak needs to know its own public URL to build correct redirects.
  # Fall back to the load balancer's own hostname when no domain is supplied.
  hostname_url = var.hostname_url != "" ? var.hostname_url : "http://${module.alb.alb_dns_name}"
}

# =============================================================================
# 1. NETWORK
# =============================================================================
module "network" {
  source = "../../modules/vpc"

  name       = var.project_name
  cidr_block = var.vpc_cidr

  public_subnet_cidrs  = local.public_cidrs
  private_subnet_cidrs = local.private_cidrs

  # NAT IS REQUIRED HERE, unlike the simpler example.
  # The instances must reach the internet to install Docker packages and pull
  # the Keycloak image from quay.io. That costs ~$32/month.
  # single_nat_gateway = true shares one across both AZs to halve the cost;
  # set it false in production so an AZ failure cannot cut off the other zone.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Free, and lets container image layers (which live in S3) be fetched
  # without crossing the NAT Gateway, cutting data processing charges.
  enable_s3_gateway_endpoint = true

  tags = local.tags
}

# =============================================================================
# 2. NETWORK ACLs -- subnet-level firewall, layered under the security groups
# =============================================================================
# NACLs are STATELESS. Every conversation needs rules in BOTH directions,
# including the ephemeral high ports that replies arrive on. The module adds
# those ephemeral rules automatically because forgetting them is the classic
# way to produce a subnet where everything mysteriously hangs.
module "public_nacl" {
  source = "../../modules/network-acl"
  count  = var.enable_nacls ? 1 : 0

  name       = "${var.project_name}-public"
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.public_subnet_ids

  ingress_rules = {
    http  = { rule_number = 100, from_port = 80, to_port = 80, cidr_block = var.allowed_cidr }
    https = { rule_number = 110, from_port = 443, to_port = 443, cidr_block = var.allowed_cidr }
  }

  egress_rules = {
    # Reach the Keycloak instances in the private subnets.
    to_app = {
      rule_number = 100
      from_port   = var.keycloak_http_port
      to_port     = var.keycloak_management_port
      cidr_block  = var.vpc_cidr
    }
    # NAT Gateway traffic on its way out to the internet.
    https_out = { rule_number = 110, from_port = 443, to_port = 443, cidr_block = "0.0.0.0/0" }
    http_out  = { rule_number = 120, from_port = 80, to_port = 80, cidr_block = "0.0.0.0/0" }
  }

  # Replies to inbound requests leave from high ports, and replies to the
  # NAT Gateway's outbound requests arrive on them.
  add_ephemeral_ingress_rule = true
  add_ephemeral_egress_rule  = true

  tags = local.tags
}

module "private_nacl" {
  source = "../../modules/network-acl"
  count  = var.enable_nacls ? 1 : 0

  name       = "${var.project_name}-private"
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  ingress_rules = {
    # From the load balancer only -- restricted to the VPC range.
    app_from_vpc = {
      rule_number = 100
      from_port   = var.keycloak_http_port
      to_port     = var.keycloak_management_port
      cidr_block  = var.vpc_cidr
    }
    # PostgreSQL between the app tier and the database, both inside the VPC.
    postgres = { rule_number = 110, from_port = 5432, to_port = 5432, cidr_block = var.vpc_cidr }
    # Keycloak clustering (Infinispan/JGroups), needed once you run 2+ nodes.
    cluster = { rule_number = 120, from_port = 7800, to_port = 7800, cidr_block = var.vpc_cidr }
  }

  egress_rules = {
    # Outbound HTTPS for dnf packages, the container image, and the
    # Secrets Manager API.
    https_out = { rule_number = 100, from_port = 443, to_port = 443, cidr_block = "0.0.0.0/0" }
    http_out  = { rule_number = 110, from_port = 80, to_port = 80, cidr_block = "0.0.0.0/0" }
    postgres  = { rule_number = 120, from_port = 5432, to_port = 5432, cidr_block = var.vpc_cidr }
    cluster   = { rule_number = 130, from_port = 7800, to_port = 7800, cidr_block = var.vpc_cidr }
    # DNS. Easy to forget, and without it absolutely nothing resolves.
    dns_tcp = { rule_number = 140, from_port = 53, to_port = 53, cidr_block = var.vpc_cidr }
    dns_udp = { rule_number = 150, protocol = "udp", from_port = 53, to_port = 53, cidr_block = var.vpc_cidr }
  }

  add_ephemeral_ingress_rule = true
  add_ephemeral_egress_rule  = true

  tags = local.tags
}

# =============================================================================
# 3. SECURITY GROUPS -- three tiers, each trusting only the one above it
# =============================================================================
module "alb_sg" {
  source = "../../modules/security-group"

  name        = "${var.project_name}-alb"
  description = "Public entry point for Keycloak"
  vpc_id      = module.network.vpc_id

  ingress_rules = {
    http  = { from_port = 80, to_port = 80, cidr_ipv4 = var.allowed_cidr }
    https = { from_port = 443, to_port = 443, cidr_ipv4 = var.allowed_cidr }
  }

  egress_rules = {
    to_app = {
      description                  = "Serve application traffic"
      from_port                    = var.keycloak_http_port
      to_port                      = var.keycloak_http_port
      referenced_security_group_id = module.app_sg.security_group_id
    }
    to_app_health = {
      description                  = "Run health checks on the management port"
      from_port                    = var.keycloak_management_port
      to_port                      = var.keycloak_management_port
      referenced_security_group_id = module.app_sg.security_group_id
    }
  }

  tags = local.tags
}

module "app_sg" {
  source = "../../modules/security-group"

  name        = "${var.project_name}-app"
  description = "Keycloak application tier"
  vpc_id      = module.network.vpc_id

  ingress_rules = {
    http_from_alb = {
      description                  = "Application traffic from the load balancer"
      from_port                    = var.keycloak_http_port
      to_port                      = var.keycloak_http_port
      referenced_security_group_id = module.alb_sg.security_group_id
    }
    health_from_alb = {
      description                  = "Health checks from the load balancer"
      from_port                    = var.keycloak_management_port
      to_port                      = var.keycloak_management_port
      referenced_security_group_id = module.alb_sg.security_group_id
    }
    cluster = {
      description = "Infinispan clustering between Keycloak nodes"
      from_port   = 7800
      to_port     = 7800
      self        = true # other members of this same group
    }
  }

  # UNLIKE the simpler example, this tier DOES need outbound access: dnf
  # packages, the container image from quay.io, and the Secrets Manager API.
  allow_all_egress = true

  tags = local.tags
}

module "db_sg" {
  source = "../../modules/security-group"

  name        = "${var.project_name}-db"
  description = "PostgreSQL for Keycloak"
  vpc_id      = module.network.vpc_id

  ingress_rules = {
    postgres_from_app = {
      description = "PostgreSQL from the Keycloak tier only"
      from_port   = 5432
      to_port     = 5432
      # A security group reference, not a CIDR. Nothing else in the VPC can
      # reach the database, even on the same subnet.
      referenced_security_group_id = module.app_sg.security_group_id
    }
  }

  tags = local.tags
}

# =============================================================================
# 4. DATABASE
# =============================================================================
module "database" {
  source = "../../modules/rds"

  name = var.project_name

  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.db_sg.security_group_id]

  engine         = "postgres"
  instance_class = var.db_instance_class
  db_name        = var.db_name
  username       = "keycloak"

  # RDS generates the password and stores it in Secrets Manager. It never
  # enters Terraform state, your repository, or your shell history.
  manage_master_password = true

  allocated_storage       = 20
  max_allocated_storage   = 100
  backup_retention_period = 7
  storage_encrypted       = true

  deletion_protection = var.enable_deletion_protection
  skip_final_snapshot = !var.enable_deletion_protection

  tags = local.tags
}

# =============================================================================
# 5. KEYCLOAK ADMIN CREDENTIALS
# =============================================================================
# A generated password stored in Secrets Manager. The instance fetches it at
# boot using its IAM role, so the password never appears in the launch
# template, in user data, or anywhere someone with describe permissions can see.
module "keycloak_admin" {
  source = "../../modules/secrets-manager"

  name        = "${var.project_name}/${var.environment}/admin"
  description = "Keycloak bootstrap admin credentials"

  generate_password = true
  password_length   = 28

  # A null value is replaced by the generated password, producing
  # {"username":"admin","password":"..."} in one step.
  secret_key_value = {
    username = "admin"
    password = null
  }

  recovery_window_in_days = 0 # immediate deletion, convenient for testing

  tags = local.tags
}

# =============================================================================
# 6. IAM -- permission to read exactly those two secrets, and nothing else
# =============================================================================
data "aws_iam_policy_document" "read_secrets" {
  statement {
    sid    = "ReadKeycloakSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Scoped to these two ARNs. Not "*". If this instance is ever compromised,
    # the attacker gets these two secrets and no others.
    resources = [
      module.database.master_user_secret_arn,
      module.keycloak_admin.secret_arn,
    ]
  }
}

module "app_profile" {
  source = "../../modules/iam-instance-profile"

  name = "${var.project_name}-app"

  managed_policy_arns = [
    # Session Manager: shell access with no SSH key and no inbound port 22.
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]

  inline_policies = {
    read-secrets = data.aws_iam_policy_document.read_secrets.json
  }

  tags = local.tags
}

# =============================================================================
# 7. LAUNCH TEMPLATE -- Docker, firewalld, and Keycloak via user data
# =============================================================================
module "keycloak_lt" {
  source = "../../modules/launch-template"

  name          = "${var.project_name}-app"
  instance_type = var.instance_type
  architecture  = startswith(var.instance_type, "t4g.") ? "arm64" : "x86_64"

  user_data_template_path = "${path.module}/scripts/bootstrap-keycloak.sh"
  user_data_vars = {
    aws_region       = var.aws_region
    db_secret_arn    = module.database.master_user_secret_arn
    admin_secret_arn = module.keycloak_admin.secret_arn
    db_host          = module.database.address
    db_port          = tostring(module.database.port)
    db_name          = var.db_name
    keycloak_image   = var.keycloak_image
    http_port        = tostring(var.keycloak_http_port)
    management_port  = tostring(var.keycloak_management_port)
    hostname_url     = local.hostname_url
  }

  security_group_ids        = [module.app_sg.security_group_id]
  iam_instance_profile_name = module.app_profile.instance_profile_name

  # Keycloak plus a container image needs more than the 8 GB default.
  root_volume_size = 20

  instance_tags = local.tags
  tags          = local.tags
}

# =============================================================================
# 8. TARGET GROUP -- health check points at the MANAGEMENT port
# =============================================================================
module "keycloak_tg" {
  source = "../../modules/target-group"

  name   = "kc"
  vpc_id = module.network.vpc_id
  port   = var.keycloak_http_port

  # THE DETAIL THAT CATCHES EVERYONE: Keycloak serves /health/ready on its
  # MANAGEMENT port (9000), not the application port (8080). Checking
  # /health/ready on 8080 returns 404 forever, every target is marked
  # unhealthy, and the ALB returns 503 while Keycloak runs perfectly.
  health_check_port    = tostring(var.keycloak_management_port)
  health_check_path    = "/health/ready"
  health_check_matcher = "200"

  # Migrations on first boot take a while; be patient before declaring death.
  health_check_interval = 30
  health_check_timeout  = 10
  healthy_threshold     = 2
  unhealthy_threshold   = 3

  # Keycloak holds session state in memory. Without clustering, stickiness
  # keeps a user pinned to one node so they are not randomly logged out.
  stickiness_enabled  = true
  stickiness_duration = 3600

  deregistration_delay = 60

  tags = local.tags
}

# =============================================================================
# 9. LOAD BALANCER
# =============================================================================
module "alb" {
  source = "../../modules/alb"

  name               = "${var.project_name}-alb"
  internal           = false
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.alb_sg.security_group_id]

  default_target_group_arn   = module.keycloak_tg.target_group_arn
  enable_deletion_protection = var.enable_deletion_protection

  # Keycloak logins can involve slow redirects; the 60s default is tight.
  idle_timeout = 300

  listener_rules = {
    # Answered by the load balancer itself, touching no instance. If /ping
    # works but / returns 503, the problem is Keycloak, not the network.
    ping = {
      priority       = 100
      path_pattern   = ["/ping"]
      fixed_response = { message_body = "pong - ALB is alive", status_code = "200" }
    }
  }

  tags = local.tags
}

# =============================================================================
# 10. AUTO SCALING GROUP
# =============================================================================
module "keycloak_asg" {
  source = "../../modules/asg"

  name = "${var.project_name}-app"

  launch_template_id      = module.keycloak_lt.launch_template_id
  launch_template_version = module.keycloak_lt.latest_version

  subnet_ids        = module.network.private_subnet_ids
  target_group_arns = [module.keycloak_tg.target_group_arn]

  min_size         = 1
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type = "ELB"

  # GENEROUS ON PURPOSE. This instance must install Docker, pull a ~450 MB
  # image, start a JVM, and run database migrations. Too short a grace period
  # kills instances mid-migration and replaces them forever in a loop -- the
  # most common way this deployment fails.
  health_check_grace_period = 900

  enable_instance_refresh                 = true
  instance_refresh_min_healthy_percentage = 50

  # Wait longer than usual for apply to report success.
  wait_for_capacity_timeout = "20m"

  tags = local.tags
}
