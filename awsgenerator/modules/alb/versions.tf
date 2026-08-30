# Every module pins the same floor. Modules deliberately do NOT declare a
# `provider "aws"` block -- that is the ROOT module's job. A module that
# configures its own provider cannot be used with multiple regions or
# accounts, and cannot be consumed by other modules. This is the single most
# important rule for writing reusable Terraform.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
