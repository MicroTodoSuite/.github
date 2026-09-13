# Outputs that prove the sample works.
output "queue_arn" {
  description = "ARN of the sample queue."
  value       = module.queue.queue_arn
}
