
# Top-level folder under an organization.
resource "google_folder" "project" {
  display_name = "${var.project_name}"
  parent       = "organizations/${var.organization_id}"
}

# Folder nested under another folder.
resource "google_folder" "dev-env" {
  display_name = "dev-${var.project_name}"
  parent       = google_folder.project.name
}

# Folder nested under another folder.
resource "google_folder" "prod-env" {
  display_name = "prod-${var.project_name}"
  parent       = google_folder.project.name
}

output "folder_ids" {
  value = {
    dev-env  = google_folder.dev-env.id
    prod-env = google_folder.prod-env.id
  }
}