variable "name" {
  description = "Base name for the launch template and the instances it creates."
  type        = string
}

variable "ami_id" {
  description = "AMI to boot. The bundled user data expects Amazon Linux 2023 or Amazon Linux 2."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size, e.g. t3.micro."
  type        = string
  default     = "t3.micro"
}

variable "security_group_ids" {
  description = "Security groups attached to the instances. Supplied by the caller. Must allow inbound http_port from the ALB security group."
  type        = list(string)
}

variable "iam_instance_profile_name" {
  description = "Name of an IAM instance profile to attach. Created in the root module. Leave \"\" for none."
  type        = string
  default     = ""
}

variable "key_name" {
  description = "EC2 key pair name for SSH. Leave \"\" to launch without a key pair (use SSM Session Manager instead)."
  type        = string
  default     = ""
}

variable "http_port" {
  description = "Port Apache listens on. Must match the ALB target group's target_port."
  type        = number
  default     = 80
}

variable "page_title" {
  description = "Heading shown on the demo web page."
  type        = string
  default     = "Hello from Terraform"
}

variable "page_body" {
  description = "Paragraph shown on the demo web page."
  type        = string
  default     = "This EC2 instance is registered behind an Application Load Balancer."
}

variable "user_data_override" {
  description = "Raw shell script to use instead of the built-in one. Leave \"\" to use the built-in Apache script."
  type        = string
  default     = ""
}

variable "root_device_name" {
  description = "Root block device name. /dev/xvda for Amazon Linux."
  type        = string
  default     = "/dev/xvda"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Root EBS volume type."
  type        = string
  default     = "gp3"
}

variable "enable_detailed_monitoring" {
  description = "Turn on 1-minute CloudWatch metrics (costs extra)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the launch template and to launched instances and volumes."
  type        = map(string)
  default     = {}
}
