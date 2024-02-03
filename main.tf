module "compute" {
  source          = "./compute"
  project_name    = var.project_name
  organization_id = var.organization_id
  env             = var.env
  billing_account = var.billing_account

}

module "network" {
  source       = "./network"
  project_name = var.project_name

}

