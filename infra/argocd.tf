resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [google_container_cluster.this]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "7.7.11"

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }
}

# Repo-server credentials — the repo is private, so ArgoCD needs a token to
# clone it. Without this, every fresh install hits "authentication required"
# on the very first sync. Sourced from a GitHub Actions secret so this is
# reproducible on every rebuild, not a manual kubectl step to remember.
resource "kubernetes_secret" "private_repo_creds" {
  metadata {
    name      = "private-repo-creds"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.gitops_repo_url
    username = "x-access-token"
    password = var.github_token
  }

  depends_on = [kubernetes_namespace.argocd]
}

# The root Application — this is the only manifest applied outside of Git.
# Once ArgoCD reconciles it, everything under gitops/ in the repo takes over.
resource "kubectl_manifest" "root_application" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "genai-demo"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = "main"
        path           = "gitops"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.app_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })

  depends_on = [helm_release.argocd, kubernetes_secret.private_repo_creds]
}
