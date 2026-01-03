# ============================================================================
# ECR MODULE - VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "repositories" {
  description = "List of repository names to create"
  type        = list(string)
  default     = ["preprocessing", "training", "evaluation", "inference", "api"]
}

variable "image_scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "image_retention_days" {
  description = "Days to retain untagged images"
  type        = number
  default     = 30
}

variable "max_image_count" {
  description = "Maximum number of images to retain"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
