# ============================================================================
# MONITORING MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "log_group_names" {
  description = "Names of CloudWatch log groups"
  value = {
    application   = aws_cloudwatch_log_group.application.name
    sagemaker     = aws_cloudwatch_log_group.sagemaker.name
    healthimaging = aws_cloudwatch_log_group.healthimaging.name
  }
}

output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = aws_sns_topic.alerts.arn
}

output "alarm_arns" {
  description = "ARNs of CloudWatch alarms"
  value = {
    lambda_errors       = aws_cloudwatch_metric_alarm.lambda_errors.arn
    pipeline_failures   = aws_cloudwatch_metric_alarm.pipeline_failures.arn
    dynamodb_throttling = aws_cloudwatch_metric_alarm.dynamodb_throttling.arn
  }
}
