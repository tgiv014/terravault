terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

variable "project_id" {
  type = string
}

data "template_cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "conf_certbot_and_vault.yaml"
    content_type = "text/cloud-config"
    content = file("./scripts/conf_certbot_and_vault.yaml")
  }
}

provider "google" {

  credentials = file("credentials.json")

  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-c"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_firewall" "http-ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "http-vault" {
  name    = "allow-vault"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["8200"]
  }
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "f1-micro"
  tags         = ["web", "dev"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1804-bionic-v20210325"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
        nat_ip = google_compute_address.vm_static_ip.address
    }
  }

  metadata = {
    user-data = data.template_cloudinit_config.user_data.rendered
    # user-data-encoding = "base64"
  }
}

resource "google_compute_address" "vm_static_ip" {
  name = "terraform-static-ip"
}
