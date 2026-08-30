resource "aws_s3_bucket" "source" {
  count  = var.create_buckets ? 1 : 0
  bucket = local.source_bucket_name
}

resource "aws_s3_bucket" "dest" {
  count  = var.create_buckets ? 1 : 0
  bucket = local.dest_bucket_name
}

resource "aws_s3_bucket_public_access_block" "source" {
  count  = var.create_buckets ? 1 : 0
  bucket = aws_s3_bucket.source[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "dest" {
  count  = var.create_buckets ? 1 : 0
  bucket = aws_s3_bucket.dest[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  count  = var.create_buckets ? 1 : 0
  bucket = aws_s3_bucket.source[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dest" {
  count  = var.create_buckets ? 1 : 0
  bucket = aws_s3_bucket.dest[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "source" {
  count  = var.create_buckets ? 1 : 0
  bucket = aws_s3_bucket.source[0].id

  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "dest" {
  count  = var.create_buckets ? 1 : 0
  bucket = aws_s3_bucket.dest[0].id

  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}
