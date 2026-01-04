bucket         = "terraform-state-healthcare-imaging-staging"
key            = "staging/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "terraform-locks"
encrypt        = true
