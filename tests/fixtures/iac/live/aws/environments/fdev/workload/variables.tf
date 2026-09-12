# Inputs of the fdev workload root, supplied by the environment's .tfvars.
variable "client" {
  type        = string
  description = "Client code, from MTS-IAC-101."

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.client))
    error_message = "The client code must be 2 to 10 lowercase letters or digits."
  }
}

variable "project" {
  type        = string
  description = "Project code, from MTS-IAC-101."

  validation {
    condition     = can(regex("^[a-z0-9]{2,15}$", var.project))
    error_message = "The project code must be 2 to 15 lowercase letters or digits."
  }
}

variable "environment" {
  type        = string
  description = "Environment code, from MTS-IAC-101."

  validation {
    condition     = contains(["shd", "eco", "fdev", "fstg", "fprd"], var.environment)
    error_message = "The environment must be one of shd, eco, fdev, fstg, or fprd."
  }
}

variable "region" {
  type        = string
  description = "AWS region of the environment."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "The region must be an AWS region code."
  }
}

variable "aws_account_id" {
  type        = string
  description = "The AWS account declared in config/aws-account.env."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "The account ID must be twelve digits."
  }
}

variable "deploy_role_arn" {
  type        = string
  description = "Role the provider assumes; empty when the caller already holds it."

  validation {
    condition     = var.deploy_role_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:role/", var.deploy_role_arn))
    error_message = "The deploy role must be empty or an IAM role ARN."
  }
}

variable "queue_retention_seconds" {
  type        = number
  description = "Message retention of the events queue, in seconds."

  validation {
    condition     = var.queue_retention_seconds >= 60 && var.queue_retention_seconds <= 1209600
    error_message = "The retention must be between 60 and 1209600 seconds."
  }
}
