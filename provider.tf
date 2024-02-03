# Configure the gcp Provider
provider "google" {
  credentials = file("key.json")
}