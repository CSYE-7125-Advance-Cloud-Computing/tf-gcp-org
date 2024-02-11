resource "google_folder" "project" {
  display_name = var.project_name
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

resource "random_uuid" "uuid" {}

data "google_billing_account" "acct" {
  billing_account = var.billing_account
  open            = true
}

resource "google_project" "my_project-in-a-folder" {
  name            = "proj-${var.project_name}"
  project_id      = "proj-${var.project_name}-${substr(random_uuid.uuid.result, 0, 8)}"
  folder_id       = google_folder.dev-env.id
  billing_account = data.google_billing_account.acct.billing_account
}

# Define a map with service names and their corresponding API URLs
variable "service_names" {
  type = map(string)
  default = {
    "iam"           = "iam.googleapis.com"
    "cloud-billing" = "cloudbilling.googleapis.com"
    "compute"       = "compute.googleapis.com"
    "container"     = "container.googleapis.com"
  }
}

# Create Google project services using a for_each loop
resource "google_project_service" "services" {
  for_each = var.service_names

  project                    = google_project.my_project-in-a-folder.project_id
  service                    = each.value
  disable_dependent_services = true

  timeouts {
    create = "30m"
    update = "40m"
  }
}

resource "google_compute_network" "vpc_network" {
  name                            = "vpc-network"
  project                         = google_project.my_project-in-a-folder.project_id
  routing_mode                    = "REGIONAL"
  auto_create_subnetworks         = "false"
  mtu                             = 1460
  delete_default_routes_on_create = "true"

  depends_on = [
    google_project_service.services["compute"],
    google_project_service.services["container"]
  ]
}


resource "google_compute_subnetwork" "private" {
  name                     = "private"
  project                  = google_project.my_project-in-a-folder.project_id
  ip_cidr_range            = "10.0.0.0/18"
  region                   = "us-east1"
  network                  = google_compute_network.vpc_network.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "k8s-pods-range"
    ip_cidr_range = "10.48.0.0/14"
  }

  secondary_ip_range {
    range_name    = "k8s-services-range"
    ip_cidr_range = "10.52.0.0/20"
  }
}

resource "google_compute_router" "router" {
  name    = "router"
  project = google_project.my_project-in-a-folder.project_id
  region  = "us-east1"
  network = google_compute_network.vpc_network.id
}

resource "google_compute_router_nat" "nat" {
  name    = "nat"
  project = google_project.my_project-in-a-folder.project_id
  router  = google_compute_router.router.name
  region  = "us-east1"

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  nat_ip_allocate_option             = "MANUAL_ONLY"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  nat_ips = [google_compute_address.nat.self_link]
}

resource "google_compute_address" "nat" {
  name         = "nat"
  project      = google_project.my_project-in-a-folder.project_id
  region       = "us-east1"
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  depends_on = [
    google_project_service.services["compute"]
  ]

}


resource "google_compute_firewall" "allow-ssh" {
  name = "allow-ssh"

  network = google_compute_network.vpc_network.name
  project = google_project.my_project-in-a-folder.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]

}

# resource "google_project_organization_policy" "constraint" {
#   project = google_project.my_project-in-a-folder.project_id

#   constraint = "constraints/compute.vmExternalIpAccess"

#   boolean_policy {
#     enforced = false
#   }

# }


resource "google_compute_instance" "vm_instance" {
  name         = "my-vm-instance"
  project      = google_project.my_project-in-a-folder.project_id
  machine_type = "n2-standard-2"
  zone         = "us-east1-b"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    access_config {
      // Include this block if you want to give the VM a public IP
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_key}"
  }

  depends_on = [
    google_compute_subnetwork.private
  ]
}

resource "google_container_cluster" "gke-cluster" {
  name                     = "gke-cluster"
  project                  = google_project.my_project-in-a-folder.project_id
  location                 = "us-east1"
  remove_default_node_pool = true
  initial_node_count       = 1
  network                  = google_compute_network.vpc_network.name
  subnetwork               = google_compute_subnetwork.private.name
  logging_service          = "logging.googleapis.com/kubernetes"
  monitoring_service       = "monitoring.googleapis.com/kubernetes"
  networking_mode          = "VPC_NATIVE"

  release_channel {
    channel = "REGULAR"
  }

  deletion_protection = false

  node_config {
    machine_type = "e2-medium"
    image_type   = "COS_CONTAINERD"
  }

  workload_identity_config {
    workload_pool = "${google_project.my_project-in-a-folder.project_id}.svc.id.goog"
  }


  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  node_locations = [
    "us-east1-b",
    "us-east1-c",
    "us-east1-d"
  ]

  addons_config {
    http_load_balancing {
      disabled = true
    }

    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "k8s-pods-range"
    services_secondary_range_name = "k8s-services-range"
  }

  private_cluster_config {
    enable_private_endpoint = false
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
}


resource "google_service_account" "kubernetes" {
  account_id = "kubernetes"
  project    = google_project.my_project-in-a-folder.project_id

}

# resource "google_container_node_pool" "general" {
#   name       = "general"
#   project    = google_project.my_project-in-a-folder.project_id
#   cluster    = google_container_cluster.primary.id
#   node_count = 1

#   management {
#     auto_repair  = true
#     auto_upgrade = true
#   }

#   node_config {
#     preemptible  = false
#     machine_type = "e2-small"

#     labels = {
#       role = "general"
#     }

#     service_account = google_service_account.kubernetes.email
#     oauth_scopes = [
#       "https://www.googleapis.com/auth/cloud-platform",
#     ]

#   }

# }


# resource "google_container_node_pool" "spot" {
#   name       = "spot"
#   project    = google_project.my_project-in-a-folder.project_id
#   cluster    = google_container_cluster.primary.id
#   node_count = 1

#   management {
#     auto_repair  = true
#     auto_upgrade = true
#   }

#   autoscaling {
#     min_node_count = 0
#     max_node_count = 10
#   }

#   node_config {
#     preemptible  = true
#     machine_type = "e2-small"

#     labels = {
#       team = "devops"
#     }

#     taint {
#       key    = "special"
#       value  = "spot"
#       effect = "NO_SCHEDULE"
#     }

#     service_account = google_service_account.kubernetes.email
#     oauth_scopes = [
#       "https://www.googleapis.com/auth/cloud-platform",
#     ]
#   }

# }

resource "google_compute_instance" "bastion_host" {
  name                      = "bastion-host"
  project                   = google_project.my_project-in-a-folder.project_id
  machine_type              = "e2-medium"
  zone                      = "us-east1-b"
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    access_config {
      // Include this block to give the instance a public IP
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_key}"
  }
}
