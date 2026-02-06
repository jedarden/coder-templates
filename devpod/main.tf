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
  description  = "Number of CPU cores for the workspace (only applies when Best Effort is disabled)"
  icon         = "/icon/memory.svg"
  type         = "number"
  default      = "0"
  mutable      = true
  order        = 1

  option {
    name  = "No Limit (Best Effort)"
    value = "0"
  }
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
  description  = "Amount of RAM in gigabytes (only applies when Best Effort is disabled)"
  icon         = "/icon/memory.svg"
  type         = "number"
  default      = "0"
  mutable      = true
  order        = 2

  option {
    name  = "No Limit (Best Effort)"
    value = "0"
  }
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
  default      = "40"
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

data "coder_parameter" "ai_extensions" {
  name         = "ai_extensions"
  display_name = "AI Coding Extensions"
  description  = "Install AI-powered coding assistants in VS Code"
  icon         = "/emojis/1f916.png"
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 6
}

data "coder_parameter" "unlimited_resources" {
  name         = "unlimited_resources"
  display_name = "Best Effort Resources"
  description  = "Use best-effort scheduling (no CPU/memory limits). Disable to set explicit limits."
  icon         = "/emojis/1f680.png"
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 7
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

  # Start script content (installed to ~/start.sh)
  start_script = file("${path.module}/start.sh")

  # Tmux config (installed to ~/.tmux/tmux.conf)
  tmux_config = <<-TMUX
# MANA Workspace tmux configuration

# Scrollback buffer
set -g history-limit 10000

# Mouse mode
set -g mouse on

# Plugin manager (TPM)
set -g @plugin 'tmux-plugins/tpm'

# Session persistence plugins
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# Continuum settings - auto-save and auto-restore
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'

# Resurrect settings
set -g @resurrect-capture-pane-contents 'on'
set -g @resurrect-strategy-vim 'session'

# Store resurrect data in workspace .tmux directory
set -g @resurrect-dir '#{pane_current_path}/.tmux/resurrect'

# Initialize TPM (keep at bottom of config)
run-shell '#{pane_current_path}/.tmux/plugins/tpm/tpm'
TMUX

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

    # ===========================================
    # Minimal bootstrap - let start.sh handle installations
    # ===========================================

    # Fix ownership of XDG_RUNTIME_DIR for Podman
    if [ -d "/run/user/1000" ]; then
      sudo chown -R coder:coder /run/user/1000 2>/dev/null || true
    fi
    mkdir -p /run/user/1000/containers

    # Git configuration
    git config --global --add safe.directory '*'
    git config --global init.defaultBranch main

    # ===========================================
    # Write start.sh and tmux config to home directory
    # ===========================================
    cat > "$HOME/start.sh" << 'STARTSCRIPT'
${local.start_script}
STARTSCRIPT
    chmod +x "$HOME/start.sh"

    # Write tmux config
    mkdir -p "$HOME/.tmux/plugins" "$HOME/.tmux/resurrect"
    cat > "$HOME/.tmux/tmux.conf" << 'TMUXCONF'
${local.tmux_config}
TMUXCONF

    # ===========================================
    # Clone repository if specified
    # ===========================================
    if [ -n "${data.coder_parameter.git_repo.value}" ]; then
      REPO_NAME=$(basename "${data.coder_parameter.git_repo.value}" .git)
      if [ ! -d "$HOME/$REPO_NAME/.git" ]; then
        echo "Cloning repository..."
        git clone "${data.coder_parameter.git_repo.value}" "$HOME/$REPO_NAME" || true
      fi
    fi

    # Apply dotfiles if specified
    if [ -n "${data.coder_parameter.dotfiles_repo.value}" ]; then
      coder dotfiles -y "${data.coder_parameter.dotfiles_repo.value}" || true
    fi

    # ===========================================
    # Instructions
    # ===========================================
    echo ""
    echo "=========================================="
    echo "Workspace bootstrap complete!"
    echo ""
    echo "To install development tools, run:"
    echo "  ~/start.sh"
    echo ""
    echo "This will install:"
    echo "  - Claude Code (with version checking)"
    echo "  - tmux + plugins"
    echo "  - MANA"
    echo "  - kubectl"
    echo "  - code-server (VS Code)"
    echo "=========================================="
    echo ""
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
  url          = "http://localhost:13337/?folder=/home/coder"
  subdomain    = false
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

resource "coder_app" "claude-code" {
  agent_id     = coder_agent.main.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "/emojis/1f916.png"
  command      = "claude"
}

resource "coder_app" "tmux" {
  agent_id     = coder_agent.main.id
  slug         = "tmux"
  display_name = "tmux"
  icon         = "/icon/terminal.svg"
  command      = "tmux new-session -A -s main"
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
            name  = "XDG_RUNTIME_DIR"
            value = "/run/user/1000"
          }

          env {
            name  = "BUILDAH_ISOLATION"
            value = "chroot"
          }

          # Disable Podman socket mode - use direct execution
          env {
            name  = "CONTAINER_HOST"
            value = ""
          }

          dynamic "resources" {
            for_each = data.coder_parameter.unlimited_resources.value == "false" ? [1] : []
            content {
              requests = {
                cpu    = "500m"
                memory = "1Gi"
              }
              limits = merge(
                data.coder_parameter.cpu.value != "0" ? { cpu = "${data.coder_parameter.cpu.value}" } : {},
                data.coder_parameter.memory.value != "0" ? { memory = "${data.coder_parameter.memory.value}Gi" } : {}
              )
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

        # Schedule exclusively on k3s-dell-micro
        node_selector = {
          "kubernetes.io/hostname" = "k3s-dell-micro"
        }

        # Tolerate the dedicated taint on k3s-dell-micro
        toleration {
          key      = "dedicated"
          operator = "Equal"
          value    = "coder-workspace"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim_v1.home]
}
