terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 2.0"
    }
  }
}

variable "project_id" {
  type = string
}

variable "cloudflare_email" {
  type = string
}

variable "cloudflare_api_key" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "certbot_domain" {
  type = string
}

variable "certbot_email" {
  type = string
}

data "template_file" "script" {
  template = file("./scripts/conf_certbot_and_vault.yaml")

  vars = {
    domain = var.certbot_domain
    email = var.certbot_email
    vault_config = base64encode(data.template_file.vault_config.rendered)
    vault_service_file = base64encode(file("./data/vault.service"))
  }
}

data "template_file" "vault_config" {
  template = file("./data/vault.hcl")

  vars = {
    domain = var.certbot_domain
    project = var.project_id
    region = "us-central1"
    key_ring = google_kms_key_ring.vault_key_ring.name
    crypto_key = google_kms_crypto_key.vault-key.name
  }
}

data "template_cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = true

  part {
    filename     = "conf_certbot_and_vault.yaml"
    content_type = "text/cloud-config"
    content = data.template_file.script.rendered
  }
}

provider "google" {

  credentials = file("credentials.json")

  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-c"
}

provider "cloudflare" { 
  email   = var.cloudflare_email
  api_key = var.cloudflare_api_key
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

resource "google_compute_firewall" "http" {
  name    = "allow-http"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
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

resource "google_kms_key_ring" "vault_key_ring" {
  name     = "vault_key_ring"
  location = "us-central1"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key" "vault-key" {
  name            = "crypto-key-example"
  key_ring        = google_kms_key_ring.vault_key_ring.id
  rotation_period = "100000s"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "service_account" {
  account_id   = "vault-service-account"
  display_name = "Vault Service Account"
}

resource "google_kms_key_ring_iam_binding" "vault_iam_kms_binding" {
  key_ring_id = google_kms_key_ring.vault_key_ring.id
  role = "roles/owner"

  members = [
    "serviceAccount:${google_service_account.service_account.email}",
  ]
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

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.service_account.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    user-data = data.template_cloudinit_config.user_data.rendered
    user-data-encoding = "base64"
  }
}

resource "google_compute_address" "vm_static_ip" {
  name = "terraform-static-ip"
}

resource "cloudflare_record" "vault_domain" {
  zone_id  = var.zone_id
  name    = "vault"
  value   = google_compute_address.vm_static_ip.address
  type    = "A"
  proxied = false
}