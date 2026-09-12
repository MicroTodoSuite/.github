# The workload of the fdev environment.
module "queue" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//queue?ref=queue-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client          = var.client
  project         = var.project
  environment     = var.environment
  queue           = local.queue
  additional_tags = {}
}
