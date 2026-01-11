# ============================================================================
# HEALTHIMAGING CLOUDFRONT PROXY WITH FARGATE
# Architecture: CloudFront → Lambda@Edge (JWT) → ALB → Fargate → HealthImaging
# Based on AWS samples: amazon-cloudfront-delivery
# ============================================================================

# ============================================================================
# VPC CONFIGURATION
# ============================================================================

resource "aws_vpc" "healthimaging" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-vpc"
  }
}

resource "aws_internet_gateway" "healthimaging" {
  vpc_id = aws_vpc.healthimaging.id
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-igw"
  }
}

resource "aws_subnet" "healthimaging_public" {
  count                   = 2
  vpc_id                  = aws_vpc.healthimaging.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-public-${count.index + 1}"
  }
}

resource "aws_route_table" "healthimaging_public" {
  vpc_id = aws_vpc.healthimaging.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.healthimaging.id
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-rt"
  }
}

resource "aws_route_table_association" "healthimaging_public" {
  count          = 2
  subnet_id      = aws_subnet.healthimaging_public[count.index].id
  route_table_id = aws_route_table.healthimaging_public.id
}

# ============================================================================
# SECURITY GROUPS
# ============================================================================

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-hi-alb-sg"
  description = "Security group for HealthImaging ALB"
  vpc_id      = aws_vpc.healthimaging.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from CloudFront"
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from CloudFront"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-alb-sg"
  }
}

resource "aws_security_group" "fargate" {
  name        = "${var.project_name}-${var.environment}-hi-fargate-sg"
  description = "Security group for HealthImaging Fargate tasks"
  vpc_id      = aws_vpc.healthimaging.id
  
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Traffic from ALB"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-fargate-sg"
  }
}

# ============================================================================
# APPLICATION LOAD BALANCER
# ============================================================================

resource "aws_lb" "healthimaging" {
  name               = "${var.project_name}-${var.environment}-hi-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.healthimaging_public[*].id
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-alb"
  }
}

resource "aws_lb_target_group" "healthimaging" {
  name        = "${var.project_name}-${var.environment}-hi-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.healthimaging.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-tg"
  }
}

resource "aws_lb_listener" "healthimaging" {
  load_balancer_arn = aws_lb.healthimaging.arn
  port              = 80
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.healthimaging.arn
  }
}

# ============================================================================
# ECR REPOSITORY
# ============================================================================

resource "aws_ecr_repository" "healthimaging_proxy" {
  name                 = "${var.project_name}-${var.environment}-hi-proxy"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-proxy"
  }
}

# ============================================================================
# ECS CLUSTER AND SERVICE
# ============================================================================

resource "aws_ecs_cluster" "healthimaging" {
  name = "${var.project_name}-${var.environment}-hi-cluster"
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-cluster"
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-${var.environment}-hi-task-exec"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-${var.environment}-hi-task"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_healthimaging" {
  name = "${var.project_name}-${var.environment}-hi-task-policy"
  role = aws_iam_role.ecs_task.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "medical-imaging:GetImageFrame",
          "medical-imaging:GetImageSetMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "healthimaging_proxy" {
  name              = "/ecs/${var.project_name}-${var.environment}-hi-proxy"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "healthimaging_proxy" {
  family                   = "${var.project_name}-${var.environment}-hi-proxy"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  
  container_definitions = jsonencode([{
    name  = "proxy"
    image = "${aws_ecr_repository.healthimaging_proxy.repository_url}:latest"
    
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "PORT", value = "8080" }
    ]
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.healthimaging_proxy.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "proxy"
      }
    }
    
    healthCheck = {
      command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-proxy"
  }
}

resource "aws_ecs_service" "healthimaging_proxy" {
  name            = "${var.project_name}-${var.environment}-hi-proxy"
  cluster         = aws_ecs_cluster.healthimaging.id
  task_definition = aws_ecs_task_definition.healthimaging_proxy.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = aws_subnet.healthimaging_public[*].id
    security_groups  = [aws_security_group.fargate.id]
    assign_public_ip = true
  }
  
  load_balancer {
    target_group_arn = aws_lb_target_group.healthimaging.arn
    container_name   = "proxy"
    container_port   = 8080
  }
  
  depends_on = [aws_lb_listener.healthimaging]
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-proxy"
  }
}

# ============================================================================
# LAMBDA@EDGE FOR JWT AUTH
# ============================================================================

