module "folders" {
  source = "../folders"
  organization_id = "${var.organization_id}"
  project_name = "${var.project_name}"
}

resource "random_uuid" "uuid" {}

data "google_billing_account" "acct" {
  billing_account = "${var.billing_account}"
  open         = true
}

resource "google_project" "my_project-in-a-folder" {
  name       = "proj-${var.project_name}"
  project_id = "proj-${var.project_name}-${substr(random_uuid.uuid.result, 0, 8)}"
  folder_id  = module.folders.folder_ids["${var.env}-env"]

  billing_account = data.google_billing_account.acct.billing_account

}

output "project" {
  value = {
    project_id  = google_project.my_project-in-a-folder.id
  }
}

