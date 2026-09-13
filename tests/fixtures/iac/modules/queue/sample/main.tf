# The queue sample: one call of the module, fed from locals.
module "queue" {
  source = "../"

  providers = {
    aws.project = aws.principal
  }

  client      = var.client
  project     = var.project
  environment = var.environment
  queue       = local.queue
}
