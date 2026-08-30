# =============================================================================
# MODULE: asg
# -----------------------------------------------------------------------------
# An Auto Scaling Group keeps a target number of instances alive, replaces ones
# that fail, and registers every instance into your load balancer automatically.
#
# WHY AN ASG INSTEAD OF PLAIN aws_instance RESOURCES:
#   1. Self-healing. A failed instance is replaced without a human.
#   2. Automatic target registration. No more forgotten register-targets calls,
#      which is the single most common cause of a mystery 503.
#   3. Zero-downtime deploys. Change the launch template and instance refresh
#      rolls the fleet gradually, keeping the site up throughout.
#   4. Elasticity. Optional policies add and remove capacity with demand.
#
# Everything is injected: the launch template, the subnets, and the target
# groups all come from elsewhere. This module creates only the ASG and its
# optional scaling policy.
# =============================================================================

resource "aws_autoscaling_group" "this" {
  name_prefix = "${var.name}-"

  # vpc_zone_identifier is just "which subnets may I launch into".
  # The AZs are implied by the subnets, which is why there is no separate
  # availability_zones argument when you supply subnets.
  vpc_zone_identifier = var.subnet_ids

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = var.launch_template_id
    version = var.launch_template_version
  }

  # THE LINK TO THE LOAD BALANCER.
  # Every instance the ASG launches is registered into these target groups, and
  # deregistered (respecting the deregistration delay) before termination.
  target_group_arns = var.target_group_arns

  # Fall back to EC2 checks when no target group exists -- ELB health checking
  # without a load balancer attached would mark everything unhealthy forever.
  health_check_type         = length(var.target_group_arns) > 0 ? var.health_check_type : "EC2"
  health_check_grace_period = var.health_check_grace_period

  termination_policies      = var.termination_policies
  capacity_rebalance        = var.capacity_rebalance
  protect_from_scale_in     = var.protect_from_scale_in
  wait_for_capacity_timeout = var.wait_for_capacity_timeout

  # Wait for this many instances to pass their ELB health check before
  # `terraform apply` reports success. Without it, apply returns while the site
  # is still returning 503 and you think the deploy worked.
  min_elb_capacity = length(var.target_group_arns) > 0 ? var.min_size : null

  dynamic "instance_refresh" {
    for_each = var.enable_instance_refresh ? [1] : []
    content {
      # "Rolling" replaces instances in batches, keeping the service up.
      strategy = "Rolling"

      preferences {
        min_healthy_percentage = var.instance_refresh_min_healthy_percentage
        checkpoint_delay       = var.instance_refresh_checkpoint_delay
        # Wait for new instances to actually pass health checks, not merely to
        # reach "running", before moving to the next batch.
        instance_warmup = var.health_check_grace_period
      }

      # Which changes trigger a refresh. Without listing the launch template
      # here, editing your bootstrap script would update the template and leave
      # every running instance on the old version indefinitely.
      triggers = ["launch_template", "desired_capacity"]
    }
  }

  # ASG tags use their own block format and need propagate_at_launch, which is
  # what pushes the tag onto each instance rather than only onto the group.
  dynamic "tag" {
    for_each = merge(var.tags, { Name = var.name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true

    # The whole point of an autoscaler is that it changes desired_capacity
    # behind your back. Without ignoring it, every `terraform apply` would drag
    # the fleet back to the number in your code and undo the scaling.
    ignore_changes = [desired_capacity]
  }
}

# -----------------------------------------------------------------------------
# Optional target-tracking scaling policy
# -----------------------------------------------------------------------------
# Target tracking is the easiest scaling to reason about: you name a metric and
# a value, and AWS creates and manages the CloudWatch alarms needed to hold it.
resource "aws_autoscaling_policy" "target_tracking" {
  count = var.enable_target_tracking ? 1 : 0

  name                   = "${var.name}-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value = var.target_tracking_value

    dynamic "predefined_metric_specification" {
      for_each = var.target_tracking_metric == "cpu" ? [1] : []
      content {
        predefined_metric_type = "ASGAverageCPUUtilization"
      }
    }

    dynamic "predefined_metric_specification" {
      for_each = var.target_tracking_metric == "alb_requests" ? [1] : []
      content {
        predefined_metric_type = "ALBRequestCountPerTarget"
        # This oddly-formatted string is required by the API: the ALB's ARN
        # suffix and the target group's ARN suffix joined by a slash.
        resource_label = "${var.alb_arn_suffix}/${var.target_group_arn_suffix}"
      }
    }
  }
}
