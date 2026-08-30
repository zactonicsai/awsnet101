# =============================================================================
# MODULE: iam-instance-profile
# -----------------------------------------------------------------------------
# An IAM role plus the instance profile that wraps it, ready to attach to a
# launch template.
#
# WHY THIS MATTERS MORE THAN IT LOOKS:
# An instance profile is how a server gets AWS credentials WITHOUT anyone
# storing an access key on disk. The instance asks the metadata service for
# short-lived credentials that rotate automatically. Hard-coded keys in a user
# data script or an environment variable are the single most common way AWS
# accounts get compromised. This module is how you avoid ever needing them.
#
# The "instance profile" is a container object that exists purely because EC2
# cannot attach a role directly. You almost never think about it again.
# =============================================================================

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "AllowServiceToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = [var.trusted_service]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix          = "${var.name}-"
  description          = "Instance role for ${var.name}"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = var.permissions_boundary

  tags = merge(var.tags, { Name = var.name })
}

# Attach managed policies. for_each over a set keeps the addresses stable even
# if you reorder the list -- with count, reordering would destroy and recreate
# unrelated attachments.
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.this.name
  tags        = var.tags

  lifecycle {
    create_before_destroy = true
  }
}
