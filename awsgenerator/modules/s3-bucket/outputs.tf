output "bucket_id" {
  description = "Bucket name. Pass to the alb module as access_logs_bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Bucket ARN. Reference it in IAM policies granting workloads access."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Global bucket domain name."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name. Use this one as a CloudFront origin."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
