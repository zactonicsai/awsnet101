# =============================================================================
# MODULE: rds
# -----------------------------------------------------------------------------
# A managed relational database in private subnets.
#
# A DB SUBNET GROUP is RDS's way of saying "these are the subnets I may place
# instances in." It must span at least two AZs even for a single-AZ instance,
# because AWS needs somewhere to fail over to if you later enable Multi-AZ.
#
# COST WARNING: RDS is one of the more expensive AWS services. A db.t4g.micro
# is roughly $12/month before storage and backups, and Multi-AZ doubles it.
# =============================================================================

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.name}-"
  subnet_ids  = var.subnet_ids
  description = "Subnet group for ${var.name}"

  tags = merge(var.tags, { Name = "${var.name}-subnet-group" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier_prefix = "${var.name}-"

  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  # Setting max_allocated_storage equal to allocated_storage disables
  # autoscaling; AWS rejects a max lower than the current size.
  max_allocated_storage = var.max_allocated_storage > var.allocated_storage ? var.max_allocated_storage : null
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id

  db_name  = var.db_name
  username = var.username

  # Exactly one of these must be set. manage_master_user_password hands the
  # secret to Secrets Manager so it never enters Terraform state.
  manage_master_user_password = var.manage_master_password ? true : null
  password                    = var.manage_master_password ? null : var.password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids

  # Belt and braces. The subnet group already keeps this private, but an
  # explicit false makes the intent unmistakable to anyone reading the code.
  publicly_accessible = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  # Patch versions install themselves during the maintenance window.
  # Major versions never upgrade automatically -- those are always deliberate.
  auto_minor_version_upgrade = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  performance_insights_enabled = var.performance_insights_enabled
  apply_immediately            = var.apply_immediately

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    ignore_changes = [
      # timestamp() changes on every plan, which would show a permanent
      # spurious diff on the snapshot name.
      final_snapshot_identifier,
      # RDS rotates the managed password on its own schedule.
      password,
    ]
  }
}
