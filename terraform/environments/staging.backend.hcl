bucket         = "terraform-state-healthcare-imaging"
key            = "healthcare-imaging/staging/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "terraform-locks"
encrypt        = true
