# =============================================================================
# versions.tf
# -----------------------------------------------------------------------------
# WHAT THIS FILE DOES (plain English):
# Terraform is a program that reads ".tf" files and builds real cloud resources.
# This file tells Terraform two things:
#   1. Which version of Terraform itself is allowed to run this project.
#   2. Which "provider" plugin to download. A provider is the translator that
#      turns our text into real AWS API calls.
# Pinning versions is a BEST PRACTICE: it means the project still builds the
# same way next year, instead of silently breaking when AWS ships a new plugin.
# =============================================================================

terraform {
  # ">= 1.9.0" means: use Terraform 1.9 or anything newer.
  # 1.9 is the first version with the `terraform test` + input validation
  # features we rely on, so older versions are refused up front.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      # "hashicorp/aws" is the official AWS provider from the public registry.
      source = "hashicorp/aws"

      # "~> 6.0" is called a pessimistic constraint. It means:
      #   allow 6.1, 6.2, 6.99...  but NEVER jump to 7.0 automatically.
      # Major version bumps (6 -> 7) can remove arguments and break the build,
      # so we opt in to those on purpose, never by accident.
      version = "~> 6.0"
    }
  }
}

# The provider block configures the plugin we just downloaded.
provider "aws" {
  # Which AWS region to build in. Comes from variables.tf so you can change it
  # in one place instead of hunting through every file.
  region = var.aws_region

  # default_tags automatically stamps EVERY resource this provider creates with
  # these labels. This is one of the highest-value AWS habits you can build:
  #   - You can find all your stuff later.
  #   - You can see exactly what this project costs in Cost Explorer.
  #   - You can safely delete everything, because nothing is unlabeled.
  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}
