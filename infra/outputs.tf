output "cluster_name" {
  value = google_container_cluster.this.name
}

output "cluster_location" {
  value = google_container_cluster.this.location
}

output "artifact_registry_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo_id}"
}

output "ci_gsa_email" {
  value = google_service_account.ci.email
}

output "github_workload_identity_provider" {
  description = "Value for the workload_identity_provider input of google-github-actions/auth"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --zone ${var.zone} --project ${var.project_id}"
}
