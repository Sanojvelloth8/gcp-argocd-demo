# Bucket/prefix are passed via -backend-config at init time (see README) rather
# than hardcoded here, so the same config works for both local and CI runs
# without a project ID baked into a tracked file.
terraform {
  backend "gcs" {}
}
