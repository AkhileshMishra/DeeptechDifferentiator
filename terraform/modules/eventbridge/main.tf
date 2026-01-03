# ============================================================================
# EVENTBRIDGE MODULE
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# CUSTOM EVENT BUS
# ============================================================================

resource "aws_cloudwatch_event_bus" "main" {
  name = var.event_bus_name

  tags = var.tags
}

# ============================================================================
# EVENT RULES
# ============================================================================

resource "aws_cloudwatch_event_rule" "rules" {
  for_each = var.rules

  name           = "${var.name_prefix}-${each.key}"
  description    = each.value.description
  event_bus_name = aws_cloudwatch_event_bus.main.name
  event_pattern  = jsonencode(each.value.pattern)

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "targets" {
  for_each = var.rules

  rule           = aws_cloudwatch_event_rule.rules[each.key].name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "${each.key}-target"
  arn            = each.value.targets[0].arn
  role_arn       = each.value.targets[0].role_arn
}

# ============================================================================
# IAM ROLE FOR EVENTBRIDGE
# ============================================================================

resource "aws_iam_role" "eventbridge_invoke" {
  name = "${var.name_prefix}-eventbridge-invoke-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "eventbridge_invoke" {
  name = "${var.name_prefix}-eventbridge-invoke-policy"
  role = aws_iam_role.eventbridge_invoke.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sagemaker:StartPipelineExecution"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# DEAD LETTER QUEUE
# ============================================================================

resource "aws_sqs_queue" "dlq" {
  name = "${var.name_prefix}-eventbridge-dlq"

  message_retention_seconds = 1209600  # 14 days

  tags = var.tags
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}
