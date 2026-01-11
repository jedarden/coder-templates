#!/bin/bash
# DevPod Workspace Setup Script
# Location: ~/workspace/start.sh
# This script installs and configures development tools for the workspace.
# It runs on workspace startup and is idempotent (safe to run multiple times).

set -e

echo "=== DevPod Workspace Setup ==="

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install a tool only if not present
install_if_missing() {
    local cmd="$1"
    local name="$2"
    local install_fn="$3"

    if command_exists "$cmd"; then
        echo "[ok] $name already installed"
        return 0
    fi

    echo "[installing] $name..."
    eval "$install_fn"
    echo "[ok] $name installed"
}

# =============================================================================
# Git Configuration
# =============================================================================
echo ""
echo "--- Git Configuration ---"
git config --global --add safe.directory '*' 2>/dev/null || true
git config --global init.defaultBranch main 2>/dev/null || true
echo "[ok] Git configured"

# =============================================================================
# Node.js (required for Claude Code)
# =============================================================================
echo ""
echo "--- Node.js ---"
install_if_missing "node" "Node.js 20.x" '
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null 2>&1
    sudo apt-get install -y -qq nodejs
'

# =============================================================================
# Claude Code
# =============================================================================
echo ""
echo "--- Claude Code ---"
install_if_missing "claude" "Claude Code" '
    sudo npm install -g @anthropic-ai/claude-code >/dev/null 2>&1
'

# =============================================================================
# tmux with plugins
# =============================================================================
echo ""
echo "--- tmux ---"
install_if_missing "tmux" "tmux" '
    sudo apt-get update -qq
    sudo apt-get install -y -qq tmux
'

# Configure tmux plugins
TMUX_DIR="$HOME/.tmux"
if [ ! -d "$TMUX_DIR/plugins/tpm" ]; then
    echo "[configuring] tmux plugins..."
    mkdir -p "$TMUX_DIR/plugins" "$TMUX_DIR/resurrect"
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$TMUX_DIR/plugins/tpm" 2>/dev/null || true

    # Create tmux config if not present
    if [ ! -f "$HOME/.tmux.conf" ]; then
        cat > "$HOME/.tmux.conf" << 'TMUXCONF'
# tmux configuration
set -g history-limit 10000
set -g mouse on
set -g default-terminal "screen-256color"

# Plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# Plugin settings
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'
set -g @resurrect-capture-pane-contents 'on'

# Initialize TPM (keep at bottom)
run-shell '~/.tmux/plugins/tpm/tpm'
TMUXCONF
    fi
    echo "[ok] tmux plugins configured"
else
    echo "[ok] tmux plugins already configured"
fi

# =============================================================================
# GitHub CLI
# =============================================================================
echo ""
echo "--- GitHub CLI ---"
install_if_missing "gh" "GitHub CLI" '
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq gh
'

# =============================================================================
# MANA
# =============================================================================
echo ""
echo "--- MANA ---"
MANA_DIR="$HOME/.mana"
if [ ! -f "$MANA_DIR/mana" ]; then
    echo "[installing] MANA..."
    mkdir -p "$MANA_DIR"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  MANA_ARCH="amd64" ;;
        aarch64|arm64) MANA_ARCH="arm64" ;;
        *) MANA_ARCH="amd64" ;;
    esac
    MANA_URL="https://github.com/jedarden/MANA/releases/latest/download/mana-linux-${MANA_ARCH}"
    curl -fsSL "$MANA_URL" -o "$MANA_DIR/mana" 2>/dev/null || \
        curl -fsSL "https://github.com/jedarden/MANA/releases/latest/download/mana" -o "$MANA_DIR/mana" 2>/dev/null || true
    chmod +x "$MANA_DIR/mana" 2>/dev/null || true

    # Add to PATH if not already
    if ! grep -q 'MANA' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.mana:$PATH"' >> "$HOME/.bashrc"
    fi
    echo "[ok] MANA installed to $MANA_DIR"
else
    echo "[ok] MANA already installed"
fi

# =============================================================================
# ccdash
# =============================================================================
echo ""
echo "--- ccdash ---"
install_if_missing "ccdash" "ccdash" '
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  CCDASH_ARCH="amd64" ;;
        aarch64|arm64) CCDASH_ARCH="arm64" ;;
        *) CCDASH_ARCH="amd64" ;;
    esac
    CCDASH_URL="https://github.com/jedarden/ccdash/releases/latest/download/ccdash-linux-${CCDASH_ARCH}"
    curl -fsSL "$CCDASH_URL" -o /tmp/ccdash 2>/dev/null
    chmod +x /tmp/ccdash
    sudo mv /tmp/ccdash /usr/local/bin/ccdash
'

# =============================================================================
# code-server (VS Code in browser)
# =============================================================================
echo ""
echo "--- code-server ---"
install_if_missing "code-server" "code-server" '
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server >/dev/null 2>&1
    export PATH="/tmp/code-server/bin:$PATH"
'

# =============================================================================
# Podman configuration
# =============================================================================
echo ""
echo "--- Podman Configuration ---"
mkdir -p "$HOME/.config/containers"

# Storage config
if [ ! -f "$HOME/.config/containers/storage.conf" ]; then
    cat > "$HOME/.config/containers/storage.conf" << 'EOF'
[storage]
driver = "overlay"
runroot = "/run/user/1000/containers"
graphroot = "/home/coder/.local/share/containers/storage"

[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"
EOF
    echo "[ok] Podman storage configured"
else
    echo "[ok] Podman storage already configured"
fi

# Registries config
if [ ! -f "$HOME/.config/containers/registries.conf" ]; then
    cat > "$HOME/.config/containers/registries.conf" << 'EOF'
[registries.search]
registries = ['docker.io', 'quay.io', 'ghcr.io']
EOF
    echo "[ok] Podman registries configured"
fi

# Docker alias
if ! grep -q "alias docker=podman" "$HOME/.bashrc" 2>/dev/null; then
    echo 'alias docker=podman' >> "$HOME/.bashrc"
    echo "[ok] Docker alias configured"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Tools installed:"
command_exists node && echo "  - Node.js $(node --version 2>/dev/null || echo 'installed')"
command_exists claude && echo "  - Claude Code"
command_exists tmux && echo "  - tmux (with resurrect & continuum)"
command_exists gh && echo "  - GitHub CLI"
command_exists ccdash && echo "  - ccdash"
[ -f "$HOME/.mana/mana" ] && echo "  - MANA"
command_exists code-server && echo "  - code-server"
command_exists podman && echo "  - Podman"
echo ""
