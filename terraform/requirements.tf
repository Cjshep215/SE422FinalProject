# ---------------------------------------------------------------------------
# requirements.tf
# ---------------------------------------------------------------------------
# Pins the Terraform CLI version, required providers, and configures the
# remote state backend (Google Cloud Storage).
#
# IMPORTANT: The state bucket must be created BEFORE `terraform init`.
# Run scripts/bootstrap.sh first, or create the bucket manually with:
#   gsutil mb -p YOUR_PROJECT_ID -l us-central1 gs://YOUR_PROJECT_ID-tfstate
#
# Then init with:
#   terraform init -backend-config="bucket=YOUR_PROJECT_ID-tfstate"
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # GCS backend: bucket name supplied at init time so this file is portable.
  # Run: terraform init -backend-config="bucket=YOUR_PROJECT_ID-tfstate"
  backend "gcs" {
    prefix = "terraform/state/se4220-final"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
