#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/bootstrap.sh
# ---------------------------------------------------------------------------
# One-time pre-Terraform setup. Creates the GCS bucket that will hold the
# remote Terraform state, since you can't store the bucket's own state in
# itself (chicken-and-egg).
#
# Usage:
#   ./scripts/bootstrap.sh YOUR_PROJECT_ID [REGION]
# ---------------------------------------------------------------------------

set -euo pipefail

PROJECT_ID="${1:-}"
REGION="${2:-us-central1}"

if [ -z "$PROJECT_ID" ]; then
  echo "Usage: $0 PROJECT_ID [REGION]" >&2
  echo "Example: $0 my-cloud-project-12345 us-central1" >&2
  exit 1
fi

STATE_BUCKET="${PROJECT_ID}-tfstate"

echo "==> Project:       $PROJECT_ID"
echo "==> Region:        $REGION"
echo "==> State bucket:  gs://$STATE_BUCKET"
echo

# Make sure gcloud is pointed at the right project
gcloud config set project "$PROJECT_ID"

# Enable cloudresourcemanager so Terraform can manage other services
echo "==> Enabling Cloud Resource Manager API (required for Terraform)..."
gcloud services enable cloudresourcemanager.googleapis.com --project="$PROJECT_ID"

# Create the state bucket if it doesn't exist
if gsutil ls -b "gs://$STATE_BUCKET" >/dev/null 2>&1; then
  echo "==> State bucket already exists."
else
  echo "==> Creating state bucket..."
  gsutil mb -p "$PROJECT_ID" -l "$REGION" -b on "gs://$STATE_BUCKET"
fi

# Enable versioning on the state bucket - critical for Terraform state safety
echo "==> Enabling versioning on state bucket..."
gsutil versioning set on "gs://$STATE_BUCKET"

# Add a lifecycle rule to clean up old state versions after 30 days
echo "==> Setting lifecycle rule to clean up old state versions..."
cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": { "type": "Delete" },
        "condition": {
          "numNewerVersions": 10,
          "isLive": false
        }
      }
    ]
  }
}
EOF
gsutil lifecycle set /tmp/lifecycle.json "gs://$STATE_BUCKET"
rm /tmp/lifecycle.json

echo
echo "==> Bootstrap complete!"
echo
echo "Next steps:"
echo "  1. cd terraform/"
echo "  2. cp terraform.tfvars.example terraform.tfvars"
echo "     # Edit terraform.tfvars and set project_id = \"$PROJECT_ID\""
echo "  3. terraform init -backend-config=\"bucket=$STATE_BUCKET\""
echo "  4. terraform plan"
echo "  5. terraform apply"
