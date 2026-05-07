# ---------------------------------------------------------------------------
# network.tf
# ---------------------------------------------------------------------------
# VPC, subnet, firewall rules, and Private Service Access (PSA) for Cloud SQL.
#
# Architecture:
#   ┌─────────────────────────────────────────────────────────┐
#   │ VPC: gallery-vpc (custom mode)                          │
#   │  ├─ Subnet: 10.0.0.0/16 ──► VM (gallery-app-vm)         │
#   │  └─ PSA Range: 10.20.0.0/16 ──► Cloud SQL (private IP)  │
#   └─────────────────────────────────────────────────────────┘
# ---------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [time_sleep.wait_for_apis]
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.vpc_name}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  # Enable Private Google Access so the VM can reach googleapis.com
  # (Secret Manager, GCS) without an external route.
  private_ip_google_access = true
}

# ── Private Service Access for Cloud SQL ──────────────────────────────────
# Reserve an IP range that GCP will use to peer Cloud SQL into our VPC.
resource "google_compute_global_address" "psa_range" {
  name          = "${var.vpc_name}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.psa_range_prefix
  address       = var.psa_range_cidr
  network       = google_compute_network.vpc.id
}

# Establishes the VPC peering between our network and Google's services network.
resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]

  depends_on = [time_sleep.wait_for_apis]
}

# ── Firewall rules ─────────────────────────────────────────────────────────

# HTTP (port 80) - public access for the gallery web UI
resource "google_compute_firewall" "allow_http" {
  name    = "${var.vpc_name}-allow-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
  description   = "Allow HTTP traffic to the gallery VM."
}

# HTTPS (port 443) - opened per assignment, even though we don't terminate TLS yet
resource "google_compute_firewall" "allow_https" {
  name    = "${var.vpc_name}-allow-https"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["https-server"]
  description   = "Allow HTTPS traffic to the gallery VM (reserved for future TLS termination)."
}

# SSH via IAP - lets you SSH into the VM through `gcloud compute ssh` without
# exposing port 22 to the internet. Much safer than 0.0.0.0/0 on 22.
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.vpc_name}-allow-ssh-iap"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's well-known source range. Only IAP-tunneled SSH gets through.
  source_ranges = ["35.235.240.0/20"]
  description   = "Allow SSH only from Google IAP range."
}

# Health check probe range (in case we add a load balancer later)
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.vpc_name}-allow-health-checks"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  # Google's health-check probers
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["http-server"]
  description   = "Allow GCP load balancer health checks to reach the app."
}
