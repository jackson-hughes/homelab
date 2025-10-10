resource "aws_s3_bucket" "backups" {
  bucket = "jhughes-backups"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.backups.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "glacier"
    enabled = "true"

    prefix = "*"

    transition {
      days          = 7
      storage_class = "GLACIER"
    }

    transition {
      days          = 97
      storage_class = "DEEP_ARCHIVE"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
