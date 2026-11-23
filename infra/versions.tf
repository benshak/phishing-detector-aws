# Terraform and provider versions, and the AWS region to work in.

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Creates the AWS resources (VPC, EC2, ALB, RDS, CloudWatch).
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Packs the server setup (app files + install script) into EC2 user data.
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Every resource gets these tags, so it is easy to find (and verify it was destroyed).
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
