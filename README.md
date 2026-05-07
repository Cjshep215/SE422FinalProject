# SE 4220 Final Project — Photo Gallery on GCP via Terraform

Infrastructure-as-Code deployment of a Flask photo gallery application on Google Cloud Platform. Provisions a VPC, Compute Engine VM, Cloud SQL MySQL, GCS buckets, Secret Manager secrets, and least-privilege IAM — all via Terraform.

This is the Terraform-driven sibling of Project 4: same Flask gallery code (auth, upload, search, download), redeployed onto Compute Engine + Cloud SQL with private networking instead of App Engine.

## Architecture

```
                          ┌──────────────────────────────────────┐
                          │     gallery-vpc  (custom-mode)       │
                          │                                      │
   Internet ──HTTP(80)────┼─► Subnet 10.0.0.0/16                 │
                          │   ┌────────────────────────────┐     │
                          │   │  gallery-app-vm            │     │
                          │   │  e2-standard-2, Debian 12  │     │
                          │   │  - gunicorn:80 (systemd)   │     │
                          │   │  - SA: gallery-vm-sa       │     │
                          │   └────────────┬───────────────┘     │
                          │                │ private IP          │
                          │                ▼                     │
                          │   ┌────────────────────────────┐     │
                          │   │  gallery-mysql             │     │
                          │   │  Cloud SQL MySQL 8.0       │     │
                          │   │  db-n1-standard-1          │     │
                          │   │  via PSA range 10.20.0.0/16│     │
                          │   └────────────────────────────┘     │
                          └──────────────────────────────────────┘

                          ┌──────────────────────────────────────┐
                          │  Outside the VPC (managed services)  │
                          ├──────────────────────────────────────┤
                          │  GCS:    <project>-photos            │  ← image binaries
                          │  GCS:    <project>-app-staging       │  ← code zip
                          │  Secret: gallery-db-password         │
                          │  Secret: gallery-flask-secret-key    │
                          └──────────────────────────────────────┘
```

**How traffic flows**

A user hits `http://<vm-ip>/`, which lands on gunicorn running as a systemd service. The Flask app reads/writes user and photo metadata to Cloud SQL MySQL over the VPC's private IP range (no public DB exposure). Image binaries go to a GCS bucket via the VM's attached service account. On boot, the VM pulls its app code from a staging GCS bucket and pulls the DB password and Flask secret key from Secret Manager.

## Repository structure

```
se4220-final-project/
├── README.md                       — this file
├── app/
│   ├── gallery/                    — Flask application (Project 4 code, unchanged)
│   │   ├── __init__.py
│   │   ├── config.py               — DB connection mode selector (MySQL via DB_HOST)
│   │   ├── models.py               — SQLAlchemy models (User, Photo)
│   │   ├── routes.py               — auth, upload, search, download, /healthz
│   │   ├── storage.py              — GCS / local file storage backend
│   │   └── static/, templates/
│   ├── main.py                     — gunicorn entrypoint (`main:app`)
│   └── requirements.txt
├── terraform/
│   ├── requirements.tf             — provider versions, GCS backend
│   ├── variables.tf                — all variables with validation
│   ├── main.tf                     — API enablement, locals, random secrets
│   ├── network.tf                  — VPC, subnet, firewall, PSA
│   ├── storage.tf                  — GCS buckets + app zip upload
│   ├── database.tf                 — Cloud SQL + Secret Manager
│   ├── iam.tf                      — service account + scoped role bindings
│   ├── app-deploy.tf               — VM + startup script wiring
│   ├── outputs.tf                  — endpoints, connection strings, helpers
│   ├── startup.sh.tftpl            — VM boot script template
│   └── terraform.tfvars.example
└── scripts/
    └── bootstrap.sh                — one-time setup of state bucket
```

## Prerequisites

Install on your machine:

