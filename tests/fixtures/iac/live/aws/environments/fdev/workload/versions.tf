# Terraform, provider, and backend requirements of the fdev workload root.
terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.64.0"
    }
  }

  backend "s3" {}
}
