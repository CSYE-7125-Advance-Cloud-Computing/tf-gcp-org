# Configure the gcp Provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.15.0"
    }
  }
}

provider "google" {
  credentials = file("key.json")
  region      = "us-east1"
}

