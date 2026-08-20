# gcp-argocd-demo

A small GitOps playground on GKE: Terraform provisions the cloud infra, ArgoCD watches this repo and deploys two things into the same Autopilot cluster — a tiny FastAPI chat app in the `genai-demo` namespace, and a self-hosted [Ollama](https://ollama.com) LLM server (CPU-only, a small `llama3.2:1b` model) in the `llm-inference` namespace. The app calls Ollama over the cluster's internal network. No external LLM API, no API key, no billing outside the GKE compute itself.

## Architecture

- **Terraform (`infra/`)** — owns cloud-level infra only: a zonal GKE Autopilot cluster, an Artifact Registry repo, Workload Identity Federation bindings (one for the app-build CI identity, one for the Terraform-runner CI identity), and a one-time ArgoCD install + root `Application`. State lives in a GCS bucket, not locally, so both your machine and CI operate on the same state.
- **ArgoCD, driven by `gitops/`** — owns everything inside the cluster: both namespaces, the Ollama Deployment + Service, and the chat app's Deployment. Terraform never touches these after the initial bootstrap.
- **`.github/workflows/build-and-push.yml`** — builds the app image, pushes it to Artifact Registry, and bumps the image tag in `gitops/deployment.yaml`. It never talks to the cluster — ArgoCD is the only thing with deploy access, and it gets there by watching Git.
- **`.github/workflows/terraform.yml`** — plans on pull requests that touch `infra/**`, applies on merge to `main`. Infra changes go through the same review flow as app code.

### Why Ollama instead of a hosted API

vLLM (the other common self-hosted option) is built for GPU-batched serving — running it means provisioning a GPU node pool, which adds real cost and Autopilot GPU-quota complexity for a demo. Ollama runs fine on plain CPU with a small quantized model, so the whole thing stays on ordinary Autopilot compute with no external billing account to wire up.

## Prerequisites

Already installed on this machine: `gcloud`, `terraform`, `kubectl`, `helm`, `docker`.

Before starting:

1. **Re-authenticate gcloud** (the active token expired):
   ```sh
   gcloud auth login
   ```
2. **Pick a GCP project.** Either reuse an existing one or create a fresh one dedicated to this demo:
   ```sh
   gcloud projects create gcp-argocd-demo
   gcloud config set project gcp-argocd-demo
   # link billing (required for GKE/Artifact Registry):
   gcloud billing projects link gcp-argocd-demo --billing-account=01055A-29EEAA-65B928
   ```
3. **Start Docker Desktop** — needed later to build the app image.

## Setup

1. **Push this repo to GitHub** (a real remote — ArgoCD and GitHub Actions both need to reach it):
   ```sh
   gh repo create gcp-argocd-demo --private --source=. --remote=origin --push
   ```

2. **Create the Terraform state bucket** (must exist before `terraform init` — this is the one piece of infra that can't provision itself):
   ```sh
   PROJECT_ID=$(gcloud config get-value project)
   gcloud storage buckets create "gs://${PROJECT_ID}-tfstate" \
     --location=us-central1 --uniform-bucket-level-access
   gcloud storage buckets update "gs://${PROJECT_ID}-tfstate" --versioning
   ```

3. **Configure Terraform variables:**
   ```sh
   cd infra
   cp terraform.tfvars.example terraform.tfvars
   # edit terraform.tfvars: project_id, github_repo, gitops_repo_url
   ```

4. **Init with the remote backend and apply:**
   ```sh
   terraform init \
     -backend-config="bucket=${PROJECT_ID}-tfstate" \
     -backend-config="prefix=gcp-argocd-demo"
   terraform apply
   ```
   This creates the cluster, Artifact Registry repo, the app + CI Workload Identity bindings, installs ArgoCD, and applies the root `Application`. Takes ~10-15 minutes, mostly the GKE cluster. This first apply runs locally with your own credentials — everything after this can run from CI.

5. **Get cluster credentials locally:**
   ```sh
   $(terraform output -raw get_credentials_command)
   ```

6. **Fill in the real project ID** in the GitOps manifests (Terraform can't template these — ArgoCD applies them verbatim from Git):
   ```sh
   cd ..
   sed -i '' "s/PROJECT_ID/$PROJECT_ID/g" gitops/deployment.yaml
   git add gitops/ && git commit -m "fill in project ID" && git push
   ```

7. **Bootstrap the Terraform-runner CI identity** (one-time, run locally — see the comment in the script for why this isn't a Terraform resource):
   ```sh
   ./infra/bootstrap-tf-ci.sh "$PROJECT_ID" your-github-username/gcp-argocd-demo
   ```

8. **Wire up GitHub Actions.** In the GitHub repo settings → Secrets and variables → Actions → Variables, add (used by both `build-and-push.yml` and `terraform.yml`):
   - `GCP_PROJECT_ID` — your project ID
   - `GCP_WORKLOAD_IDENTITY_PROVIDER` — output of `terraform output -raw github_workload_identity_provider`

9. **Watch it come up:**
    ```sh
    kubectl get applications -n argocd
    kubectl get pods -n llm-inference -w    # wait for ollama to pull the model and go Ready
    kubectl get pods -n genai-demo -w
    ```

## Try it

```sh
kubectl port-forward -n genai-demo svc/genai-app 8080:8080 &
curl "localhost:8080/ask?q=tell+me+a+one-line+joke+about+kubernetes"

# watch ArgoCD sync visually:
kubectl port-forward -n argocd svc/argocd-server 8081:443 &
# open https://localhost:8081  (user: admin, password: below)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

First request after a fresh deploy may be slow or 502 — the Ollama pod pulls the model (~1GB) on first startup; check `kubectl get pods -n llm-inference` and wait for it to go `Ready` before hitting `/ask`.

## Changing infra

Edit anything under `infra/`, open a PR — `terraform.yml` runs `terraform plan` and you can read the diff in the Actions log. Merge to `main` and it applies automatically. The identity running this (`genai-tf-sa`) only has the roles granted in `bootstrap-tf-ci.sh`; if a change needs a new permission, re-run that script (or edit it) locally rather than broadening its access through a PR.

## See the GitOps loop in action

Change something in `app/main.py`, commit, and push to `main`. GitHub Actions builds and pushes a new image, bumps the tag in `gitops/deployment.yaml`, and commits that change back. ArgoCD notices the Git change within its poll interval (or immediately if you click "Refresh" in the UI) and rolls out the new image — no `kubectl apply` involved.

## Cost and teardown

GKE Autopilot's cluster management fee is waived for one zonal cluster per billing account. You still pay for pod compute while it's running — the chat app is negligible, but the Ollama pod requests 2 CPU / 4Gi memory to run the model, which is the bulk of this demo's cost (well under $1 for a short session, but don't leave it running unattended). There's no external API billing — everything runs on cluster compute you already provisioned. **Tear down when you're done**:

```sh
cd infra
terraform destroy
```

Then clean up anything Terraform doesn't own:
```sh
gcloud artifacts docker images list us-central1-docker.pkg.dev/$PROJECT_ID/genai-demo
# delete any images terraform destroy left behind (it deletes the repo, but double check)

# the state bucket and genai-tf-sa were created outside Terraform, so destroy won't remove them:
gcloud storage rm -r "gs://${PROJECT_ID}-tfstate"
gcloud iam service-accounts delete "genai-tf-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```
