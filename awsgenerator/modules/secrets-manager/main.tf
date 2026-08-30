# =============================================================================
# MODULE: secrets-manager
# -----------------------------------------------------------------------------
# A Secrets Manager secret, optionally with a generated password.
#
# WHY THIS EXISTS: applications need credentials, and the two obvious places to
# put them are both wrong. Hard-coding into user data means the secret is
# visible to anyone who can describe the launch template. Passing as a Terraform
# variable means it lands in state and often in shell history.
#
# The right shape is: store it here, grant the instance role permission to read
# it, and have the application fetch it at boot. The value never appears in the
# launch template, and rotating it does not require redeploying anything.
#
# COST: $0.40 per secret per month, plus $0.05 per 10,000 API calls.
# =============================================================================

resource "random_password" "this" {
  count = var.generate_password ? 1 : 0

  length  = var.password_length
  special = true
  # Restricting the character set avoids values that break shell quoting or
  # JDBC connection strings -- a genuinely common source of lost afternoons.
  override_special = var.password_override_special

  # Guarantee complexity rather than relying on chance.
  min_lower   = 2
  min_upper   = 2
  min_numeric = 2
  min_special = 2
}

locals {
  generated = var.generate_password ? random_password.this[0].result : null

  # Build the stored value. Three shapes are supported:
  #   1. A JSON object from secret_key_value (nulls filled with the password)
  #   2. The generated password on its own
  #   3. A literal string
  secret_value = (
    var.secret_key_value != null
    ? jsonencode({ for k, v in var.secret_key_value : k => v == null ? local.generated : v })
    : (var.generate_password ? local.generated : var.secret_string)
  )
}

resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = var.description
  kms_key_id  = var.kms_key_id

  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_secretsmanager_secret_version" "this" {
  # Only create a version when there is something to store. A secret with no
  # version exists but returns an error on read, which is confusing.
  count = local.secret_value != null ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = local.secret_value

  lifecycle {
    # If something else rotates this secret (a Lambda, or a human), do not drag
    # it back to the Terraform-generated value on the next apply.
    ignore_changes = [secret_string]
  }
}

# -----------------------------------------------------------------------------
# Optional resource policy granting read access
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "read" {
  count = length(var.read_principal_arns) > 0 ? 1 : 0

  statement {
    sid    = "AllowRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.read_principal_arns
    }

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = ["*"] # "*" here means this secret -- resource policies are scoped to their own resource
  }
}

resource "aws_secretsmanager_secret_policy" "this" {
  count = length(var.read_principal_arns) > 0 ? 1 : 0

  secret_arn = aws_secretsmanager_secret.this.arn
  policy     = data.aws_iam_policy_document.read[0].json
}
