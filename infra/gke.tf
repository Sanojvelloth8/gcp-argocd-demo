resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.zone

  enable_autopilot    = true
  deletion_protection = false

  release_channel {
    channel = "REGULAR"
  }

  depends_on = [google_project_service.apis]
}
