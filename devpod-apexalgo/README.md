# DevPod Coder Template (apexalgo-iad)

Kubernetes-based development workspace template for Coder, designed for the apexalgo-iad cluster.

## Cluster-Specific Configuration

| Setting | Value |
|---------|-------|
| Namespace | `devpod` |
| Storage Class | `sata` (Cinder CSI, 5-20GB) or `sata-large` (≥75GB) |
| Node Selector | `app: devpod` |
| Toleration | `workload=devpod:NoSchedule` |

## Differences from ardenone-cluster version

| Setting | ardenone-cluster | apexalgo-iad |
|---------|------------------|---------------|
| Namespace | `devpod` | `devpod` |
| Storage Class | `longhorn` | `sata` (Cinder CSI) |
| Node Selector | `k3s-dell-micro` | `app: devpod` |
| Toleration | `dedicated=coder-workspace:NoSchedule` | `workload=devpod:NoSchedule` |

## Prerequisites

1. **devpod namespace** must exist in apexalgo-iad
2. **docker-hub-registry** secret must be configured (for private images)
3. **devpod node** must be labeled with `app=devpod` and tainted with `workload=devpod:NoSchedule`

## Features
- Persistent Storage: 10-100GB home directory persisted across restarts
- Podman-in-Container: Privileged container with Podman socket access
- Pre-installed Tools:
  - tmux with resurrect & continuum plugins
  - GitHub CLI (gh)
  - Claude Code
  - ccdash
  - MANA
  - Node.js 20.x
  - Python 3
  - kubectl

## Parameters
| Parameter | Description | Default |
|-----------|-------------|---------|
| CPU | Number of CPU cores | 0 (Best Effort) |
| Memory | RAM in GB | 0 (Best Effort) |
| Disk Size | Persistent storage | 40 GB |
| Git Repository | Git repo to clone | (empty) |
| Dotfiles | Personal dotfiles repo | (empty) |
| AI Extensions | Install AI VS Code extensions | true |
| Best Effort Resources | No CPU/memory limits | true |

## Usage
```bash
# Push template to apexalgo-iad Coder instance
coder login https://coder-apexalgo.ardenone.com --session-token <token>
coder templates push devpod-apexalgo --directory ./devpod-apexalgo
```
