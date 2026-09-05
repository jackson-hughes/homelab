output "bucket_name" {
  value = b2_bucket.backups.bucket_name
}

output "s3_api_url" {
  value = data.b2_account_info.this.s3_api_url
}
