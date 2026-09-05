terraform {
  backend "s3" {
    bucket = "jhughes-tf-states"
    key    = "aws/terraform.tfstate"
    region = "eu-west-2"
  }
}
