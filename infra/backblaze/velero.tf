data "b2_account_info" "this" {}

data "onepassword_vault" "homelab" {
  name = "Homelab"
}

resource "b2_bucket" "backups" {
  bucket_name = "homelab-backups"
  bucket_type = "allPrivate"

  lifecycle_rules {
    file_name_prefix                                       = ""
    days_from_hiding_to_deleting                           = 1
    days_from_starting_to_canceling_unfinished_large_files = 7
  }
}

resource "b2_application_key" "velero" {
  key_name   = "velero-helios"
  bucket_ids = [b2_bucket.backups.bucket_id]
  capabilities = [
    "listAllBucketNames",
    "listBuckets",
    "listFiles",
    "readFiles",
    "writeFiles",
    "deleteFiles",
  ]
}

ephemeral "random_password" "velero_repository" {
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
  vault               = data.onepassword_vault.homelab.uuid
  title               = "velero-repo-password"
  category            = "password"
  password_wo         = ephemeral.random_password.velero_repository.result
  password_wo_version = 1
}
