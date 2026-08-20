# gcp-argocd-demo

A GitOps playground on GKE: Terraform provisions the cloud infra, GitHub Actions runs both Terraform and the app build, and ArgoCD watches this repo and deploys everything into the cluster. Two things run there — a self-hosted [Ollama](https://ollama.com) LLM server (CPU-only, a small `llama3.2:1b` model) in the `llm-inference` namespace, and a tiny FastAPI chat app in the `genai-demo` namespace that calls it over the cluster's internal network. No external LLM API, no API key, no billing outside the GKE compute itself.

## Architecture

- **Terraform (`infra/`)** — owns cloud-level infra only: a zonal GKE Autopilot cluster, an Artifact Registry repo, and a one-time ArgoCD install + root `Application`. State lives in a GCS bucket, not locally, so both your machine and CI operate on the same state.
- **ArgoCD, driven by `gitops/`** — owns everything inside the cluster: both namespaces, the Ollama Deployment + Service, and the chat app's Deployment. Terraform never touches these after the initial bootstrap.
- **`.github/workflows/terraform.yml`** — plans on pull requests that touch `infra/**`, applies on merge to `main`.
- **`.github/workflows/build-and-push.yml`** — builds the app image, pushes it to Artifact Registry, and bumps the image tag in `gitops/deployment.yaml`. It never talks to the cluster — ArgoCD is the only thing with deploy access, and it gets there by watching Git.
- **Auth for both workflows**: a single GCP service account key (`GCP_SA_KEY`, a GitHub Actions secret), not Workload Identity Federation. Simpler to set up for a demo — the tradeoff is a static, long-lived credential instead of short-lived OIDC-issued tokens, which is fine here but not what you'd want for a production setup.

### Why Ollama instead of a hosted API

vLLM (the other common self-hosted option) is built for GPU-batched serving — running it means provisioning a GPU node pool, which adds real cost and Autopilot GPU-quota complexity for a demo. Ollama runs fine on plain CPU with a small quantized model, so the whole thing stays on ordinary Autopilot compute with no external billing account to wire up.

## Prerequisites — already in place

- **GCP project**: `gcp-argocd-demo`, billing linked
- **GitHub repo**: [`Sanojvelloth8/gcp-argocd-demo`](https://github.com/Sanojvelloth8/gcp-argocd-demo) (private)
- **Service account**: `sanoj-admin@gcp-argocd-demo.iam.gserviceaccount.com` (project `roles/owner`), its key stored as the `GCP_SA_KEY` secret on the repo
- **Terraform state bucket**: `gs://gcp-argocd-demo-tfstate` (versioned, `us-central1`)

Still needed before the first CI run:

1. **Set the `GCP_PROJECT_ID` repo variable** (both workflows read it):
   ```sh
   gh variable set GCP_PROJECT_ID --repo Sanojvelloth8/gcp-argocd-demo --body gcp-argocd-demo
   ```
2. **Configure Terraform variables locally** (only needed if you want to run `terraform plan` locally before pushing — CI applies independently):
   ```sh
   cd infra
   cp terraform.tfvars.example terraform.tfvars
   # edit terraform.tfvars: project_id, gitops_repo_url
   ```

## Setup

1. **Push this repo to GitHub** (already created — just push your commits):
   ```sh
   git push -u origin main
   ```
   Pushing `infra/**` triggers `terraform.yml`, which runs `terraform apply` on `main` — this creates the cluster, Artifact Registry, and ArgoCD, and applies the root `Application`. Takes ~10-15 minutes, mostly the GKE cluster. Watch it in the repo's **Actions** tab.

2. **Get cluster credentials locally** (once the cluster exists):
   ```sh
   gcloud container clusters get-credentials genai-demo --zone us-central1-a --project gcp-argocd-demo
   ```

3. **Watch it come up:**
   ```sh
   kubectl get applications -n argocd
   kubectl get pods -n llm-inference -w    # wait for ollama to pull the model
   kubectl get pods -n genai-demo -w
   ```
   The app Deployment will sit in `ImagePullBackOff` until `build-and-push.yml` runs — it triggers on any push touching `app/**`, so it runs automatically once your first commit lands on `main`.

## Try it

```sh
kubectl port-forward -n genai-demo svc/genai-app 8080:8080 &
curl "localhost:8080/ask?q=tell+me+a+one-line+joke+about+kubernetes"

# watch ArgoCD sync visually:
kubectl port-forward -n argocd svc/argocd-server 8081:443 &
# open https://localhost:8081  (user: admin, password: below)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

First request after a fresh deploy may be slow or return a 502 — the Ollama pod pulls the model (~1GB) on first startup; check `kubectl get pods -n llm-inference` and wait for it to go `Ready` before hitting `/ask`.

### Before a live demo

Run this once, before you start talking, and leave it backgrounded for the whole session:

```sh
kubectl port-forward -n argocd svc/argocd-server 8081:443 &
```

That's the only port-forward you need. `genai-app` is public via the Ingress below — no port-forward for that, and `llm-inference` (Ollama) is never accessed directly at all, so there's nothing to forward for it either.

### Public access

`gitops/ingress.yaml` puts `genai-app` behind GKE's built-in Ingress controller — no controller to install, it just provisions a real Google Cloud HTTP Load Balancer. Get the external IP once it finishes provisioning (a few minutes after the Ingress first syncs):

```sh
kubectl get ingress -n genai-demo genai-app -w
# once ADDRESS is populated:
curl "http://<EXTERNAL_IP>/ask?q=tell+me+a+one-line+joke+about+kubernetes"
```

Plain HTTP, no domain or TLS (a Google-managed cert needs a real domain you control — out of scope for this demo). **There's no auth or rate limiting on `/ask`** — anyone who finds the IP can hit it and consume the Ollama pod's CPU. Fine for a short-lived demo; don't leave it up unattended. This also adds real, continuous billing (a GCP HTTP Load Balancer, roughly $18-25/month) on top of the Ollama pod's compute cost — tear it down along with everything else when you're done (`kubectl delete -f gitops/ingress.yaml` removes just the load balancer, or `terraform destroy` per the teardown section removes everything).

## Changing infra

Edit anything under `infra/`, open a PR — `terraform.yml` runs `terraform plan` and you can read the diff in the Actions log. Merge to `main` and it applies automatically.

## See the GitOps loop in action

Change something in `app/main.py`, commit, and push to `main`. GitHub Actions builds and pushes a new image, bumps the tag in `gitops/deployment.yaml`, and commits that change back. ArgoCD notices the Git change within its poll interval (or immediately if you click "Refresh" in the UI) and rolls out the new image — no `kubectl apply` involved.

## Cost and teardown

GKE Autopilot's cluster management fee is waived for one zonal cluster per billing account. You still pay for pod compute while it's running — the chat app is negligible, but the Ollama pod requests 2 CPU / 4Gi memory to run the model, which is the bulk of this demo's cost. There's no external API billing — everything runs on cluster compute you already provisioned. **Tear down when you're done**:

```sh
cd infra
terraform init -backend-config="bucket=gcp-argocd-demo-tfstate" -backend-config="prefix=gcp-argocd-demo"
terraform destroy
```

Then clean up anything Terraform doesn't own:
```sh
gcloud artifacts docker images list us-central1-docker.pkg.dev/gcp-argocd-demo/genai-demo
# delete any images terraform destroy left behind (it deletes the repo, but double check)

# the state bucket, sanoj-admin SA, and its key were created outside Terraform, so destroy won't remove them:
gcloud storage rm -r gs://gcp-argocd-demo-tfstate
gcloud iam service-accounts keys list --iam-account=sanoj-admin@gcp-argocd-demo.iam.gserviceaccount.com
gcloud iam service-accounts keys delete <KEY_ID> --iam-account=sanoj-admin@gcp-argocd-demo.iam.gserviceaccount.com
gcloud iam service-accounts delete sanoj-admin@gcp-argocd-demo.iam.gserviceaccount.com
```
