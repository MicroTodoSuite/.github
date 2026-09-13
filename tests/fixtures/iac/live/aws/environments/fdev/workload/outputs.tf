# Outputs of the fdev workload root.
output "queue_arn" {
  description = "ARN of the events queue."
  value       = module.queue.queue_arn
}
