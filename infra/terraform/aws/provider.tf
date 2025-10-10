terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

terraform {
  backend "s3" {
    bucket = "jhughes-tf-states"
    key    = "aws/terraform.tfstate"
    region = "eu-west-2"
  }
}
