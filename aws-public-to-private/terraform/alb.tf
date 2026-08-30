# =============================================================================
# alb.tf
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# This is the heart of the whole tutorial. Three pieces work together:
#
#   1. LOAD BALANCER - the public receptionist. Has a public address, sits in
#      the public subnets, and is the only thing the internet ever touches.
#
#   2. TARGET GROUP  - the receptionist's list of who is available to help,
#      plus a rule for how to check they are still awake (the health check).
#
#   3. LISTENER      - the receptionist's instructions: "when someone knocks on
#      port 80, hand them to this target group."
#
# Miss any one of the three and nothing works. A load balancer with no listener
# silently ignores all traffic. A listener pointing at an empty target group
# returns 503. This is where almost every beginner gets stuck.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. THE APPLICATION LOAD BALANCER (ALB)
# -----------------------------------------------------------------------------
# COST WARNING: this is the most expensive thing in the project, about
# $16.20/month just to exist, plus a few cents for traffic. It is NOT in the
# free tier. If you are only learning, build it, test it, and destroy it the
# same day - that costs about 5 cents.
resource "aws_lb" "main" {
  name = "${var.project_name}-alb"

  # internal = false means INTERNET-FACING (it gets public IP addresses).
  # Setting this to true would make it reachable only from inside the VPC.
  # This single boolean is the difference between a public and private door.
  internal = false

  # "application" = Layer 7. It understands HTTP: paths, headers, hostnames.
  # The alternative, "network" (NLB), is Layer 4 - faster and it understands
  # only IP addresses and ports. Use ALB for websites, NLB for raw TCP speed.
  load_balancer_type = "application"

  # The ALB's own firewall - the one that allows the internet in on port 80.
  security_groups = [aws_security_group.alb.id]

  # WHICH SUBNETS THE ALB PUTS ITS NETWORK CARDS IN.
  # These MUST be the PUBLIC subnets, and there MUST be at least two of them in
  # two different Availability Zones. AWS refuses to build the ALB otherwise.
  # [*] is a splat expression - shorthand for "the .id of every item in the list".
  subnets = aws_subnet.public[*].id

  # Safety catch for real environments. Set to true in production so a stray
  # `terraform destroy` cannot delete your live load balancer.
  enable_deletion_protection = false

  # Drop malformed requests instead of forwarding them. Free security win.
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# -----------------------------------------------------------------------------
# 2. THE TARGET GROUP
# -----------------------------------------------------------------------------
# A target group is a named list of destinations plus a health-check policy.
# The load balancer NEVER sends traffic to a target marked unhealthy - that is
# the whole point, and it's how a website survives one server crashing.
resource "aws_lb_target_group" "app" {
  name = "${var.project_name}-tg"

  # The port and protocol the ALB uses to talk to your servers on the INSIDE.
  # This does not have to match the port the public uses. The public hits
  # port 80; the ALB forwards to port 8080. That translation is normal.
  port     = var.app_port
  protocol = "HTTP"

  vpc_id = aws_vpc.main.id

  # target_type "instance" means we register EC2 instance IDs.
  # Other options: "ip" (any IP in the VPC, used for containers/Fargate)
  #                "lambda" (a serverless function - no servers at all)
  #                "alb" (chain a load balancer behind an NLB)
  target_type = "instance"

  # --- THE HEALTH CHECK ---------------------------------------------------
  # Every 30 seconds the ALB quietly requests this path from every target and
  # judges the answer. This is exactly where "returns 200" matters.
  health_check {
    enabled = true
    path    = "/" # the URL to ask for
    port    = "traffic-port"
    protocol = "HTTP"

    # matcher lists the HTTP status codes that count as HEALTHY.
    # "200" means only a clean success passes. You can widen it, e.g. "200-299".
    matcher = "200"

    interval            = 30 # seconds between checks
    timeout             = 5  # seconds to wait for an answer before calling it a failure
    healthy_threshold   = 2  # 2 passes in a row -> mark it healthy, start sending traffic
    unhealthy_threshold = 2  # 2 failures in a row -> stop sending traffic
  }

  # deregistration_delay: how long the ALB waits for in-flight requests to
  # finish before yanking a target out. AWS defaults to 300 seconds (5 minutes),
  # which makes `terraform destroy` feel frozen. 30 is plenty for a demo.
  deregistration_delay = 30

  # Stickiness sends a returning visitor back to the same server using a cookie.
  # Off by default here, because our stateless demo genuinely doesn't care and
  # stickiness makes it harder to SEE the load balancing happen.
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  # Target groups cannot be renamed in place. Creating the new one first avoids
  # an error where the listener still references the old group.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# -----------------------------------------------------------------------------
# REGISTERING THE SERVERS INTO THE TARGET GROUP
# -----------------------------------------------------------------------------
# Creating a server and creating a target group does NOT connect them.
# This resource is the actual wire between the two. Forgetting it produces a
# perfectly healthy-looking setup that returns 503 Service Unavailable.
resource "aws_lb_target_group_attachment" "app" {
  count = var.instance_count

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app[count.index].id
  port             = var.app_port
}

# -----------------------------------------------------------------------------
# 3. THE LISTENER
# -----------------------------------------------------------------------------
# The listener is the ALB's ear. It watches one port and decides what happens.
# No listener = the ALB exists but answers nothing at all.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # default_action is what happens when no other rule matches.
  # "forward" hands the request to our target group.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# -----------------------------------------------------------------------------
# BONUS: A ZERO-SERVER LISTENER RULE (very useful for debugging)
# -----------------------------------------------------------------------------
# This rule answers /ping directly FROM THE LOAD BALANCER without touching any
# server at all. If /ping works but / returns 503, you have proved the problem
# is your servers or health check, not your networking. That single fact saves
# hours of confusion.
#
# It also demonstrates fixed-response, which is how you could build this entire
# tutorial with NO EC2 INSTANCES AT ALL - see the README's cheaper variants.
resource "aws_lb_listener_rule" "ping" {
  listener_arn = aws_lb_listener.http.arn

  # Lower number = evaluated first. Rules are checked in priority order, and
  # the default_action only runs if nothing matched.
  priority = 100

  action {
    type = "fixed_response"
    fixed_response {
      content_type = "text/plain"
      message_body = "pong - the load balancer itself is alive\n"
      status_code  = "200"
    }
  }

  condition {
    path_pattern {
      values = ["/ping"]
    }
  }
}
