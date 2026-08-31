############################################
# Naming and region
############################################
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name. Used as a name prefix for every resource."
  type        = string
  default     = "demo"
}

variable "environment" {
  description = "Environment name such as dev, test, or prod. Used in resource names."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags applied to everything this configuration creates."
  type        = map(string)
  default     = {}
}

############################################
# Existing network - you supply these
############################################
variable "vpc_id" {
  description = "ID of the VPC that already exists, e.g. vpc-0abc123."
  type        = string
}

variable "alb_subnet_ids" {
  description = "Two or more public subnet IDs, in different Availability Zones, for the load balancer."
  type        = list(string)
}

variable "instance_subnet_id" {
  description = "Subnet ID the single EC2 instance is launched into. Must be in the same VPC as the ALB."
  type        = string
}

############################################
# Existing security groups - you supply these
############################################
variable "alb_security_group_ids" {
  description = "Security groups for the ALB. Should allow inbound listener_port from the internet (or from your office CIDR)."
  type        = list(string)
}

variable "instance_security_group_ids" {
  description = "Security groups for the EC2 instance. Should allow inbound app_port from the ALB security group."
  type        = list(string)
}

############################################
# Instance settings
############################################
variable "instance_type" {
  description = "EC2 size. t3.micro and t2.micro are the free-tier eligible micro sizes."
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID to use. Leave \"\" to auto-select the newest Amazon Linux 2023 AMI in the region."
  type        = string
  default     = ""
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH. Leave \"\" to skip SSH and use SSM Session Manager."
  type        = string
  default     = ""
}

############################################
# Ports and health check
############################################
variable "listener_port" {
  description = "Port the ALB accepts client traffic on."
  type        = number
  default     = 80
}

variable "app_port" {
  description = "Port the web server listens on. Used by the target group and by user data."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Path the ALB health check requests. The bundled user data serves both / and /health."
  type        = string
  default     = "/health"
}

############################################
# IAM - roles and policies live here in the root module
############################################
variable "create_instance_profile" {
  description = "Create an IAM role and instance profile for the EC2 instance. Set false to launch with no role."
  type        = bool
  default     = true
}

variable "instance_managed_policy_arns" {
  description = "AWS-managed or customer-managed policy ARNs to attach to the instance role."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}

variable "instance_inline_policy_json" {
  description = "Optional inline IAM policy document as a JSON string. Leave \"\" for none."
  type        = string
  default     = ""
}