resource "aws_iam_role" "jwt_auth_edge" {
  name = "${var.project_name}-${var.environment}-hi-jwt-edge"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = [
          "lambda.amazonaws.com",
          "edgelambda.amazonaws.com"
        ]
      }
    }]
  })
}

resource "aws_iam_role_policy" "jwt_auth_edge" {
  name = "${var.project_name}-${var.environment}-hi-jwt-edge-policy"
  role = aws_iam_role.jwt_auth_edge.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

# Template the JWT auth Lambda with Cognito config
resource "local_file" "jwt_auth_lambda" {
  content = templatefile("${path.module}/../lambda_edge/jwt_auth/index.js", {
    cognito_region       = var.aws_region
    cognito_user_pool_id = module.cognito.user_pool_id
    cognito_client_id    = module.cognito.user_pool_client_id
  })
  filename = "${path.module}/lambda_edge_build/jwt_auth/index.js"
}

data "archive_file" "jwt_auth_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_edge_build/jwt_auth"
  output_path = "${path.module}/lambda_zips/jwt_auth.zip"
  
  depends_on = [local_file.jwt_auth_lambda]
}

resource "aws_lambda_function" "jwt_auth" {
  filename         = data.archive_file.jwt_auth_zip.output_path
  function_name    = "${var.project_name}-${var.environment}-hi-jwt-auth"
  role             = aws_iam_role.jwt_auth_edge.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.jwt_auth_zip.output_base64sha256
  runtime          = "nodejs18.x"
  timeout          = 5
  memory_size      = 128
  publish          = true
  
  provider = aws
}

# ============================================================================
# CLOUDFRONT DISTRIBUTION
# ============================================================================

resource "aws_cloudfront_cache_policy" "healthimaging" {
  name        = "${var.project_name}-${var.environment}-hi-cache"
  comment     = "Cache policy for HealthImaging frames"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 86400
  
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

resource "aws_cloudfront_origin_request_policy" "healthimaging" {
  name    = "${var.project_name}-${var.environment}-hi-origin"
  comment = "Origin request policy for HealthImaging"
  
  cookies_config {
    cookie_behavior = "none"
  }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["X-User-Sub", "X-User-Email"]
    }
  }
  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudfront_response_headers_policy" "healthimaging" {
  name    = "${var.project_name}-${var.environment}-hi-cors"
  comment = "CORS headers for HealthImaging proxy"
  
  cors_config {
    access_control_allow_credentials = false
    access_control_max_age_sec       = 86400
    origin_override                  = true
    
    access_control_allow_headers {
      items = ["*"]
    }
    access_control_allow_methods {
      items = ["GET", "POST", "OPTIONS"]
    }
    access_control_allow_origins {
      items = ["*"]
    }
    access_control_expose_headers {
      items = ["Content-Length", "Content-Type"]
    }
  }
}

resource "aws_cloudfront_distribution" "healthimaging_proxy" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name} HealthImaging Proxy (Fargate)"
  price_class     = "PriceClass_100"
  
  origin {
    domain_name = aws_lb.healthimaging.dns_name
    origin_id   = "alb"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "alb"
    
    cache_policy_id            = aws_cloudfront_cache_policy.healthimaging.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.healthimaging.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.healthimaging.id
    
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    
    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = aws_lambda_function.jwt_auth.qualified_arn
      include_body = false
    }
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-hi-proxy"
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "healthimaging_proxy_url" {
  description = "CloudFront URL for HealthImaging proxy"
  value       = "https://${aws_cloudfront_distribution.healthimaging_proxy.domain_name}"
}

output "healthimaging_proxy_distribution_id" {
  description = "CloudFront distribution ID for HealthImaging proxy"
  value       = aws_cloudfront_distribution.healthimaging_proxy.id
}

output "healthimaging_ecr_repository_url" {
  description = "ECR repository URL for HealthImaging proxy container"
  value       = aws_ecr_repository.healthimaging_proxy.repository_url
}

output "healthimaging_alb_dns" {
  description = "ALB DNS name for HealthImaging proxy"
  value       = aws_lb.healthimaging.dns_name
}


output "healthimaging_cluster_name" {
  description = "ECS cluster name for HealthImaging proxy"
  value       = aws_ecs_cluster.healthimaging.name
}

output "healthimaging_service_name" {
  description = "ECS service name for HealthImaging proxy"
  value       = aws_ecs_service.healthimaging_proxy.name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}
