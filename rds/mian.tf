# ============================================================
# SIMPLE PUBLIC AWS RDS POSTGRESQL DATABASE
#
# Database: appdb
# Username: admin
# Password: Changeme123!
# Port:     5432
#
# DEV / TEST EXAMPLE
# ============================================================


# ============================================================
# TERRAFORM
# ============================================================

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
# FIND AVAILABLE AVAILABILITY ZONES
#
# This is better than manually assuming us-east-1a and
# us-east-1b.
# ============================================================

data "aws_availability_zones" "available" {
  state = "available"
}


# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "zpostgres" {
  cidr_block = "10.20.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "zpostgres-vpc"
  }
}


# ============================================================
# INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "zpostgres" {
  vpc_id = aws_vpc.zpostgres.id

  tags = {
    Name = "zpostgres-igw"
  }
}


# ============================================================
# PUBLIC SUBNET 1
# ============================================================

resource "aws_subnet" "public_1" {
  vpc_id = aws_vpc.zpostgres.id

  cidr_block = "10.20.1.0/24"

  availability_zone = data.aws_availability_zones.available.names[0]

  map_public_ip_on_launch = true

  tags = {
    Name = "zpostgres-public-1"
  }
}


# ============================================================
# PUBLIC SUBNET 2
#
# RDS subnet groups should span multiple Availability Zones.
# ============================================================

resource "aws_subnet" "public_2" {
  vpc_id = aws_vpc.zpostgres.id

  cidr_block = "10.20.2.0/24"

  availability_zone = data.aws_availability_zones.available.names[1]

  map_public_ip_on_launch = true

  tags = {
    Name = "zpostgres-public-2"
  }
}


# ============================================================
# PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.zpostgres.id

  route {
    cidr_block = "0.0.0.0/0"

    gateway_id = aws_internet_gateway.zpostgres.id
  }

  tags = {
    Name = "zpostgres-public-route"
  }
}


# ============================================================
# ATTACH SUBNET 1 TO PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table_association" "public_1" {
  subnet_id = aws_subnet.public_1.id

  route_table_id = aws_route_table.public.id
}


# ============================================================
# ATTACH SUBNET 2 TO PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table_association" "public_2" {
  subnet_id = aws_subnet.public_2.id

  route_table_id = aws_route_table.public.id
}


# ============================================================
# POSTGRESQL SECURITY GROUP
# ============================================================

resource "aws_security_group" "zpostgres" {
  name = "zpostgres-public-sg"

  description = "Allow PostgreSQL connections"

  vpc_id = aws_vpc.zpostgres.id


  # ----------------------------------------------------------
  # POSTGRESQL
  #
  # WARNING:
  #
  # 0.0.0.0/0 means the whole Internet can ATTEMPT to connect.
  #
  # Better:
  #
  # cidr_blocks = ["YOUR.PUBLIC.IP/32"]
  #
  # ----------------------------------------------------------

  ingress {
    description = "PostgreSQL TCP 5432"

    from_port = 5432
    to_port   = 5432

    protocol = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }


  # ----------------------------------------------------------
  # OUTBOUND
  # ----------------------------------------------------------

  egress {
    from_port = 0
    to_port   = 0

    protocol = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "zpostgres-public-sg"
  }
}


# ============================================================
# RDS SUBNET GROUP
# ============================================================

resource "aws_db_subnet_group" "zpostgres" {
  name = "zpostgres-subnet-group"

  subnet_ids = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  tags = {
    Name = "zpostgres-subnet-group"
  }
}


# ============================================================
# RDS POSTGRESQL
# ============================================================

