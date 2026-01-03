# ============================================================================
# EVENTBRIDGE MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "event_bus_arn" {
  description = "ARN of the custom event bus"
  value       = aws_cloudwatch_event_bus.main.arn
}

output "event_bus_name" {
  description = "Name of the custom event bus"
  value       = aws_cloudwatch_event_bus.main.name
}

output "event_rule_arns" {
  description = "ARNs of event rules"
  value       = { for k, v in aws_cloudwatch_event_rule.rules : k => v.arn }
}

output "eventbridge_invoke_role_arn" {
  description = "ARN of the EventBridge invoke role"
  value       = aws_iam_role.eventbridge_invoke.arn
}

output "dlq_arn" {
  description = "ARN of the dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}
