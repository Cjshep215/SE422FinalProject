# ---------------------------------------------------------------------------
# iam.tf
# ---------------------------------------------------------------------------
# Service account attached to the VM, with the minimum roles needed to:
#   - Read/write photos in the GCS photo bucket
#   - Read the app zip from the staging bucket
#   - Connect to Cloud SQL (used implicitly even with private IP)
#   - Read the DB password & Flask key from Secret Manager
#   - Write logs and metrics to Cloud Operations
#
# All bindings are scoped to specific resources where possible (bucket-level,
# secret-level) rather than project-wide.
# ---------------------------------------------------------------------------

resource "google_service_account" "gallery_vm" {
  account_id   = var.service_account_id
  display_name = "Gallery VM Runtime SA"
  description  = "Service account attached to the VM running the Flask gallery app."

  depends_on = [time_sleep.wait_for_apis]
}

# ── Bucket-scoped roles ────────────────────────────────────────────────────

# Full read/write on the photo bucket (the app uploads & downloads images here)
resource "google_storage_bucket_iam_member" "photos_object_admin" {
  bucket = google_storage_bucket.photos.name
  role   = "roles/storage.objectAdmin"
  member = local.service_account_member
}

# Read-only on the staging bucket (just to download the app zip on boot)
resource "google_storage_bucket_iam_member" "staging_object_viewer" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectViewer"
  member = local.service_account_member
}

# ── Secret-scoped roles ────────────────────────────────────────────────────
# Each secret gets its own accessor binding - tighter than project-wide

resource "google_secret_manager_secret_iam_member" "db_password_accessor" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.service_account_member
}

resource "google_secret_manager_secret_iam_member" "flask_secret_accessor" {
  secret_id = google_secret_manager_secret.flask_secret_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.service_account_member
}

# ── Project-scoped roles (cannot be bucket/secret-scoped) ──────────────────

# Cloud SQL Client - needed for the Cloud SQL connector & ADC
resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = local.service_account_member
}

# Logging - ship app logs to Cloud Logging
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.service_account_member
}

# Monitoring - ship VM metrics
resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = local.service_account_member
}
