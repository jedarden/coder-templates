#!/bin/bash
# DevPod Tool Installation Script for Coder Workspaces
set -e

echo "🚀 Starting tool installation..."

# Configure Git safe directories
echo "🔧 Configuring Git..."
git config --global --add safe.directory '*'
git config --global init.defaultBranch main

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install and start Docker (Docker-in-Docker)
echo "🐳 Setting up Docker..."
if ! command_exists docker; then
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker coder
    echo "✅ Docker installed"
else
    echo "✅ Docker already installed"
fi

# Start Docker daemon if not running
if ! pgrep -x "dockerd" > /dev/null; then
    echo "🐳 Starting Docker daemon..."
    sudo dockerd > /var/log/dockerd.log 2>&1 &
    # Wait for Docker to be ready
    for i in $(seq 1 30); do
        if docker info >/dev/null 2>&1; then
            echo "✅ Docker daemon started"
            break
        fi
        sleep 1
    done
else
    echo "✅ Docker daemon already running"
fi

# Install tmux if not present
echo "📦 Checking tmux..."
if ! command_exists tmux; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq tmux
    echo "✅ tmux installed"
else
    echo "✅ tmux already installed"
fi

# Configure tmux with plugins
TMUX_DIR="$HOME/.tmux"
if [ ! -d "$TMUX_DIR/plugins/tpm" ]; then
    echo "🔧 Configuring tmux..."
    mkdir -p "$TMUX_DIR/plugins" "$TMUX_DIR/resurrect"

    # Install TPM
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$TMUX_DIR/plugins/tpm" 2>/dev/null || true

    # Create tmux config
    cat > "$HOME/.tmux.conf" << 'EOF'
set -g history-limit 10000
set -g mouse on
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'
set -g @resurrect-capture-pane-contents 'on'
run-shell '~/.tmux/plugins/tpm/tpm'
EOF
    echo "✅ tmux configured"
fi

# Install GitHub CLI
echo "📦 Checking GitHub CLI..."
if ! command_exists gh; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq gh
    echo "✅ GitHub CLI installed"
else
    echo "✅ GitHub CLI already installed"
fi

# Install Node.js if not present (needed for claude-code)
echo "📦 Checking Node.js..."
if ! command_exists node; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y -qq nodejs
    echo "✅ Node.js installed"
else
    echo "✅ Node.js already installed ($(node --version))"
fi

# Install Claude Code
echo "📦 Checking Claude Code..."
if ! command_exists claude; then
    sudo npm install -g @anthropic-ai/claude-code
    echo "✅ Claude Code installed"
else
    echo "✅ Claude Code already installed"
fi

# Install ccdash
echo "📦 Checking ccdash..."
if ! command_exists ccdash; then
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  CCDASH_ARCH="amd64" ;;
        aarch64|arm64) CCDASH_ARCH="arm64" ;;
        *) CCDASH_ARCH="$ARCH" ;;
    esac

    CCDASH_URL="https://github.com/jedarden/ccdash/releases/latest/download/ccdash-linux-${CCDASH_ARCH}"
    curl -fsSL "$CCDASH_URL" -o /tmp/ccdash
    chmod +x /tmp/ccdash
    sudo mv /tmp/ccdash /usr/local/bin/ccdash
    echo "✅ ccdash installed"
else
    echo "✅ ccdash already installed"
fi

# Install MANA
echo "📦 Checking MANA..."
MANA_DIR="$HOME/.mana"
if [ ! -f "$MANA_DIR/mana" ]; then
    mkdir -p "$MANA_DIR"
    MANA_URL="https://github.com/jedarden/MANA/releases/latest/download/mana"
    curl -fsSL "$MANA_URL" -o "$MANA_DIR/mana"
    chmod +x "$MANA_DIR/mana"
    echo "✅ MANA installed to $MANA_DIR"
else
    echo "✅ MANA already installed"
fi

# Install code-server for VS Code in browser
echo "📦 Checking code-server..."
if ! command_exists code-server; then
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/usr/local
    echo "✅ code-server installed"
else
    echo "✅ code-server already installed"
fi

# Start code-server in background
echo "🖥️ Starting code-server..."
if ! pgrep -x "code-server" > /dev/null; then
    code-server --auth none --port 13337 --host 0.0.0.0 &
    echo "✅ code-server started on port 13337"
else
    echo "✅ code-server already running"
fi

# Install VS Code extensions
echo "📦 Installing VS Code extensions..."
code-server --install-extension ms-python.python 2>/dev/null || true
code-server --install-extension dbaeumer.vscode-eslint 2>/dev/null || true
code-server --install-extension esbenp.prettier-vscode 2>/dev/null || true
code-server --install-extension hashicorp.terraform 2>/dev/null || true
code-server --install-extension redhat.vscode-yaml 2>/dev/null || true
code-server --install-extension ms-azuretools.vscode-docker 2>/dev/null || true

echo ""
echo "=========================================="
echo "  🎉 Development Environment Ready!"
echo "=========================================="
echo ""
echo "Installed tools:"
echo "  - Docker (Docker-in-Docker)"
echo "  - tmux (with resurrect & continuum)"
echo "  - GitHub CLI (gh)"
echo "  - Claude Code"
echo "  - ccdash"
echo "  - MANA"
echo "  - code-server (VS Code)"
echo ""
