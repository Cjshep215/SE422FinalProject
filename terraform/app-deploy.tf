# ---------------------------------------------------------------------------
# app-deploy.tf
# ---------------------------------------------------------------------------
# The Compute Engine VM that runs the Flask gallery app via gunicorn+systemd.
#
# Network: attached to the custom VPC subnet, with a public IP so it's
# reachable on port 80. Cloud SQL is reached over private IP via VPC peering.
# ---------------------------------------------------------------------------

resource "google_compute_instance" "gallery_vm" {
  name         = var.vm_name
  machine_type = var.vm_machine_type
  zone         = var.zone

  # Tags map to the firewall rules in network.tf
  tags = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = var.vm_image
      size  = var.vm_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id

    # Public IP for browser access. Use access_config with no nat_ip to get
    # an ephemeral external IP (auto-assigned by GCP).
    access_config {
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email = google_service_account.gallery_vm.email
    # cloud-platform scope lets the VM use any API the SA has permission for.
    # IAM (not scopes) is the actual access boundary on modern VMs.
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  # Render the startup script template with all the values it needs.
  metadata_startup_script = templatefile("${path.module}/startup.sh.tftpl", {
    project_id              = var.project_id
    vm_name                 = var.vm_name
    zone                    = var.zone
    staging_bucket          = google_storage_bucket.staging.name
    app_archive_name        = google_storage_bucket_object.app_zip.name
    db_host                 = google_sql_database_instance.mysql.private_ip_address
    db_name                 = var.db_name
    db_user                 = var.db_user
    db_password_secret      = google_secret_manager_secret.db_password.secret_id
    flask_secret_key_secret = google_secret_manager_secret.flask_secret_key.secret_id
    photo_bucket            = google_storage_bucket.photos.name
    app_title               = var.app_title
    admin_email             = var.admin_email
  })

  # Ensure all dependencies are in place before the VM tries to boot.
  # If any of these aren't ready, the startup script will fail.
  depends_on = [
    google_sql_database.gallery,
    google_sql_user.gallery,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.flask_secret_key,
    google_storage_bucket_object.app_zip,
    google_storage_bucket_iam_member.photos_object_admin,
    google_storage_bucket_iam_member.staging_object_viewer,
    google_secret_manager_secret_iam_member.db_password_accessor,
    google_secret_manager_secret_iam_member.flask_secret_accessor,
    google_project_iam_member.cloudsql_client,
  ]

  # When the app archive content changes, force a VM replacement.
  # Without this, Terraform would just update the startup script metadata
  # but the VM doesn't re-run startup scripts on metadata change - it would
  # keep serving the old code until manually rebooted.
  lifecycle {
    replace_triggered_by = [google_storage_bucket_object.app_zip]
  }
}
