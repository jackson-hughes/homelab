resource "aws_kms_key" "backups" {
  description         = "Backup KMS key"
  enable_key_rotation = true

  lifecycle {
    prevent_destroy = true
  }
}
