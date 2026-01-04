# ============================================================================
# CORE VARIABLES (Shared Identity)
# ============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d{1}$", var.aws_region))
    error_message = "AWS region must be a valid AWS region format (e.g., us-east-1, eu-west-1)"
  }
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
  
  validation {
    condition     = can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "AWS Account ID must be a 12-digit number"
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "healthcare-imaging"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.project_name))
    error_message = "Project name must be 3-32 characters, lowercase alphanumeric and hyphens only"
  }
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
  description = "Owner email for tagging and notifications"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.owner_email))
    error_message = "Owner email must be a valid email address"
  }
}

variable "cost_center" {
  description = "Cost center for billing and allocation"
  type        = string
  default     = "engineering"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.cost_center))
    error_message = "Cost center must be 3-32 characters, lowercase alphanumeric and hyphens only"
  }
}

# ============================================================================
# LEGACY/OPTIONAL VARIABLES (Prevent breaking old references)
# ============================================================================

variable "domain_name" {
  description = "Legacy: Domain name for email ingestion (optional)"
  type        = string
  default     = ""
}

variable "bedrock_model_id" {
  description = "Legacy: Bedrock model ID for guardrails (optional)"
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20240620-v1:0"
}
