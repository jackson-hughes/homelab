# The bucket itself belongs to state-setup/, a bootstrap root with no remote
# state, so it is referenced by name rather than managed here. Its public access
# block and policy are owned here only: adding them in state-setup/ too would
# make the two roots fight over them.
locals {
  state_bucket = "jhughes-tf-states"
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = local.state_bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${local.state_bucket}",
      "arn:aws:s3:::${local.state_bucket}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = local.state_bucket
  policy = data.aws_iam_policy_document.state_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
