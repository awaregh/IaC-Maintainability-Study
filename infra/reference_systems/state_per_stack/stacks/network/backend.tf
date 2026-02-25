terraform {
  backend "s3" {
    bucket         = "iac-study-tfstate"
    key            = "state-per-stack/network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "iac-study-tfstate-lock"
    encrypt        = true
  }
}
