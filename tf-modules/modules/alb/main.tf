# =============================================================================
# MODULE: alb
# -----------------------------------------------------------------------------
# The Application Load Balancer plus its listeners. Target groups, security
# groups, subnets, and certificates are all INJECTED -- this module creates
# none of them, which is what lets one ALB serve many target groups owned by
# different teams or stacks.
#
# THE FOUR PIECES A WORKING LOAD BALANCER NEEDS:
#   1. The load balancer     <- this module
#   2. A target group        <- the target-group module
#   3. Registered targets    <- the asg module, via target_group_arns
#   4. A listener            <- this module
# Miss any one and you get either total silence or a 503, with every individual
# component reporting as perfectly healthy.
# =============================================================================

locals {
  # HTTPS only makes sense once a certificate exists.
  https_enabled = var.certificate_arn != null

  # Redirect port 80 to 443 only when there is somewhere to redirect TO.
  do_redirect = local.https_enabled && var.redirect_http_to_https

  # Whichever listener actually serves traffic is where extra rules attach.
  # With a redirect in place, rules belong on the HTTPS listener -- attaching
  # them to the redirecting HTTP listener would mean they never match.
  primary_listener_arn = local.https_enabled ? aws_lb_listener.https[0].arn : (var.enable_http_listener ? aws_lb_listener.http[0].arn : null)
}

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = var.internal
  security_groups    = var.security_group_ids
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = var.idle_timeout
  enable_http2               = var.enable_http2
  drop_invalid_header_fields = var.drop_invalid_header_fields

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

# -----------------------------------------------------------------------------
# HTTP listener
# -----------------------------------------------------------------------------
# Without a listener the load balancer exists, reports as active, has a working
# DNS name -- and answers nothing at all. No error anywhere. It is the single
# most confusing failure mode in this whole architecture.
resource "aws_lb_listener" "http" {
  count = var.enable_http_listener ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = var.http_port
  protocol          = "HTTP"

  default_action {
    # NOTE the hyphens. The action TYPE strings are hyphenated while the nested
    # BLOCK names are underscored -- "fixed-response" vs fixed_response {}.
    # This mirrors the AWS API and catches almost everyone at least once.
    type = local.do_redirect ? "redirect" : (var.default_target_group_arn != null ? "forward" : "fixed-response")

    target_group_arn = (!local.do_redirect && var.default_target_group_arn != null) ? var.default_target_group_arn : null

    dynamic "redirect" {
      for_each = local.do_redirect ? [1] : []
      content {
        port     = "443"
        protocol = "HTTPS"
        # HTTP_301 is a permanent redirect, so browsers cache it and stop
        # requesting the insecure URL at all.
        status_code = "HTTP_301"
      }
    }

    dynamic "fixed_response" {
      for_each = (!local.do_redirect && var.default_target_group_arn == null) ? [1] : []
      content {
        content_type = var.default_fixed_response.content_type
        message_body = var.default_fixed_response.message_body
        status_code  = var.default_fixed_response.status_code
      }
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# HTTPS listener
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = var.default_target_group_arn != null ? "forward" : "fixed-response"
    target_group_arn = var.default_target_group_arn

    dynamic "fixed_response" {
      for_each = var.default_target_group_arn == null ? [1] : []
      content {
        content_type = var.default_fixed_response.content_type
        message_body = var.default_fixed_response.message_body
        status_code  = var.default_fixed_response.status_code
      }
    }
  }

  tags = var.tags
}

# Extra certificates for serving multiple domains from one listener via SNI.
resource "aws_lb_listener_certificate" "additional" {
  for_each = local.https_enabled ? toset(var.additional_certificate_arns) : toset([])

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = each.value
}

# -----------------------------------------------------------------------------
# Extra listener rules
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "this" {
  for_each = local.primary_listener_arn != null ? var.listener_rules : {}

  listener_arn = local.primary_listener_arn
  priority     = each.value.priority

  action {
    type = each.value.target_group_arn != null ? "forward" : (each.value.fixed_response != null ? "fixed-response" : "redirect")

    target_group_arn = each.value.target_group_arn

    dynamic "fixed_response" {
      for_each = each.value.fixed_response != null ? [each.value.fixed_response] : []
      content {
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
        status_code  = fixed_response.value.status_code
      }
    }

    dynamic "redirect" {
      for_each = each.value.redirect != null ? [each.value.redirect] : []
      content {
        host        = redirect.value.host
        path        = redirect.value.path
        port        = redirect.value.port
        protocol    = redirect.value.protocol
        status_code = redirect.value.status_code
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.path_pattern != null ? [1] : []
    content {
      path_pattern {
        values = each.value.path_pattern
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.host_header != null ? [1] : []
    content {
      host_header {
        values = each.value.host_header
      }
    }
  }

  tags = var.tags
}
