data "b2_account_info" "this" {}

data "onepassword_vault" "homelab" {
  name = "Homelab"
}

resource "b2_bucket" "backups" {
  bucket_name = "homelab-backups"
  bucket_type = "allPrivate"

  # Kopia keeps its own history. B2's default keeps every hidden version
  # forever, so without this every blob Kopia deletes is billed indefinitely.
  lifecycle_rules {
    file_name_prefix                                       = ""
    days_from_hiding_to_deleting                           = 1
    days_from_starting_to_canceling_unfinished_large_files = 7
  }
}

resource "b2_application_key" "velero" {
  key_name   = "velero-helios"
  bucket_ids = [b2_bucket.backups.bucket_id]
  # listAllBucketNames is how the S3 API resolves a bucket-restricted key.
  capabilities = [
    "listAllBucketNames",
    "listBuckets",
    "listFiles",
    "readFiles",
    "writeFiles",
    "deleteFiles",
  ]
}

# Velero seeds its Kopia repository password from a Secret at first backup and
# the repository cannot be re-keyed afterwards, so the value must outlive the
# cluster.
resource "random_password" "velero_repository" {
  length  = 64
  special = false
}

resource "onepassword_item" "velero_b2" {
  vault    = data.onepassword_vault.homelab.uuid
  title    = "velero-b2"
  category = "login"
  url      = data.b2_account_info.this.s3_api_url
  username = b2_application_key.velero.application_key_id
  password = b2_application_key.velero.application_key # gitleaks:allow
}

resource "onepassword_item" "velero_repository_password" {
  vault    = data.onepassword_vault.homelab.uuid
  title    = "velero-repo-password"
  category = "password"
  password = random_password.velero_repository.result
}
