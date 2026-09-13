# Name construction for the queue sample.
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  queue = {
    name                      = "${local.governance_prefix}-sqs-events"
    message_retention_seconds = 345600
  }
}