resource "aws_db_instance" "zpostgres" {

  # ----------------------------------------------------------
  # AWS RDS INSTANCE NAME
  #
  # Safe name:
  # - starts with a letter
  # - no underscores
  # - no reserved RDS name
  # ----------------------------------------------------------

  identifier = "postgres-dev"


  # ----------------------------------------------------------
  # DATABASE ENGINE
  # ----------------------------------------------------------

  engine = "postgres"


  # ----------------------------------------------------------
  # SMALL / LOW-COST INSTANCE
  # ----------------------------------------------------------

  instance_class = "db.t3.micro"


  # ----------------------------------------------------------
  # STORAGE
  # ----------------------------------------------------------

  allocated_storage = 20

  storage_type = "gp3"

  storage_encrypted = true


  # ----------------------------------------------------------
  # INITIAL DATABASE NAME
  #
  # appdb is a safe simple database name.
  # ----------------------------------------------------------

  db_name = "appdb"


  # ----------------------------------------------------------
  # MASTER USER
  #
  # IMPORTANT:
  #
  # DO NOT USE:
  #
  # rdsadmin
  # rds_superuser
  # rds_password
  # rds_replication
  # rds_reserved
  # rdstopmgr
  #
  # "admin" is okay.
  # ----------------------------------------------------------

  username = "kcsuper"


  # ----------------------------------------------------------
  # MASTER PASSWORD
  #
  # DEV / TEST ONLY.
  #
  # Changeme123! is acceptable for the RDS PostgreSQL
  # password rules.
  #
  # Production systems should use Secrets Manager.
  # ----------------------------------------------------------

  password = "changeme"


  # ----------------------------------------------------------
  # POSTGRESQL PORT
  # ----------------------------------------------------------

  port = 5432


  # ----------------------------------------------------------
  # MAKE RDS PUBLICLY REACHABLE
  # ----------------------------------------------------------

  publicly_accessible = true


  # ----------------------------------------------------------
  # RDS SUBNET GROUP
  # ----------------------------------------------------------

  db_subnet_group_name = aws_db_subnet_group.zpostgres.name


  # ----------------------------------------------------------
  # SECURITY GROUP
  # ----------------------------------------------------------

  vpc_security_group_ids = [
    aws_security_group.zpostgres.id
  ]


  # ----------------------------------------------------------
  # KEEP DEV COST / COMPLEXITY LOW
  # ----------------------------------------------------------

  multi_az = false


  # ----------------------------------------------------------
  # NO AUTOMATED BACKUPS FOR THIS THROWAWAY LAB
  # ----------------------------------------------------------

  backup_retention_period = 0


  # ----------------------------------------------------------
  # ALLOW TERRAFORM DESTROY
  # ----------------------------------------------------------

  deletion_protection = false


  # ----------------------------------------------------------
  # DO NOT CREATE FINAL SNAPSHOT ON DESTROY
  # ----------------------------------------------------------

  skip_final_snapshot = true


  # ----------------------------------------------------------
  # APPLY CHANGES IMMEDIATELY
  # ----------------------------------------------------------

  apply_immediately = true


  # ----------------------------------------------------------
  # ALLOW AWS MINOR VERSION UPDATES
  # ----------------------------------------------------------

  auto_minor_version_upgrade = true


  tags = {
    Name        = "postgres-dev"
    Environment = "development"
  }
}


# ============================================================
# OUTPUT: DATABASE HOST
# ============================================================

output "postgres_host" {
  description = "Public PostgreSQL RDS DNS hostname"

  value = aws_db_instance.zpostgres.address
}


# ============================================================
# OUTPUT: DATABASE ENDPOINT INCLUDING PORT
# ============================================================

output "postgres_endpoint" {
  description = "PostgreSQL hostname and port"

  value = aws_db_instance.zpostgres.endpoint
}


# ============================================================
# OUTPUT: DATABASE PORT
# ============================================================

output "postgres_port" {
  value = aws_db_instance.zpostgres.port
}


# ============================================================
# OUTPUT: DATABASE NAME
# ============================================================

output "postgres_database" {
  value = "appdb"
}


# ============================================================
# OUTPUT: USERNAME
# ============================================================

output "postgres_username" {
  value = "admin"
}


# ============================================================
# OUTPUT: FULL POSTGRESQL URL
#
# Terraform marks it sensitive because it contains a password.
# ============================================================

output "postgres_url" {
  value = "postgresql://admin:Changeme123!@${aws_db_instance.zpostgres.address}:5432/appdb?sslmode=require"

  sensitive = true
}


# ============================================================
# OUTPUT: PSQL COMMAND
# ============================================================

output "psql_command" {
  value = "PGPASSWORD='Changeme123!' psql \"host=${aws_db_instance.zpostgres.address} port=5432 dbname=appdb user=admin sslmode=require\""

  sensitive = true
}