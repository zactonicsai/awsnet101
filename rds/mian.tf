terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ============================================================
# AWS PROVIDER
# ============================================================

provider "aws" {
  region = "us-east-1"
}

# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "postgres_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "postgres-dev-vpc"
  }
}

# ============================================================
# INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "postgres_igw" {
  vpc_id = aws_vpc.postgres_vpc.id

  tags = {
    Name = "postgres-dev-igw"
  }
}

# ============================================================
# PUBLIC SUBNET 1
# ============================================================

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.postgres_vpc.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "postgres-public-1"
  }
}

# ============================================================
# PUBLIC SUBNET 2
#
# RDS needs subnets in multiple Availability Zones.
# ============================================================

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.postgres_vpc.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "postgres-public-2"
  }
}

# ============================================================
# PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.postgres_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.postgres_igw.id
  }

  tags = {
    Name = "postgres-public-route-table"
  }
}

# ============================================================
# CONNECT SUBNET 1 TO ROUTE TABLE
# ============================================================

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# CONNECT SUBNET 2 TO ROUTE TABLE
# ============================================================

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# SECURITY GROUP
#
# WARNING:
# 0.0.0.0/0 allows anyone on the Internet to try port 5432.
#
# For better security change this to your IP:
#
# cidr_blocks = ["1.2.3.4/32"]
# ============================================================

resource "aws_security_group" "postgres_sg" {
  name        = "postgres-public-sg"
  description = "Allow PostgreSQL connections"
  vpc_id      = aws_vpc.postgres_vpc.id

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"

    # DEVELOPMENT ONLY
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "postgres-public-sg"
  }
}

# ============================================================
# RDS SUBNET GROUP
# ============================================================

resource "aws_db_subnet_group" "postgres" {
  name = "postgres-dev-subnets"

  subnet_ids = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  tags = {
    Name = "postgres-dev-subnets"
  }
}

# ============================================================
# POSTGRESQL RDS DATABASE
# ============================================================

resource "aws_db_instance" "postgres" {

  identifier = "postgres-dev"

  # PostgreSQL
  engine = "postgres"

  # Small / low-cost database
  instance_class = "db.t3.micro"

  # 20 GB storage
  allocated_storage = 20

  # General Purpose SSD
  storage_type = "gp3"

  # Encrypt database storage
  storage_encrypted = true

  # Database name
  db_name = "appdb"

  # ----------------------------------------------------------
  # LOGIN
  # ----------------------------------------------------------

  username = "admin"

  # DEVELOPMENT ONLY
  # Do not normally store passwords directly in Terraform.
  password = "Changeme123!"

  # PostgreSQL default port
  port = 5432

  # ----------------------------------------------------------
  # PUBLIC ACCESS
  # ----------------------------------------------------------

  publicly_accessible = true

  db_subnet_group_name = aws_db_subnet_group.postgres.name

  vpc_security_group_ids = [
    aws_security_group.postgres_sg.id
  ]

  # ----------------------------------------------------------
  # KEEP COST LOW
  # ----------------------------------------------------------

  # Do not create standby database
  multi_az = false

  # Disable backups for this simple development example
  backup_retention_period = 0

  # Allow Terraform to delete database
  deletion_protection = false

  # Do not make final snapshot when destroying
  skip_final_snapshot = true

  apply_immediately = true

  auto_minor_version_upgrade = true

  tags = {
    Name        = "postgres-dev"
    Environment = "development"
  }
}

# ============================================================
# OUTPUTS
# ============================================================

output "postgres_host" {
  description = "RDS PostgreSQL hostname"
  value       = aws_db_instance.postgres.address
}

output "postgres_port" {
  description = "PostgreSQL port"
  value       = aws_db_instance.postgres.port
}

output "database_name" {
  value = "appdb"
}

output "database_username" {
  value = "admin"
}

# ============================================================
# FULL DATABASE CONNECTION URL
#
# Terraform hides this because it contains the password.
# ============================================================

output "postgres_url" {
  value = "postgresql://admin:Changeme123!@${aws_db_instance.postgres.address}:5432/appdb?sslmode=require"

  sensitive = true
}

# ============================================================
# PSQL CONNECTION COMMAND
# ============================================================

output "psql_command" {
  value = "PGPASSWORD='Changeme123!' psql -h ${aws_db_instance.postgres.address} -p 5432 -U admin -d appdb"

  sensitive = true
}