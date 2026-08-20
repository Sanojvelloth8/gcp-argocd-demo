resource "google_artifact_registry_repository" "this" {
  location      = var.region
  repository_id = var.artifact_repo_id
  format        = "DOCKER"
  description   = "Docker images for the genai-demo app"

  depends_on = [google_project_service.apis]
}
