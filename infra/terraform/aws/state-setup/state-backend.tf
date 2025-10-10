provider "aws" {
  region = "eu-west-2"
}

resource "aws_s3_bucket" "state" {
  bucket = "jhughes-tf-states"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
