terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "poc-security"

  default_tags {
    tags = {
      Project     = "poc-aws-security"
      Environment = "security"
      ManagedBy   = "terraform"
    }
  }
}