- **Terraform** ≥ 1.5 — `brew install terraform` or [download](https://developer.hashicorp.com/terraform/install)
- **gcloud CLI** — [install guide](https://cloud.google.com/sdk/docs/install)
- A **GCP project** with billing enabled. Note the project ID — you'll use it everywhere.

Authenticate locally:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

You need the **Owner** role (or equivalent: Editor + Project IAM Admin + Service Account Admin) on the project.

## Setup

### 1. Bootstrap the Terraform state bucket

The state bucket must exist before `terraform init`, since it can't hold its own state. Run the helper:

```bash
cd se4220-final-project
./scripts/bootstrap.sh YOUR_PROJECT_ID
```

This creates `gs://YOUR_PROJECT_ID-tfstate` with versioning enabled.

### 2. Configure your variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set at minimum:

```hcl
project_id = "your-actual-gcp-project-id"
```

Every other variable has a default that matches the assignment spec.

### 3. Initialize Terraform

```bash
terraform init -backend-config="bucket=YOUR_PROJECT_ID-tfstate"
```

This downloads the Google provider, sets up the GCS backend, and links state to the bucket created in step 1.

### 4. Review the plan

```bash
terraform plan
```

You should see ~30 resources to be created. Skim the plan to confirm it looks reasonable — this is the moment to catch typos.

### 5. Apply

```bash
terraform apply
```

Type `yes` when prompted. Expect **8–12 minutes** end-to-end. Cloud SQL provisioning is the long pole (~6–8 minutes on its own).

When it finishes, Terraform prints all outputs, including:

```
application_url            = "http://34.27.xxx.xxx"
health_check_url           = "http://34.27.xxx.xxx/healthz"
db_instance_connection_name = "your-project:us-central1:gallery-mysql"
db_private_ip               = "10.20.0.3"
photo_bucket                = "your-project-photos"
ssh_command                 = "gcloud compute ssh gallery-app-vm --zone=us-central1-a ..."
```

### 6. Wait for the app to come up

The VM finishes provisioning before its startup script finishes installing dependencies and starting gunicorn. Give it **2–3 more minutes** after `terraform apply` completes, then hit the URL.

To watch the startup script run live:

```bash
$(terraform output -raw tail_startup_log_command)
```

You should see it work through: apt-get → download zip → venv → pip install → fetch secrets → systemd start → "✓ App is healthy."

## Validation

### Health check

```bash
curl $(terraform output -raw health_check_url)
# Expected: {"status":"ok"}
```

### Web UI

Open the `application_url` in a browser. You should see the gallery login page.

- Click **Register**, create an account, log in.
- Upload a few images on the dashboard.
- Try the search box.
- Click **Download** on any uploaded photo.

Verify in the GCP Console:
- **Compute Engine → VM instances** — `gallery-app-vm` is RUNNING.
- **SQL → gallery-mysql** — instance is RUNNABLE.
- **Cloud Storage → Buckets** — your photos appear under `<project>-photos/user_1/...`
- **VPC network → VPC networks → gallery-vpc** — subnet `10.0.0.0/16` exists.
- **Secret Manager** — both secrets exist with one version each.
- **IAM & Admin → Service Accounts** — `gallery-vm-sa` exists with the expected roles.

### Database connectivity test

SSH into the VM and connect to MySQL through the private IP:

```bash
$(terraform output -raw ssh_command)
# Once on the VM:
sudo apt-get install -y mariadb-client
mysql -h $(grep DB_HOST /etc/gallery.env | cut -d= -f2) \
      -u $(grep DB_USER /etc/gallery.env | cut -d= -f2) \
      -p$(grep DB_PASSWORD /etc/gallery.env | cut -d= -f2) \
      photo_gallery -e "SHOW TABLES;"
```

You should see `users` and `photos` tables (created automatically by `db.create_all()` on first boot).

## Destroy

**Important: run this when the demo is finished to stop billing.**

```bash
terraform destroy
```

Expect ~5 minutes. If destroy hangs on Cloud SQL or the network, see Troubleshooting below.

## Variables reference

| Variable                  | Default            | Notes                                            |
| ------------------------- | ------------------ | ------------------------------------------------ |
| `project_id`              | *(required)*       | GCP project ID                                   |
| `region`                  | `us-central1`      |                                                  |
| `zone`                    | `us-central1-a`    | VM placement                                     |
| `vpc_name`                | `gallery-vpc`      |                                                  |
| `subnet_cidr`             | `10.0.0.0/16`      | Required by assignment                           |
| `psa_range_cidr`          | `10.20.0.0`        | Cloud SQL private IP range (must not overlap)    |
| `psa_range_prefix`        | `16`               |                                                  |
| `vm_machine_type`         | `e2-standard-2`    | Required by assignment                           |
| `vm_image`                | `debian-cloud/debian-12` |                                            |
| `vm_disk_size_gb`         | `20`               |                                                  |
| `db_tier`                 | `db-n1-standard-1` | Required by assignment                           |
| `db_version`              | `MYSQL_8_0`        |                                                  |
| `db_name`                 | `photo_gallery`    |                                                  |
| `db_user`                 | `gallery_user`     |                                                  |
| `db_deletion_protection`  | `false`            | Set `true` for production                        |
| `app_title`               | `SkyFrame Gallery` | Shown in UI header                               |
| `admin_email`             | `admin@example.com`| Auto-created admin email on first boot           |

## Outputs reference

| Output                        | Use case                                        |
| ----------------------------- | ----------------------------------------------- |
| `application_url`             | Open in browser to use the app                  |
| `health_check_url`            | curl this for deployment verification           |
| `vm_external_ip`              | Public IP of the VM                             |
| `db_instance_connection_name` | Used by Cloud SQL Auth Proxy if you ever want it|
| `db_private_ip`               | What the VM connects to                         |
| `photo_bucket`                | Where uploads land                              |
| `staging_bucket`              | Where the app zip lives                         |
| `ssh_command`                 | Copy-paste to SSH into the VM via IAP           |
| `tail_startup_log_command`    | Watch the boot log if the app isn't up          |

## Cost estimate

For a single demo run (apply → demo → destroy within a few hours):

| Resource              | Approx. hourly cost  |
| --------------------- | -------------------- |
| Compute Engine VM (e2-standard-2) | ~$0.07/hr |
| Cloud SQL (db-n1-standard-1)      | ~$0.10/hr |
| Persistent disks                  | ~$0.01/hr |
| Network egress + GCS              | negligible |
| **Total**             | **~$0.18/hr** |

**Run `terraform destroy` when finished.** Leaving it up for a week is ~$30. Leaving it for a month is ~$130.

## Troubleshooting

**`Error 400: Invalid request: Incorrect Service Networking config`**
Cloud SQL provisioning failed because PSA wasn't ready. Re-run `terraform apply` — the second pass will succeed once the service networking connection is fully propagated.

**App URL returns "connection refused" or hangs**
The VM is up but gunicorn hasn't started yet. SSH in and check:
```bash
sudo systemctl status gallery
sudo tail -100 /var/log/gallery-startup.log
```
Most common cause: pip install of Pillow took longer than expected. Wait another minute and retry.

**`destroy` hangs on `google_compute_network` or `google_service_networking_connection`**
PSA peering can be slow to tear down. If it's been stuck for >10 minutes, kill the run, then in the GCP Console go to **VPC Network → VPC network peering** and delete the `cloudsql-mysql-googleapis-com` peering manually. Re-run destroy.

**`Error: Error creating Address: googleapi: Error 409: The resource already exists`**
You ran `terraform apply` before, and the PSA range is left over. Run `terraform destroy` to clean up, or import the existing range with `terraform import google_compute_global_address.psa_range projects/YOUR_PROJECT/global/addresses/gallery-vpc-psa-range`.

**App crashes with "Access denied for user 'gallery_user'@..."**
The Secret Manager binding raced with the VM boot. Either:
- Reboot the VM: `gcloud compute instances reset gallery-app-vm --zone=us-central1-a`
- Or run `terraform apply` once more to reapply the IAM bindings.

## Production hardening (out of scope for this assignment, but worth mentioning)

If you wanted to make this real:

- **HTTPS**: front the VM with an HTTPS Load Balancer + managed SSL cert. Health check probes already work — the firewall rule is in place.
- **Managed Instance Group**: turn the single VM into a MIG with autoscaling and rolling updates.
- **Container deployment**: build a Docker image, push to Artifact Registry, run the app in a container or move to Cloud Run. Cloud Run with the same Cloud SQL via VPC connector is genuinely a few lines of swap.
- **Secret rotation**: Secret Manager supports rotation schedules; gunicorn would need a SIGHUP handler to pick up new values.
- **Cloud Armor** in front of the LB for WAF and DDoS protection.

## Why these design choices

A few decisions worth flagging if asked in the demo video:

- **Private IP for Cloud SQL** (PSA, not Cloud SQL Auth Proxy). The assignment specifies "private networking" and PSA gives you exactly that — Cloud SQL becomes a peer in your VPC, reachable on a 10.20.x.x address. Auth Proxy works too but adds a sidecar binary.
- **Secrets in Secret Manager, not Terraform variables.** Variables end up in plaintext state. Secret Manager keeps them out of state and lets you rotate without rebuilding the VM.
- **App code in a GCS staging bucket, not a public Git repo.** Reproducible, doesn't require committing the code anywhere public, and Terraform handles the upload + hashing automatically.
- **`CAP_NET_BIND_SERVICE` on the systemd unit.** Lets gunicorn bind to port 80 without running as root. Cleaner than nginx-as-reverse-proxy for this scope.
- **One VM, no load balancer.** A class project shouldn't pay for an LB. The firewall rule for health-check probers (`130.211.0.0/22`, `35.191.0.0/16`) is there so you could drop one in front later without changing the network layer.
