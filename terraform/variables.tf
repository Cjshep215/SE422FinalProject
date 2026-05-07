# ---------------------------------------------------------------------------
# variables.tf
# ---------------------------------------------------------------------------
# All inputs to the Terraform configuration. Each variable has a description,
# type, and where appropriate a validation block.
# ---------------------------------------------------------------------------

# ── Project & location ─────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID where all resources will be created."
  type        = string

  validation {
    condition     = length(var.project_id) >= 6 && length(var.project_id) <= 30
    error_message = "GCP project IDs must be 6-30 characters long."
  }
}

variable "region" {
  description = "Regional location for VPC subnet, Cloud SQL, and bucket."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Compute Engine zone for the VM."
  type        = string
  default     = "us-central1-a"
}

# ── Networking ─────────────────────────────────────────────────────────────

variable "vpc_name" {
  description = "Name for the custom-mode VPC network."
  type        = string
  default     = "gallery-vpc"
}

variable "subnet_cidr" {
  description = "CIDR range for the VM subnet. Required: 10.0.0.0/16 per assignment."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "psa_range_cidr" {
  description = "CIDR for Cloud SQL Private Service Access. Must NOT overlap subnet_cidr."
  type        = string
  default     = "10.20.0.0"
}

variable "psa_range_prefix" {
  description = "Prefix length for the PSA range."
  type        = number
  default     = 16
}

# ── Compute ────────────────────────────────────────────────────────────────

variable "vm_name" {
  description = "Name for the Compute Engine VM running the Flask app."
  type        = string
  default     = "gallery-app-vm"
}

variable "vm_machine_type" {
  description = "Machine type for the VM. Required: e2-standard-2 per assignment."
  type        = string
  default     = "e2-standard-2"
}

variable "vm_image" {
  description = "Boot disk image for the VM."
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "vm_disk_size_gb" {
  description = "Boot disk size in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.vm_disk_size_gb >= 10 && var.vm_disk_size_gb <= 200
    error_message = "Boot disk size must be between 10 and 200 GB."
  }
}

# ── Cloud SQL ──────────────────────────────────────────────────────────────

variable "db_instance_name" {
  description = "Cloud SQL instance name."
  type        = string
  default     = "gallery-mysql"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. Required: db-n1-standard-1 per assignment."
  type        = string
  default     = "db-n1-standard-1"
}

variable "db_version" {
  description = "MySQL version."
  type        = string
  default     = "MYSQL_8_0"
}

variable "db_name" {
  description = "MySQL database name."
  type        = string
  default     = "photo_gallery"
}

variable "db_user" {
  description = "MySQL application user."
  type        = string
  default     = "gallery_user"
}

variable "db_disk_size_gb" {
  description = "Cloud SQL data disk size in GB."
  type        = number
  default     = 10
}

variable "db_deletion_protection" {
  description = "Whether Cloud SQL is protected from deletion. Set false for class demos."
  type        = bool
  default     = false
}

# ── Application ────────────────────────────────────────────────────────────

variable "app_title" {
  description = "Display title shown in the gallery UI."
  type        = string
  default     = "SkyFrame Gallery"
}

variable "admin_email" {
  description = "Email seeded into the auto-created admin account on first boot."
  type        = string
  default     = "admin@example.com"

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.admin_email))
    error_message = "admin_email must be a valid email address."
  }
}

# ── Naming ─────────────────────────────────────────────────────────────────

variable "service_account_id" {
  description = "Account ID for the VM-attached service account."
  type        = string
  default     = "gallery-vm-sa"
}

variable "photo_bucket_suffix" {
  description = "Suffix for the photo bucket name (full name = project_id-suffix)."
  type        = string
  default     = "photos"
}

variable "staging_bucket_suffix" {
  description = "Suffix for the staging bucket holding the app code archive."
  type        = string
  default     = "app-staging"
}
