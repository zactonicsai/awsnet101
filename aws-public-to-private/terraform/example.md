# Example out
```
alb_dns_name = "web-demo-alb-1232667067.us-east-1.elb.amazonaws.com"
check_target_health_command = "aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:us-east-1:406207085797:targetgroup/web-demo-tg/5765e1fa8c24e630 --region us-east-1"
estimated_monthly_cost_usd = "ALB ~$16.20 + EC2 1 x ~$3.07 + EBS 1 x ~$0.64 + Route53 $0.00 = ~$19.91/month if left running 24/7"
instance_private_ips = [
  "10.0.10.32",
]
ping_url = "http://web-demo-alb-1232667067.us-east-1.elb.amazonaws.com/ping"
private_subnet_ids = [
  "subnet-074ff0d3aff88a87c",
  "subnet-09f84b15c6ae252d8",
]
public_subnet_ids = [
  "subnet-049d45d8531cbde95",
  "subnet-048448fa0bda1e071",
]
test_command = "curl -i http://web-demo-alb-1232667067.us-east-1.elb.amazonaws.com"
vpc_id = "vpc-024df46db3e2b76ef"
website_url = "http://web-demo-alb-1232667067.us-east-1.elb.amazonaws.com"
```