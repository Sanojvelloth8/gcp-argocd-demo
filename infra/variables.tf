variable "project_id" {
  description = "GCP project ID to deploy into"
  type        = string
}

variable "region" {
  description = "GCP region for regional resources (Artifact Registry)"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the GKE cluster and its node pool"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  type    = string
  default = "genai-demo"
}

variable "node_machine_type" {
  description = "Machine type for the GKE node pool"
  type        = string
  default     = "e2-standard-4"
}

variable "app_namespace" {
  type    = string
  default = "genai-demo"
}

variable "artifact_repo_id" {
  type    = string
  default = "genai-demo"
}

variable "gitops_repo_url" {
  description = "Git URL of the repo ArgoCD should watch (the gitops/ folder in this same repo)"
  type        = string
}

variable "github_token" {
  description = "Token ArgoCD's repo-server uses to clone the private gitops repo (any credential with read access, e.g. gh CLI's own OAuth token)"
  type        = string
  sensitive   = true
}
