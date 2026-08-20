# GKE Standard, not Autopilot — we pick the node pool size ourselves instead
# of letting Autopilot dynamically provision node shapes per workload. That
# dynamic provisioning is what kept tripping the project's default CPU quota
# (CPUS_ALL_REGIONS, 12 vCPUs) during bootstrap: Autopilot would try several
# different machine shapes across zones, each one a separate quota draw.
# One fixed, right-sized pool avoids that entirely.
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.zone

  # Node pool is managed separately below — this default pool is created and
  # immediately deleted, which is the standard Terraform pattern for GKE (lets
  # the real pool be resized/changed without forcing a cluster replacement).
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = false

  release_channel {
    channel = "REGULAR"
  }

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "primary" {
  name     = "primary"
  cluster  = google_container_cluster.this.name
  location = var.zone

  node_config {
    machine_type = var.node_machine_type
  }

  # Fixed machine type, bounded node count — total CPU draw is predictable
  # and capped (max 2 nodes x 4 vCPU = 8, comfortably under the 12 vCPU
  # project quota) instead of Autopilot's per-shape autoscaling.
  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  depends_on = [google_container_cluster.this]
}
