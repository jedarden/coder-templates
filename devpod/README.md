# DevPod Coder Template

Kubernetes-based development workspace template for Coder, based on the ardenone-cluster devcontainer configuration.

## Features

- **Persistent Storage**: 10GB home directory persisted across restarts
- **Docker-in-Docker**: Privileged container with Docker socket access
- **VS Code in Browser**: code-server pre-configured and accessible via Coder
- **Pre-installed Tools**:
  - tmux with resurrect & continuum plugins
  - GitHub CLI (gh)
  - Claude Code
  - ccdash
  - MANA
  - Node.js 20.x
  - Python 3

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| CPU | Number of CPU cores | 2 |
| Memory | RAM in GB | 4 |
| Repository | Git repo to clone | ardenone-cluster |
| Dotfiles | Personal dotfiles repo | (empty) |

## Usage

### Adding to Coder

```bash
# From Coder CLI
coder templates create devpod --directory ./templates/devpod

# Or update existing
coder templates push devpod --directory ./templates/devpod
```

### Creating a Workspace

```bash
coder create my-workspace --template devpod
```

## Architecture

```
┌─────────────────────────────────────────────┐
│  Kubernetes Pod (devpod namespace)          │
│  ┌────────────────────────────────────────┐ │
│  │  Container: dev                        │ │
│  │  Image: codercom/enterprise-base       │ │
│  │  ┌──────────────────────────────────┐  │ │
│  │  │  code-server (port 13337)        │  │ │
│  │  │  coder agent                     │  │ │
│  │  │  tmux, gh, claude, ccdash, mana  │  │ │
│  │  └──────────────────────────────────┘  │ │
│  └────────────────────────────────────────┘ │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │  PVC: home   │  │  ConfigMap: scripts│   │
│  │  (10Gi)      │  │  install-tools.sh  │   │
│  └──────────────┘  └────────────────────┘   │
└─────────────────────────────────────────────┘
```

## Customization

### Adding More Tools

Edit `install-tools.sh` to add additional tools to the installation process.

### Changing the Base Image

Modify the `image` field in `main.tf` to use a different base image:
- `codercom/enterprise-base:ubuntu` (default)
- `mcr.microsoft.com/devcontainers/base:debian12`
- Custom image with tools pre-baked

### Resource Limits

Adjust the parameter validation blocks in `main.tf` to allow more CPU/memory.
