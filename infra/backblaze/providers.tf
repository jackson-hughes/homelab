# Credentials come from B2_APPLICATION_KEY_ID / B2_APPLICATION_KEY. The key
# must be account-wide: it creates buckets and other keys.
provider "b2" {}

# Desktop-app auth through the op CLI, so no token lives in code or state.
provider "onepassword" {
  account = "my.1password.com"
}
