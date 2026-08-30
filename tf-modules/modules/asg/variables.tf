variable "name" {
  description = "Name prefix for the Auto Scaling Group."
  type        = string
}

variable "launch_template_id" {
  description = "EXISTING launch template ID. Pass module.app_lt.launch_template_id."
  type        = string
}

variable "launch_template_version" {
  description = <<-EOT
    Which version to launch.

      "$Latest"  -- always the newest. Convenient, but changes never appear in
                    `terraform plan`, so drift is invisible.
      "$Default" -- the version marked default in the console.
      "3"        -- an explicit pin. Pass module.app_lt.latest_version to get a
                    visible diff on every change. RECOMMENDED.
  EOT
  type        = string
  default     = "$Latest"
}

variable "subnet_ids" {
  description = "EXISTING subnet IDs to launch into. Use PRIVATE subnets for anything behind a load balancer. Spread across 2+ AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids cannot be empty."
  }
}

variable "target_group_arns" {
  description = <<-EOT
    EXISTING target group ARNs to register instances into.

    This is the connective tissue between the ASG and the load balancer. The
    ASG registers every new instance automatically and deregisters it before
    termination -- you never call register-targets by hand again.
  EOT
  type        = list(string)
  default     = []
}

# --- Capacity ----------------------------------------------------------------

variable "min_size" {
  description = "Never drop below this many instances."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Never exceed this many. Acts as a cost ceiling as well as a capacity one."
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Target instance count. Leave null to let the ASG manage it (correct when using scaling policies -- otherwise Terraform fights the autoscaler on every apply)."
  type        = number
  default     = null
}

# --- Health --------------------------------------------------------------

variable "health_check_type" {
  description = <<-EOT
    "EC2" -- replace only when the VM itself fails (hypervisor-level).
    "ELB" -- ALSO replace when the load balancer's health check fails.

    Use ELB whenever target groups are attached. With EC2, an instance whose
    application crashed stays in service forever: the VM is fine, so the ASG
    sees no problem, while the load balancer refuses to send it traffic.
  EOT
  type        = string
  default     = "ELB"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "health_check_type must be EC2 or ELB."
  }
}

variable "health_check_grace_period" {
  description = "Seconds to ignore health checks after launch, giving user data time to run. Too short and instances get killed mid-boot, producing an infinite replacement loop. Raise it for slow bootstraps."
  type        = number
  default     = 300
}

# --- Instance refresh --------------------------------------------------------

variable "enable_instance_refresh" {
  description = "Roll out new instances automatically when the launch template changes. This is how you deploy a new AMI or bootstrap script with zero downtime."
  type        = bool
  default     = true
}

variable "instance_refresh_min_healthy_percentage" {
  description = "Percentage that must stay healthy during a refresh. 100 adds a new instance before removing an old one (needs max_size > desired). 50 replaces half at a time and is cheaper."
  type        = number
  default     = 90
}

variable "instance_refresh_checkpoint_delay" {
  description = "Seconds to pause between refresh batches, letting you catch a bad rollout before it reaches every instance."
  type        = number
  default     = 0
}

# --- Scaling policies --------------------------------------------------------

variable "enable_target_tracking" {
  description = "Add a target-tracking scaling policy. AWS creates and manages the CloudWatch alarms for you -- far simpler than hand-built step scaling."
  type        = bool
  default     = false
}

variable "target_tracking_metric" {
  description = "\"cpu\" tracks average CPU. \"alb_requests\" tracks requests per instance and needs target_group_arn_suffix and alb_arn_suffix."
  type        = string
  default     = "cpu"

  validation {
    condition     = contains(["cpu", "alb_requests"], var.target_tracking_metric)
    error_message = "target_tracking_metric must be cpu or alb_requests."
  }
}

variable "target_tracking_value" {
  description = "The value to hold. 60 with metric \"cpu\" means: keep average CPU near 60%."
  type        = number
  default     = 60
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix, required only for alb_requests tracking. Pass module.alb.arn_suffix."
  type        = string
  default     = null
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix, required only for alb_requests tracking. Pass module.tg.arn_suffix."
  type        = string
  default     = null
}

# --- Lifecycle ---------------------------------------------------------------

variable "termination_policies" {
  description = "Which instance to kill when scaling in. OldestInstance keeps the fleet fresh; Default balances across AZs first."
  type        = list(string)
  default     = ["Default"]
}

variable "capacity_rebalance" {
  description = "Proactively replace Spot instances AWS has warned it will reclaim. Leave true when using Spot; harmless otherwise."
  type        = bool
  default     = true
}

variable "protect_from_scale_in" {
  description = "Stop the ASG scaling in instances it created. Only needed for stateful workloads such as ECS capacity providers."
  type        = bool
  default     = false
}

variable "wait_for_capacity_timeout" {
  description = "How long `terraform apply` waits for instances to become healthy. \"0\" disables waiting entirely. Set this generously when health checks are slow."
  type        = string
  default     = "10m"
}

variable "tags" {
  description = "Tags. All of these propagate to launched instances as well as the ASG itself."
  type        = map(string)
  default     = {}
}
