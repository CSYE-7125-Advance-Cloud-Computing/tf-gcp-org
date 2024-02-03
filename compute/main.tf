module "projects" {
  source            = "../projects"
  project_name      = var.project_name
  organization_id   = var.organization_id
  env               = var.env
  billing_account   = var.billing_account
}

resource "google_project_service" "google-api" {
  project                     = module.projects.project.project_id
  service                     = "iam.googleapis.com"
  disable_dependent_services  = true

  timeouts {
    create = "30m"
    update = "40m"
  }
}

resource "google_project_service" "cloud-billing" {
  project                     = module.projects.project.project_id
  service                     = "cloudbilling.googleapis.com"
  disable_dependent_services  = true

  timeouts {
    create = "30m"
    update = "40m"
  }

  depends_on = [google_project_service.google-api]
}

resource "google_service_account" "default" {
  account_id     = "my-custom-sa"
  display_name   = "Custom SA for VM Instance"
  project        = module.projects.project.project_id
}

resource "google_compute_instance" "default" {
  name         = "my-instance"
  machine_type = "n2-standard-2"
  zone         = "us-east1-a"  

  project      = module.projects.project.project_id

  tags = ["foo", "bar"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = "default"  

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    foo = "bar"
  }

  metadata_startup_script = "echo hi > /test.txt"

  service_account {
    email  = google_service_account.default.email
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_disk" "default" {
  name                     = "test-disk"
  type                     = "pd-standard"
  zone                     = "us-east1-a"  
  image                    = "debian-cloud/debian-11"
  project                  = module.projects.project.project_id
  labels                   = { environment = "dev" }
  physical_block_size_bytes = 4096
}

resource "google_compute_attached_disk" "default" {
  disk     = google_compute_disk.default.id
  instance = google_compute_instance.default.id
  project  = module.projects.project.project_id
}

resource "google_sql_database_instance" "main" {
  name             = "main-instance"
  database_version = "POSTGRES_15"
  region           = "us-east1-a"
  project         = module.projects.project.project_id
  settings {
    # Second-generation instance tiers are based on the machine
    # type. See argument reference below.
    tier = "db-f1-micro"
  }
}

resource "google_sql_database" "database" {
  name     = "my-database"
  instance = google_sql_database_instance.main.name
  project  = module.projects.project.project_id
}