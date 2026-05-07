# ---------------------------------------------------------------------------
# database.tf
# ---------------------------------------------------------------------------
# Cloud SQL MySQL 8.0 instance with private networking only (no public IP).
# Stores the DB password and Flask SECRET_KEY in Secret Manager.
# ---------------------------------------------------------------------------

# ── Cloud SQL MySQL instance ───────────────────────────────────────────────
resource "google_sql_database_instance" "mysql" {
  name             = var.db_instance_name
  database_version = var.db_version
  region           = var.region

  # Disable accidental destroy protection for class demo workflow
  deletion_protection = var.db_deletion_protection

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"  # Class project - no need for regional HA
    disk_size         = var.db_disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    # Private IP only - no public IP exposure. The VM reaches MySQL through
    # the VPC peering set up in network.tf.
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
      start_time         = "03:00"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = false
      record_client_address   = false
    }

    # Permanently delete instance backups on destroy (class demo)
    deletion_protection_enabled = var.db_deletion_protection
  }

  # PSA must be fully provisioned before Cloud SQL can attach to the VPC
  depends_on = [
    google_service_networking_connection.psa,
    time_sleep.wait_for_apis,
  ]
}

# ── Database & user ────────────────────────────────────────────────────────
resource "google_sql_database" "gallery" {
  name     = var.db_name
  instance = google_sql_database_instance.mysql.name
}

resource "google_sql_user" "gallery" {
  name     = var.db_user
  instance = google_sql_database_instance.mysql.name
  host     = "%"  # Connect from any host in the VPC
  password = random_password.db_password.result
}

# ── Secret Manager ─────────────────────────────────────────────────────────
# DB password - VM's SA has accessor role (granted in iam.tf)
resource "google_secret_manager_secret" "db_password" {
  secret_id = "gallery-db-password"

  replication {
    auto {}
  }

  depends_on = [time_sleep.wait_for_apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Flask SECRET_KEY for session signing
resource "google_secret_manager_secret" "flask_secret_key" {
  secret_id = "gallery-flask-secret-key"

  replication {
    auto {}
  }

  depends_on = [time_sleep.wait_for_apis]
}

resource "google_secret_manager_secret_version" "flask_secret_key" {
  secret      = google_secret_manager_secret.flask_secret_key.id
  secret_data = random_password.flask_secret_key.result
}
