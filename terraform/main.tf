# ---------------------------------------------------------------------------
# main.tf
# ---------------------------------------------------------------------------
# Top-level config: enables required GCP APIs, defines locals shared across
# files, and generates random passwords / secret keys for the application.
# ---------------------------------------------------------------------------

locals {
  # APIs needed for: VPC, Compute, Cloud SQL, GCS, Secret Manager, PSA, IAM
  required_services = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
  ])

  # Bucket names - GCS bucket names are global, so we prefix with project_id
  photo_bucket_name   = "${var.project_id}-${var.photo_bucket_suffix}"
  staging_bucket_name = "${var.project_id}-${var.staging_bucket_suffix}"

  # Service account email (computed from id + project)
  service_account_email = "${var.service_account_id}@${var.project_id}.iam.gserviceaccount.com"
  service_account_member = "serviceAccount:${local.service_account_email}"
}

# ── Enable required APIs ───────────────────────────────────────────────────
resource "google_project_service" "services" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Some APIs (especially compute, servicenetworking) take 30-60s to fully
# propagate after enablement. This pause prevents flaky first applies on
# brand-new projects.
resource "time_sleep" "wait_for_apis" {
  depends_on      = [google_project_service.services]
  create_duration = "60s"
}

# ── Generated secrets ──────────────────────────────────────────────────────
# Random DB password - kept in Secret Manager, never in plaintext state outputs
resource "random_password" "db_password" {
  length  = 32
  special = false  # MySQL-friendly: avoids escape headaches in env vars
}

# Flask SECRET_KEY for session signing
resource "random_password" "flask_secret_key" {
  length  = 64
  special = false
}
