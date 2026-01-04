# ============================================================================
# CORE VARIABLES (Shared Identity)
# ============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "healthcare-imaging"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be one of: dev, staging, prod"
  }
}

variable "owner_email" {
  description = "Owner email for tagging"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# Legacy/Optional placeholders to prevent breaking old references
variable "domain_name" { default = "" }
variable "bedrock_model_id" { default = "" }
