# DevPod Coder Template (apexalgo-iad)

Kubernetes-based development workspace template for Coder, designed for the apexalgo-iad cluster.

## Differences from ardenone-cluster version

- **Namespace**: Uses `devpod-apexalgo` instead of `devpod`
- **Storage**: Uses `local-path` storage class instead of `longhorn`
- **Node Selection**: No node selector (can run on any available node)
- **Tolerations**: No tolerations needed (no dedicated taint)
- **Privileged**: Still enabled for Podman-in-container support
- **ImagePullSecret**: Uses `docker-hub-registry` (if available)

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
coder templates push devpod-apexalgo --directory ./devpod-apexalgo
```
