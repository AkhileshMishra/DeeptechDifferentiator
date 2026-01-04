bucket         = "terraform-state-healthcare-imaging-prod"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "terraform-locks"
encrypt        = true
