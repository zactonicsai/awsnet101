# =============================================================================
# MODULE: target-group
# -----------------------------------------------------------------------------
# A target group is two things at once:
#   1. A list of destinations the load balancer may send traffic to.
#   2. A health-check policy deciding which of them are currently allowed to
#      receive it.
#
# This module deliberately does NOT register targets. Registration belongs to
# whoever owns the compute: the ASG registers itself via target_group_arns, and
# for one-off instances you use aws_lb_target_group_attachment in your root
# module. Keeping registration out of here is what makes the module reusable by
# ASGs, Lambda, containers, and static instances alike.
# =============================================================================

locals {
  # AWS enforces a 6-character maximum on target group name_prefix, and 32 on
  # the full generated name. Truncating here beats failing at apply time with
  # an error most people find baffling.
  name_prefix = substr(replace(var.name, "/[^a-zA-Z0-9-]/", ""), 0, 6)

  # Health checks are only configurable for non-Lambda targets in the same way.
  is_lambda = var.target_type == "lambda"
}

resource "aws_lb_target_group" "this" {
  name_prefix = local.name_prefix

  # Lambda target groups must NOT specify port, protocol, or vpc_id -- AWS
  # rejects the request if you do. Hence the conditionals.
  port        = local.is_lambda ? null : var.port
  protocol    = local.is_lambda ? null : var.protocol
  vpc_id      = local.is_lambda ? null : var.vpc_id
  target_type = var.target_type

  deregistration_delay = local.is_lambda ? null : var.deregistration_delay
  slow_start           = local.is_lambda || var.slow_start_duration == 0 ? null : var.slow_start_duration

  load_balancing_algorithm_type = local.is_lambda ? null : var.load_balancing_algorithm

  health_check {
    enabled  = true
    path     = var.health_check_path
    matcher  = var.health_check_matcher
    interval = var.health_check_interval
    timeout  = var.health_check_timeout

    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold

    port     = local.is_lambda ? null : var.health_check_port
    protocol = local.is_lambda ? null : var.protocol
  }

  dynamic "stickiness" {
    for_each = local.is_lambda ? [] : [1]
    content {
      type            = "lb_cookie"
      enabled         = var.stickiness_enabled
      cookie_duration = var.stickiness_duration
    }
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # A target group referenced by a listener cannot be deleted, so any change
    # forcing replacement must build the new one first. This is exactly why we
    # use name_prefix rather than a fixed name -- two groups briefly coexist.
    create_before_destroy = true
  }
}
