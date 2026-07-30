terraform {
  required_providers {
    ns = {
      source = "nullstone-io/ns"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 6.14"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
