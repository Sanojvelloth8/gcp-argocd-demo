variable "project_id" {
  description = "GCP project ID to deploy into"
  type        = string
}

variable "region" {
  description = "GCP region for regional resources (Artifact Registry)"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  type    = string
  default = "genai-demo"
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
