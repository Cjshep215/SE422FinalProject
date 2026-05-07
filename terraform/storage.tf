# ---------------------------------------------------------------------------
# storage.tf
# ---------------------------------------------------------------------------
# Two GCS buckets:
#   1. photo bucket - holds user-uploaded image binaries (the app reads/writes)
#   2. staging bucket - holds the zipped Flask app code that the VM downloads
#                       on first boot
# ---------------------------------------------------------------------------

# ── Photo storage bucket ───────────────────────────────────────────────────
resource "google_storage_bucket" "photos" {
  name          = local.photo_bucket_name
  location      = var.region
  force_destroy = true  # Allow `terraform destroy` even with objects inside

  uniform_bucket_level_access = true

  # Soft-delete photos for 7 days in case of accidental deletion
  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [time_sleep.wait_for_apis]
}

# ── App code staging bucket ────────────────────────────────────────────────
# Holds the zipped Flask app. The VM startup script pulls from here on boot.
resource "google_storage_bucket" "staging" {
  name          = local.staging_bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  depends_on = [time_sleep.wait_for_apis]
}

# ── Bundle the Flask app into a zip ────────────────────────────────────────
# We zip the local ../app directory (relative to terraform/) so the VM gets
# everything it needs: gallery/ package, main.py, requirements.txt.
data "archive_file" "app_archive" {
  type        = "zip"
  source_dir  = "${path.module}/../app"
  output_path = "${path.module}/.terraform-build/app.zip"
}

# Upload the zip to the staging bucket. The object name includes the source
# hash so any code change forces a new object (and triggers a VM rebuild
# via the metadata_startup_script change in compute.tf).
resource "google_storage_bucket_object" "app_zip" {
  name   = "app-${data.archive_file.app_archive.output_md5}.zip"
  bucket = google_storage_bucket.staging.name
  source = data.archive_file.app_archive.output_path
}
