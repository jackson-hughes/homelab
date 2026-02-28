terraform {
  backend "s3" {
    bucket = "jhughes-tf-states"
    key    = "kvm/terraform.tfstate"
    region = "eu-west-2"
  }
}
