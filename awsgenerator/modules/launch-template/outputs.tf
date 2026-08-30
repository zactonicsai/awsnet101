output "launch_template_id" {
  description = "Launch template ID. Pass this to the asg module."
  value       = aws_launch_template.this.id
}

output "launch_template_arn" {
  description = "Launch template ARN."
  value       = aws_launch_template.this.arn
}

output "launch_template_name" {
  description = "Generated name including the random suffix."
  value       = aws_launch_template.this.name
}

output "latest_version" {
  description = <<-EOT
    Version number of the template as of this apply.

    Pass this to the ASG when you want a script change to trigger an instance
    refresh. Using the literal "$Latest" instead means the ASG silently picks up
    new versions without Terraform showing a diff -- convenient, but it hides
    changes from `terraform plan`, which is usually the wrong trade.
  EOT
  value       = aws_launch_template.this.latest_version
}

output "image_id" {
  description = "The AMI actually used, whether supplied or auto-resolved."
  value       = aws_launch_template.this.image_id
}

output "user_data_rendered" {
  description = "The bootstrap script after template substitution, before encoding. Useful for debugging with `terraform console`."
  value       = local.rendered_user_data
  sensitive   = true
}
