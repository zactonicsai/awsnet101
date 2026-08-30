terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    # Only needed when generate_password = true. The random provider stores the
    # generated value in state -- which is why state must be treated as secret.
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}
