locals {
  name = var.name_prefix

  generated_source_bucket = "${local.name}-src-${random_id.suffix.hex}"
  generated_dest_bucket   = "${local.name}-dst-${random_id.suffix.hex}"

  source_bucket_name = var.source_bucket_name != "" ? var.source_bucket_name : local.generated_source_bucket
  dest_bucket_name   = var.dest_bucket_name != "" ? var.dest_bucket_name : local.generated_dest_bucket

  lambda_name = "${local.name}-worker"

  visibility_timeout = var.lambda_timeout * 6
}

resource "random_id" "suffix" {
  byte_length = 4
}
