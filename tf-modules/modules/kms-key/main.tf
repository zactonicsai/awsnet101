# =============================================================================
# MODULE: kms-key
# -----------------------------------------------------------------------------
# A customer-managed KMS key with a sane default policy.
#
# DO YOU ACTUALLY NEED ONE? Most encryption in AWS -- EBS, S3, RDS, Secrets
# Manager -- works fine with the FREE AWS-managed key. A customer-managed key
# costs $1/month plus $0.03 per 10,000 requests, and is worth it when you need:
#   - an audit trail of every use, in CloudTrail
#   - the ability to revoke access by changing one key policy
#   - cross-account sharing of encrypted resources
#   - a compliance rule that demands it
# Otherwise, leave kms_key_id null in the other modules and save the money.
#
# THE MOST IMPORTANT THING TO KNOW: a key policy is not like other IAM. If you
# lock yourself out of a KMS key, AWS Support cannot recover it, and everything
# encrypted with it is permanently unreadable. That is why the default policy
# below always grants the account root full access.
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "key" {
  # STATEMENT 1 -- the anti-lockout statement. Do not remove this.
  # Granting the account root full control does NOT mean "everyone in the
  # account can use the key". It means normal IAM policies are allowed to grant
  # access, which is how you expect AWS to behave. Without it, the key policy
  # becomes the ONLY path to the key and a mistake is unrecoverable.
  statement {
    sid    = "EnableRootAccountAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.admin_role_arns) > 0 ? [1] : []
    content {
      sid    = "AllowKeyAdministration"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.admin_role_arns
      }
      actions = [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
        "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
        "kms:Get*", "kms:Delete*", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.user_role_arns) > 0 ? [1] : []
    content {
      sid    = "AllowKeyUsage"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.user_role_arns
      }
      actions = [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.service_principals) > 0 ? [1] : []
    content {
      sid    = "AllowServiceUsage"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = var.service_principals
      }
      actions = [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  multi_region            = var.multi_region
  policy                  = data.aws_iam_policy_document.key.json

  tags = merge(var.tags, { Name = var.alias })
}

# An alias is what makes a key usable by humans. Key IDs are raw UUIDs.
resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}
