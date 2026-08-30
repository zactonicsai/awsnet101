# =============================================================================
# compute.tf
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# This creates the actual little servers that answer web requests. They sit in
# the PRIVATE subnets, so they have no public IP address and no way to be
# reached from the internet directly. The only thing on earth that can talk to
# them is our load balancer.
# =============================================================================

# -----------------------------------------------------------------------------
# PICK THE OPERATING SYSTEM IMAGE (AMI) AUTOMATICALLY
# -----------------------------------------------------------------------------
# An AMI (Amazon Machine Image) is a snapshot of a hard drive used as a template
# for new servers. AMI IDs are DIFFERENT in every region and change every time
# Amazon publishes a security update, so hard-coding one is a classic mistake.
#
# Instead we read AWS's own public SSM Parameter Store pointer, which always
# points at the newest Amazon Linux 2023 image for this region. Free, and always
# current. This is the officially recommended approach.
data "aws_ssm_parameter" "al2023_ami" {
  # We choose arm64 or x86_64 automatically based on the instance type you picked.
  # t4g.* instances use ARM (Graviton) chips; t3/t2 use Intel/AMD x86_64.
  # startswith() is a built-in Terraform string function.
  name = startswith(var.instance_type, "t4g.") ? "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64" : "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# -----------------------------------------------------------------------------
# THE SERVERS
# -----------------------------------------------------------------------------
resource "aws_instance" "app" {
  count = var.instance_count

  # .value is the actual AMI ID string stored in that SSM parameter.
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type

  # Spread servers across the private subnets using the modulo operator (%).
  # With 2 subnets: server 0 -> subnet 0, server 1 -> subnet 1, server 2 -> subnet 0...
  # This guarantees you never accidentally pile every server into one data center.
  subnet_id = aws_subnet.private[count.index % length(aws_subnet.private)].id

  # Attach the firewall that only trusts the load balancer.
  vpc_security_group_ids = [aws_security_group.app.id]

  # Belt and braces: never give this a public IP even if the subnet changes.
  associate_public_ip_address = false

  # templatefile() reads our bootstrap script and substitutes the ${...} markers
  # with real values before handing it to AWS.
  user_data = templatefile("${path.module}/user_data.sh", {
    app_port      = var.app_port
    response_text = var.response_text
  })

  # If you edit the script, replace the server rather than leaving a stale one.
  # (user_data only ever runs on FIRST boot, so editing it otherwise does nothing.)
  user_data_replace_on_change = true

  # --- Cost control -------------------------------------------------------
  root_block_device {
    volume_size = 8     # 8 GB is the minimum for Amazon Linux 2023
    volume_type = "gp3" # gp3 is cheaper AND faster than the older gp2. Always use gp3.
    encrypted   = true  # Encryption at rest is free. There is no reason not to.

    # Delete the disk when the server is deleted, so `terraform destroy`
    # doesn't quietly leave you paying for orphaned storage.
    delete_on_termination = true
  }

  # --- Security hardening -------------------------------------------------
  metadata_options {
    http_endpoint = "enabled"
    # IMDSv2 requires a session token, which blocks a whole family of attacks
    # (SSRF) that could otherwise steal the server's AWS credentials.
    # "required" means IMDSv1 is switched off. This is the modern default.
    http_tokens = "required"
    # Limit how many network hops the metadata response may travel. 1 stops
    # containers on the host from reaching it.
    http_put_response_hop_limit = 1
  }

  # We attach NO SSH key pair on purpose. There is nothing to SSH from, and no
  # key means no key to leak. If you later need shell access, use AWS Systems
  # Manager Session Manager - though note that requires VPC endpoints, which
  # cost about $7/month each. See the README's troubleshooting section.

  tags = {
    Name = "${var.project_name}-app-${count.index + 1}"
  }
}
