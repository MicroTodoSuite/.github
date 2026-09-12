# Names, tags, and module configuration of the fdev workload root.
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  common_tags = {
    Client      = var.client
    Project     = var.project
    Environment = var.environment
    Owner       = "infrastructure"
    CostCenter  = "mts-full"
    ManagedBy   = "terraform"
    Repository  = "microservice-app-ops"
  }

  queue = {
    name                      = "${local.governance_prefix}-sqs-events"
    message_retention_seconds = var.queue_retention_seconds
  }
}
