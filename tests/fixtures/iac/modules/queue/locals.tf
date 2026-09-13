# Local values of the queue module: governance tags merged with the queue's name.
locals {
  governance_tags = {
    Client      = var.client
    Project     = var.project
    Environment = var.environment
  }

  tags = merge(local.governance_tags, { Name = var.queue.name }, var.additional_tags)
}
