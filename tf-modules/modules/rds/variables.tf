variable "name" {
  description = "Identifier prefix for the instance and its subnet group."
  type        = string
}

variable "subnet_ids" {
  description = "EXISTING PRIVATE subnet IDs, at least two in different AZs. A database should never sit in a public subnet."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires at least 2 subnets in different Availability Zones."
  }
}

variable "security_group_ids" {
  description = "EXISTING security group IDs. The rule should allow the DB port from your APP's security group, never from a CIDR range."
  type        = list(string)
}

variable "engine" {
  description = "postgres, mysql, mariadb, and so on."
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  description = "Major.minor version. Leave null to take the current default for the engine, which avoids pinning to something that later goes end-of-life."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "db.t4g.micro is the cheapest current-generation option (~$12/mo). RDS is not cheap -- consider whether you need it for a learning project."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GB. Minimum 20 for most engines."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Enables storage autoscaling up to this ceiling. Set 0 to disable. Prevents the classic 3am disk-full outage."
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "gp3 is cheaper and faster than gp2. Use it."
  type        = string
  default     = "gp3"
}

variable "db_name" {
  description = "Name of the initial database created inside the instance."
  type        = string
  default     = null
}

variable "username" {
  description = "Master username. Avoid reserved words like \"admin\" on some engines."
  type        = string
  default     = "dbadmin"
}

variable "manage_master_password" {
  description = <<-EOT
    Let RDS generate the password and store it in Secrets Manager, rotating it
    automatically. Strongly preferred: no password ever touches your Terraform
    state, your repo, or your terminal history.

    Set false only if you must supply a password yourself.
  EOT
  type        = bool
  default     = true
}

variable "password" {
  description = "Master password, used only when manage_master_password is false. WARNING: this value is stored in PLAIN TEXT in Terraform state."
  type        = string
  default     = null
  sensitive   = true
}

variable "multi_az" {
  description = "Run a synchronous standby in a second AZ with automatic failover. Roughly DOUBLES the cost. Essential for production, wasteful for dev."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups. 0 DISABLES backups entirely -- never do that outside a throwaway environment. 7 is a sensible minimum."
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Daily UTC window for backups, e.g. \"03:00-04:00\". Pick your quietest hour."
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly UTC window for patching, e.g. \"sun:04:00-sun:05:00\". Must not overlap backup_window."
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "storage_encrypted" {
  description = "Encrypt at rest. Free. Note it CANNOT be enabled on an existing instance -- you would have to snapshot and restore, so get it right now."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "Customer-managed KMS key. Null uses the free AWS-managed key."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Block deletion until someone explicitly disables this. Turn it on for anything holding real data."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the farewell snapshot on delete. true is fine for dev; false in production means you can recover from an accidental destroy."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Query-level performance analysis. Free for 7 days of retention on most instance classes."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply changes now instead of waiting for the maintenance window. true can cause an immediate restart and brief downtime."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for the instance and subnet group."
  type        = map(string)
  default     = {}
}
