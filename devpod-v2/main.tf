terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
}

provider "coder" {}

provider "kubernetes" {
  # Coder provisioner runs in-cluster, no config needed
}

# =============================================================================
# Data Sources
# =============================================================================

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# =============================================================================
# Parameters (User-configurable at workspace creation)
# =============================================================================

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "Number of CPU cores for the workspace"
  icon         = "/icon/memory.svg"
  type         = "number"
  default      = "2"
  mutable      = true
  order        = 1

  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Amount of RAM in gigabytes"
  icon         = "/icon/memory.svg"
  type         = "number"
  default      = "4"
  mutable      = true
  order        = 2

  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Home Disk (GB)"
  description  = "Persistent storage for home directory"
  icon         = "/emojis/1f4be.png"
  type         = "number"
  default      = "20"
  mutable      = false
  order        = 3

  validation {
    min = 10
    max = 100
  }
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git Repository"
  description  = "Repository to clone on startup (optional)"
  icon         = "/icon/git.svg"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 4
}

data "coder_parameter" "dotfiles_repo" {
  name         = "dotfiles_repo"
  display_name = "Dotfiles Repository"
  description  = "Personal dotfiles to apply (optional)"
  icon         = "/icon/dotfiles.svg"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 5
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  namespace     = "devpod"
  storage_class = "longhorn"

  # Workspace naming
  workspace_name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"

  # Container image from private Docker Hub (ronaldraygun)
  # Requires docker-hub-registry imagePullSecret (reflected from kubernetes-reflector)
  workspace_image = "ronaldraygun/coder-workspace:latest"

  # Labels for all resources
  labels = {
    "app.kubernetes.io/name"       = "coder-workspace"
    "app.kubernetes.io/instance"   = local.workspace_name
    "app.kubernetes.io/part-of"    = "coder"
    "app.kubernetes.io/managed-by" = "coder"
    "com.coder.resource"           = "true"
    "com.coder.workspace.id"       = data.coder_workspace.me.id
    "com.coder.workspace.name"     = data.coder_workspace.me.name
    "com.coder.user.id"            = data.coder_workspace_owner.me.id
    "com.coder.user.username"      = data.coder_workspace_owner.me.name
  }
}

# =============================================================================
# Coder Agent
# =============================================================================

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = "/home/coder"

  startup_script_behavior = "blocking"

  startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Configure git
    git config --global --add safe.directory '*'
    git config --global init.defaultBranch main

    # Install code-server if not present
    if ! command -v code-server &> /dev/null; then
      echo "Installing code-server..."
      curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server
      export PATH="/tmp/code-server/bin:$PATH"
    fi

    # Clone repository if specified
    if [ -n "${data.coder_parameter.git_repo.value}" ]; then
      REPO_DIR="$HOME/workspace"
      if [ ! -d "$REPO_DIR/.git" ]; then
        echo "Cloning repository..."
        git clone "${data.coder_parameter.git_repo.value}" "$REPO_DIR" || true
      fi
    fi

    # Apply dotfiles if specified
    if [ -n "${data.coder_parameter.dotfiles_repo.value}" ]; then
      echo "Applying dotfiles..."
      coder dotfiles -y "${data.coder_parameter.dotfiles_repo.value}" || true
    fi

    # Install tmux plugin manager if not present
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
      git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" 2>/dev/null || true
    fi

    # Start code-server (redirect output to close pipes properly)
    echo "Starting code-server..."
    if command -v code-server &> /dev/null; then
      nohup code-server --auth none --port 13337 --host 0.0.0.0 > /tmp/code-server.log 2>&1 &
    else
      nohup /tmp/code-server/bin/code-server --auth none --port 13337 --host 0.0.0.0 > /tmp/code-server.log 2>&1 &
    fi

    echo "Workspace ready!"
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage"
    key          = "mem_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Disk Usage"
    key          = "disk_usage"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 3
  }
}

# =============================================================================
# Coder Apps
# =============================================================================

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337/?folder=/home/coder/workspace"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 10
  }
}

resource "coder_app" "terminal" {
  agent_id     = coder_agent.main.id
  slug         = "terminal"
  display_name = "Terminal"
  icon         = "/icon/terminal.svg"
  command      = "/bin/bash"
}

# =============================================================================
# Kubernetes Resources
# =============================================================================

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "${local.workspace_name}-home"
    namespace = local.namespace
    labels    = local.labels
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.storage_class

    resources {
      requests = {
        storage = "${data.coder_parameter.disk_size.value}Gi"
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_deployment_v1" "main" {
  count            = data.coder_workspace.me.start_count
  wait_for_rollout = false

  metadata {
    name      = local.workspace_name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        "app.kubernetes.io/instance" = local.workspace_name
      }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        # Pull from private Docker Hub using reflected secret
        image_pull_secrets {
          name = "docker-hub-registry"
        }

        security_context {
          run_as_user = 1000
          fs_group    = 1000
        }

        container {
          name              = "workspace"
          image             = local.workspace_image
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]

          security_context {
            run_as_user = 1000
            # Privileged required for Podman-in-container
            privileged = true
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          # Podman environment variables for Kubernetes
          env {
            name  = "CONTAINER_HOST"
            value = "unix:///run/user/1000/podman/podman.sock"
          }

          env {
            name  = "XDG_RUNTIME_DIR"
            value = "/run/user/1000"
          }

          env {
            name  = "BUILDAH_ISOLATION"
            value = "chroot"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "${data.coder_parameter.cpu.value}"
              memory = "${data.coder_parameter.memory.value}Gi"
            }
          }

          volume_mount {
            name       = "home"
            mount_path = "/home/coder"
          }

          # For Podman storage (container images and layers)
          volume_mount {
            name       = "podman-storage"
            mount_path = "/home/coder/.local/share/containers"
          }

          # XDG_RUNTIME_DIR for Podman socket
          volume_mount {
            name       = "podman-run"
            mount_path = "/run/user/1000"
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
          }
        }

        volume {
          name = "podman-storage"
          empty_dir {}
        }

        volume {
          name = "podman-run"
          empty_dir {
            medium = "Memory"
          }
        }

        # Schedule on agent nodes
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "kubernetes.io/role"
                  operator = "In"
                  values   = ["agent"]
                }
              }
            }
          }

          # Spread workspaces across nodes
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim_v1.home]
}
