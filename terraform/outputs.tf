# ---------------------------------------------------------------------------
# outputs.tf
# ---------------------------------------------------------------------------
# Information emitted after `terraform apply`. These satisfy the assignment's
# "Output application endpoint and database connection details" requirement.
# ---------------------------------------------------------------------------

# ── Application endpoints ──────────────────────────────────────────────────

output "vm_external_ip" {
  description = "Public IP of the gallery VM."
  value       = google_compute_instance.gallery_vm.network_interface[0].access_config[0].nat_ip
}

output "application_url" {
  description = "URL where the gallery app is reachable."
  value       = "http://${google_compute_instance.gallery_vm.network_interface[0].access_config[0].nat_ip}"
}

output "health_check_url" {
  description = "Health check endpoint - should return {\"status\":\"ok\"}."
  value       = "http://${google_compute_instance.gallery_vm.network_interface[0].access_config[0].nat_ip}/healthz"
}

# ── Database connection details ────────────────────────────────────────────

output "db_instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.mysql.name
}

output "db_instance_connection_name" {
  description = "Cloud SQL instance connection name (project:region:instance)."
  value       = google_sql_database_instance.mysql.connection_name
}

output "db_private_ip" {
  description = "Private IP the VM uses to reach Cloud SQL."
  value       = google_sql_database_instance.mysql.private_ip_address
}

output "db_name" {
  description = "Application database name."
  value       = google_sql_database.gallery.name
}

output "db_user" {
  description = "Application database user."
  value       = google_sql_user.gallery.name
}

output "db_password_secret_name" {
  description = "Secret Manager secret holding the DB password (to retrieve: gcloud secrets versions access latest --secret=<this>)."
  value       = google_secret_manager_secret.db_password.secret_id
}

# ── Storage ────────────────────────────────────────────────────────────────

output "photo_bucket" {
  description = "GCS bucket where uploaded photos are stored."
  value       = google_storage_bucket.photos.name
}

output "staging_bucket" {
  description = "GCS bucket holding the deployed app zip."
  value       = google_storage_bucket.staging.name
}

# ── Networking ─────────────────────────────────────────────────────────────

output "vpc_name" {
  description = "Name of the custom VPC."
  value       = google_compute_network.vpc.name
}

output "subnet_cidr" {
  description = "CIDR of the main subnet."
  value       = google_compute_subnetwork.main.ip_cidr_range
}

# ── Operations ─────────────────────────────────────────────────────────────

output "ssh_command" {
  description = "Command to SSH into the VM via IAP (no public SSH port needed)."
  value       = "gcloud compute ssh ${google_compute_instance.gallery_vm.name} --zone=${google_compute_instance.gallery_vm.zone} --tunnel-through-iap --project=${var.project_id}"
}

output "tail_startup_log_command" {
  description = "Command to watch the VM's startup log."
  value       = "gcloud compute ssh ${google_compute_instance.gallery_vm.name} --zone=${google_compute_instance.gallery_vm.zone} --tunnel-through-iap --project=${var.project_id} -- 'sudo tail -f /var/log/gallery-startup.log'"
}

output "destroy_reminder" {
  description = "Reminder to destroy resources after the demo to avoid billing charges."
  value       = "When done, run: terraform destroy -auto-approve"
}
