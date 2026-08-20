#!/usr/bin/env bash
# One-time bootstrap for the identity that runs Terraform from GitHub Actions.
#
# This is deliberately a plain gcloud script, not a Terraform resource. Having
# Terraform grant its own CI identity the permissions it runs with is a
# privilege-escalation smell: a merged PR could grant that identity more
# power than it started with. Run this once, locally, with your own
# (human) credentials — after that, terraform.yml can only do what's
# granted here.
set -euo pipefail

PROJECT_ID="${1:?Usage: bootstrap-tf-ci.sh <project-id> <github-owner/repo>}"
GITHUB_REPO="${2:?Usage: bootstrap-tf-ci.sh <project-id> <github-owner/repo>}"

TF_SA="genai-tf-sa@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET="${PROJECT_ID}-tfstate"

gcloud iam service-accounts create genai-tf-sa \
  --project "$PROJECT_ID" \
  --display-name "Terraform runner for gcp-argocd-demo CI"

# Least privilege for exactly what infra/*.tf manages: GKE, Artifact Registry,
# service accounts + their IAM bindings, the WIF pool/provider, and enabling
# APIs. Notably NOT resourcemanager.projectIamAdmin — nothing in this config
# sets project-level IAM policy, so it doesn't need it.
for role in \
  roles/container.admin \
  roles/artifactregistry.admin \
  roles/iam.serviceAccountAdmin \
  roles/iam.workloadIdentityPoolAdmin \
  roles/serviceusage.serviceUsageAdmin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:${TF_SA}" \
    --role "$role" \
    --condition None \
    --quiet
done

# Read/write access to the Terraform state bucket only (not project-wide storage).
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "serviceAccount:${TF_SA}" \
  --role roles/storage.objectAdmin

# Reuse the GitHub OIDC pool created by the first (local) `terraform apply` —
# it already trusts this repo's GitHub Actions identity.
POOL_NAME=$(gcloud iam workload-identity-pools describe github-actions-pool \
  --project "$PROJECT_ID" --location global --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "$TF_SA" \
  --project "$PROJECT_ID" \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository/${GITHUB_REPO}"

echo "Done. genai-tf-sa is ready for .github/workflows/terraform.yml to impersonate via WIF."
