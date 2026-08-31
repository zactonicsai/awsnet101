output "alb_arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer. Open this in a browser."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB, for alias records."
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group. Pass this to aws_lb_target_group_attachment or an ASG."
  value       = aws_lb_target_group.this.arn
}

output "target_group_name" {
  description = "Name of the target group."
  value       = aws_lb_target_group.this.name
}

output "listener_arn" {
  description = "ARN of the HTTP listener."
  value       = aws_lb_listener.http.arn
}
