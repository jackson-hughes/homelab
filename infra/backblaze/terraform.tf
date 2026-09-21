terraform {
  required_version = "~> 1.13"

  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "0.14.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "3.3.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}
