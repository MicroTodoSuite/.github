# Inputs of the queue module.
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

variable "queue" {
  type = object({
    name                      = string
    message_retention_seconds = number
  })
  description = "Name of the queue, built by the root, and its message retention in seconds."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,80}$", var.queue.name))
    error_message = "The queue name must be 1 to 80 lowercase letters, digits, or hyphens."
  }

  validation {
    condition     = var.queue.message_retention_seconds >= 60 && var.queue.message_retention_seconds <= 1209600
    error_message = "The retention must be between 60 and 1209600 seconds."
  }
}

variable "additional_tags" {
  type        = map(string)
  description = "Tags added to the queue besides Name and the provider's default tags."
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.additional_tags) : length(key) > 0])
    error_message = "Tag keys must not be empty."
  }
}
