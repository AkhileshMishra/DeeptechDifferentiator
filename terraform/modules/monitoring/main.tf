# ============================================================================
# MONITORING MODULE
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/${var.name_prefix}/application"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "sagemaker" {
  name              = "/aws/${var.name_prefix}/sagemaker"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "healthimaging" {
  name              = "/aws/${var.name_prefix}/healthimaging"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# ============================================================================
# CLOUDWATCH DASHBOARD
# ============================================================================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Invocations"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.name_prefix}-image-ingestion"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.name_prefix}-pipeline-trigger"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.name_prefix}-model-evaluation"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.name_prefix}-model-registry"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", "${var.name_prefix}-image-ingestion"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.name_prefix}-pipeline-trigger"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.name_prefix}-model-evaluation"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.name_prefix}-model-registry"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "SageMaker Pipeline Executions"
          region = var.aws_region
          metrics = [
            ["AWS/SageMaker", "PipelineExecutionCount", "PipelineName", "${var.name_prefix}-pneumonia-pipeline"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB Read/Write Capacity"
          region = var.aws_region
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "${var.name_prefix}-image-metadata"],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "${var.name_prefix}-image-metadata"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title  = "S3 Bucket Size"
          region = var.aws_region
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", var.training_data_bucket, "StorageType", "StandardStorage"],
            ["AWS/S3", "BucketSizeBytes", "BucketName", var.model_artifacts_bucket, "StorageType", "StandardStorage"]
          ]
          period = 86400
          stat   = "Average"
        }
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda function errors exceeded threshold"
  alarm_actions       = var.alarm_actions

  dimensions = {
    FunctionName = "${var.name_prefix}-image-ingestion"
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "pipeline_failures" {
  alarm_name          = "${var.name_prefix}-pipeline-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PipelineExecutionFailed"
  namespace           = "AWS/SageMaker"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "SageMaker pipeline execution failed"
  alarm_actions       = var.alarm_actions

  dimensions = {
    PipelineName = "${var.name_prefix}-pneumonia-pipeline"
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttling" {
  alarm_name          = "${var.name_prefix}-dynamodb-throttling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB throttling detected"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = "${var.name_prefix}-image-metadata"
  }

  tags = var.tags
}

# ============================================================================
# SNS TOPIC FOR ALERTS
# ============================================================================

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
