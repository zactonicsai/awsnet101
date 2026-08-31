############################################
# Copy this file to terraform.tfvars and edit the values.
#   cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars is loaded automatically by terraform plan/apply.
############################################

aws_region   = "us-east-1"
project_name = "demo"
environment  = "dev"

# ---- Network you already have (REQUIRED - no defaults) ----
vpc_id = "vpc-04771d1e932553432"

# ALB needs at least two subnets in two different AZs.
alb_subnet_ids = [
  "subnet-0be8924f152df5688", # us-east-1a
  "subnet-0c2beecd63abf62bd", # us-east-1b
]

# The single EC2 instance goes in one subnet.
instance_subnet_id = "subnet-0c2beecd63abf62bd"

# ---- Security groups you already have (REQUIRED) ----
# ALB SG: allow inbound TCP 80 from 0.0.0.0/0
alb_security_group_ids = ["sg-07175b2febb77143d"]

# Instance SG: allow inbound TCP 80 FROM the ALB security group above
instance_security_group_ids = ["sg-07175b2febb77143d"]

# ---- Instance ----
instance_type = "t3.micro"
ami_id        = "ami-000bcc17ad8504e18"
key_name      = ""

# ---- Ports ----
listener_port     = 80
app_port          = 80
health_check_path = "/health"

# ---- IAM ----
create_instance_profile = true
instance_managed_policy_arns = [
  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
]
instance_inline_policy_json = ""

# ---- Tags ----
tags = {
  Project   = "demo"
  ManagedBy = "terraform"
  Owner     = "platform-team"
}
