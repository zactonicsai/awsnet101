terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # For real work, keep state in S3 instead of on your laptop.
  # Uncomment and fill in, then run: terraform init -migrate-state
  #
  # backend "s3" {
  #   bucket       = "my-terraform-state-bucket"
  #   key          = "alb-ec2-demo/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
