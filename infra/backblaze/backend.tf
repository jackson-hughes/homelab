terraform {
  backend "s3" {
    bucket       = "jhughes-tf-states"
    key          = "backblaze/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
