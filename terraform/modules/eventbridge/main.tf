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
# EVENT RULES (FIXED)
# ============================================================================

resource "aws_cloudwatch_event_rule" "rules" {
  for_each = var.rules

  name           = "${var.name_prefix}-${each.key}"
  description    = each.value.description
  event_bus_name = aws_cloudwatch_event_bus.main.name
  
  # FIXED: Merge logic to only include 'detail' if it is not empty
  event_pattern = jsonencode(merge(
    {
      source      = each.value.pattern.source
      detail-type = each.value.pattern["detail-type"]
    },
    # Only add 'detail' key if the object is not empty
    length(each.value.pattern.detail) > 0 ? { detail = each.value.pattern.detail } : {}
  ))

  tags = var.tags
}


resource "aws_cloudwatch_event_target" "targets" {
  for_each = var.rules

  rule           = aws_cloudwatch_event_rule.rules[each.key].name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "${each.key}-target"
  
  arn            = each.value.targets[0].arn
  
  # FIXED: Use try() to safely handle optional role_arn (it might be null)
  role_arn       = try(each.value.targets[0].role_arn, null)
  
  # FIXED: Add support for 'input' (it might be null)
  input          = try(each.value.targets[0].input, null)
}

# ============================================================================
# IAM ROLE FOR EVENTBRIDGE (KEPT AS IS)
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
# DEAD LETTER QUEUE (KEPT AS IS)
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
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

# ============================================================================
# LAMBDA PERMISSIONS FOR EVENTBRIDGE
# ============================================================================

# Create Lambda permissions for each rule that targets a Lambda function
resource "aws_lambda_permission" "eventbridge_invoke" {
  for_each = {
    for k, v in var.rules : k => v
    if can(regex("^arn:aws:lambda:", v.targets[0].arn))
  }

  statement_id  = "AllowEventBridgeInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.targets[0].arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rules[each.key].arn
}
