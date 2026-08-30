# =============================================================================
# MODULE: s3-bucket
# -----------------------------------------------------------------------------
# An S3 bucket with the safe defaults already applied: encrypted, versioned,
# and with public access blocked.
#
# WHY SO MANY SEPARATE RESOURCES:
# Modern AWS provider versions split bucket configuration into individual
# resources (aws_s3_bucket_versioning, aws_s3_bucket_public_access_block, and
# so on) rather than nesting everything inside aws_s3_bucket. It is more
# verbose, but each setting shows as its own line in `terraform plan`, so you
# can see exactly which control is changing.
# =============================================================================

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = merge(var.tags, { Name = var.bucket_name })
}

# THE MOST IMPORTANT RESOURCE IN THIS FILE.
# All four settings must be true to genuinely block public access; leaving any
# one false leaves a path by which an object or policy can expose data.
resource "aws_s3_bucket_public_access_block" "this" {
  count = var.block_public_access ? 1 : 0

  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "aws:kms" ? var.kms_key_id : null
    }
    bucket_key_enabled = var.sse_algorithm == "aws:kms" ? var.bucket_key_enabled : null
  }
}

# Disable ACLs entirely. Bucket-owner-enforced is the modern default and
# removes a whole category of "who owns this object" confusion.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  # Lifecycle configuration must wait for versioning, or rules referencing
  # noncurrent versions are rejected.
  depends_on = [aws_s3_bucket_versioning.this]

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.key
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_version_expiration_days
        }
      }

      dynamic "transition" {
        for_each = rule.value.transition_to_ia_days != null ? [1] : []
        content {
          days          = rule.value.transition_to_ia_days
          storage_class = "STANDARD_IA"
        }
      }

      dynamic "transition" {
        for_each = rule.value.transition_to_glacier_days != null ? [1] : []
        content {
          days          = rule.value.transition_to_glacier_days
          storage_class = "GLACIER"
        }
      }

      # Failed multipart uploads leave invisible fragments that you pay for
      # forever. Almost nobody notices. Always clean them up.
      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_upload_days != null ? [1] : []
        content {
          days_after_initiation = rule.value.abort_incomplete_upload_days
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Optional: allow ALB access log delivery
# -----------------------------------------------------------------------------
data "aws_elb_service_account" "current" {
  count = var.enable_alb_access_logs_policy ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = var.enable_alb_access_logs_policy ? 1 : 0
}

data "aws_iam_policy_document" "alb_logs" {
  count = var.enable_alb_access_logs_policy ? 1 : 0

  # Older regions use a per-region ELB service account principal.
  statement {
    sid    = "AllowELBServiceAccount"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current[0].arn]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  # Newer regions deliver logs via the logdelivery service principal instead.
  # Including both keeps this module portable across every region.
  statement {
    sid    = "AllowLogDeliveryWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "AllowLogDeliveryAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.this.arn]
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count = var.enable_alb_access_logs_policy ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.alb_logs[0].json

  # The public access block must exist first, or attaching a policy can trip
  # the block-public-policy check during creation.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
