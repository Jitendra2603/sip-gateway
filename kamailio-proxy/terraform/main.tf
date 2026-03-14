terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "your-gcp-project-tf-state"
    prefix = "sip-gateway"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Static external IP for the SIP gateway — this is what customers whitelist
resource "google_compute_address" "sip_gateway" {
  name         = "${var.instance_name}-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

# Firewall: SIP signaling (UDP 5060, TCP 5060, TLS 5061)
resource "google_compute_firewall" "sip_signaling" {
  name    = "${var.instance_name}-sip-signaling"
  network = var.network

  allow {
    protocol = "udp"
    ports    = ["5060"]
  }

  allow {
    protocol = "tcp"
    ports    = ["5060", "5061"]
  }

  source_ranges = var.allowed_sip_source_ranges
  target_tags   = ["sip-gateway"]
}

# Firewall: RTP media (UDP 10000-20000)
resource "google_compute_firewall" "rtp_media" {
  name    = "${var.instance_name}-rtp-media"
  network = var.network

  allow {
    protocol = "udp"
    ports    = ["10000-20000"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["sip-gateway"]
}

# Firewall: SSH access
resource "google_compute_firewall" "ssh" {
  name    = "${var.instance_name}-ssh"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["sip-gateway"]
}

# GCE instance running Kamailio + RTPEngine via Docker Compose
resource "google_compute_instance" "sip_gateway" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["sip-gateway"]
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
      size  = var.disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = var.network

    access_config {
      nat_ip       = google_compute_address.sip_gateway.address
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = file("${path.module}/../scripts/startup.sh")

  service_account {
    scopes = ["cloud-platform"]
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  allow_stopping_for_update = true
}

# Health check for uptime monitoring (optional)
resource "google_compute_health_check" "sip_gateway" {
  name                = "${var.instance_name}-health"
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 5060
  }
}
