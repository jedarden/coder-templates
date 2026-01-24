#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_DIR="$SCRIPT_DIR/.tmux"
TMUX_CONF="$TMUX_DIR/tmux.conf"
TPM_DIR="$TMUX_DIR/plugins/tpm"
MANA_DIR="$HOME/.mana"
MANA_BIN="$MANA_DIR/mana"
MANA_REPO="jedarden/MANA"

# Phonetic alphabet for tmux session naming
PHONETIC_ALPHABET=(
    "alpha" "bravo" "charlie" "delta" "echo" "foxtrot" "golf" "hotel"
    "india" "juliet" "kilo" "lima" "mike" "november" "oscar" "papa"
    "quebec" "romeo" "sierra" "tango" "uniform" "victor" "whiskey"
    "xray" "yankee" "zulu"
)

# Find the first available phonetic name for a tmux session
find_available_session_name() {
    for name in "${PHONETIC_ALPHABET[@]}"; do
        if ! tmux has-session -t "$name" 2>/dev/null; then
            echo "$name"
            return 0
        fi
    done
    return 1
}

# Install tmux if not present
install_tmux() {
    echo "Installing tmux..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y tmux
    elif command -v yum &>/dev/null; then
        sudo yum install -y tmux
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y tmux
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm tmux
    elif command -v brew &>/dev/null; then
        brew install tmux
    else
        echo "Error: Could not determine package manager to install tmux."
        exit 1
    fi
}

# Install TPM (Tmux Plugin Manager) and plugins
install_tpm() {
    if [[ ! -d "$TPM_DIR" ]]; then
        echo "Installing Tmux Plugin Manager..."
        git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    fi
}

# Install tmux plugins
install_plugins() {
    if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
        echo "Installing tmux plugins..."
        "$TPM_DIR/bin/install_plugins"
    fi
}

# Install kubectl if not present
install_kubectl() {
    echo "Installing kubectl..."
    local KUBECTL_VERSION
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

    # Detect architecture
    local ARCH
    case "$(uname -m)" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) echo "Error: Unsupported architecture $(uname -m)"; return 1 ;;
    esac

    # Download kubectl
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
    chmod +x kubectl

    # Install to /usr/local/bin or ~/.local/bin
    if [[ -w /usr/local/bin ]]; then
        mv kubectl /usr/local/bin/kubectl
    elif sudo -n true 2>/dev/null; then
        sudo mv kubectl /usr/local/bin/kubectl
    else
        mkdir -p "$HOME/.local/bin"
        mv kubectl "$HOME/.local/bin/kubectl"
        echo "kubectl installed to ~/.local/bin - ensure it's in your PATH"
    fi
}

# Install mana from GitHub releases
install_mana() {
    echo "Installing mana..."
    mkdir -p "$MANA_DIR"

    # Detect OS and architecture
    local OS ARCH ASSET_NAME
    case "$(uname -s)" in
        Linux) OS="linux" ;;
        Darwin) OS="darwin" ;;
        *) echo "Error: Unsupported OS $(uname -s)"; return 1 ;;
    esac

    case "$(uname -m)" in
        x86_64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        *) echo "Error: Unsupported architecture $(uname -m)"; return 1 ;;
    esac

    ASSET_NAME="mana-${OS}-${ARCH}.tar.gz"
    local TEMP_DIR
    TEMP_DIR=$(mktemp -d)

    # Download latest release using gh if available, otherwise curl
    if command -v gh &>/dev/null; then
        gh release download --repo "$MANA_REPO" -p "$ASSET_NAME" -D "$TEMP_DIR" --clobber
    else
        # Get latest release tag
        LATEST_TAG=$(curl -s "https://api.github.com/repos/$MANA_REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ -z "$LATEST_TAG" ]]; then
            echo "Error: Could not determine latest mana release."
            rm -rf "$TEMP_DIR"
            return 1
        fi
        curl -L -o "$TEMP_DIR/$ASSET_NAME" "https://github.com/$MANA_REPO/releases/download/$LATEST_TAG/$ASSET_NAME"
    fi

    # Extract the tarball
    if [[ -f "$TEMP_DIR/$ASSET_NAME" ]]; then
        tar -xzf "$TEMP_DIR/$ASSET_NAME" -C "$TEMP_DIR"
        # Find and move the mana binary
        if [[ -f "$TEMP_DIR/mana" ]]; then
            mv "$TEMP_DIR/mana" "$MANA_BIN"
        elif [[ -f "$TEMP_DIR/mana-${OS}-${ARCH}/mana" ]]; then
            mv "$TEMP_DIR/mana-${OS}-${ARCH}/mana" "$MANA_BIN"
        else
            # Search for mana binary in extracted contents
            local FOUND_BIN
            FOUND_BIN=$(find "$TEMP_DIR" -name "mana" -type f -executable 2>/dev/null | head -1)
            if [[ -n "$FOUND_BIN" ]]; then
                mv "$FOUND_BIN" "$MANA_BIN"
            else
                echo "Error: Could not find mana binary in extracted archive."
                rm -rf "$TEMP_DIR"
                return 1
            fi
        fi
    else
        echo "Error: Failed to download $ASSET_NAME"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    rm -rf "$TEMP_DIR"
    chmod +x "$MANA_BIN"
    echo "mana installed to $MANA_BIN"
}

# Start mana daemon if not running
start_mana_daemon() {
    if "$MANA_BIN" daemon status &>/dev/null; then
        echo "mana daemon is already running."
    else
        echo "Starting mana daemon..."
        "$MANA_BIN" daemon start
    fi
}

# Check and install tmux if needed
if ! command -v tmux &>/dev/null; then
    install_tmux
    if ! command -v tmux &>/dev/null; then
        echo "Error: Failed to install tmux."
        exit 1
    fi
fi

# Check if git is installed (needed for TPM)
if ! command -v git &>/dev/null; then
    echo "Error: git is not installed. Please install git first."
    exit 1
fi

# Check and install kubectl if needed
if ! command -v kubectl &>/dev/null; then
    install_kubectl
    if ! command -v kubectl &>/dev/null; then
        echo "Warning: Failed to install kubectl. Continuing without it."
    fi
fi

# Install or update Claude Code using native installer
install_claude_code() {
    echo "Installing/updating Claude Code via native installer..."
    curl -fsSL https://claude.ai/install.sh | bash
}

# Get installed Claude Code version (returns empty string if not installed)
get_installed_claude_version() {
    if command -v claude &>/dev/null; then
        claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    fi
}

# Get latest available Claude Code version
get_latest_claude_version() {
    local CLAUDE_RELEASES_URL="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/latest"
    curl -fsSL "$CLAUDE_RELEASES_URL" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Compare semantic versions: returns 0 if v1 < v2, 1 otherwise
version_lt() {
    local v1="$1" v2="$2"
    # If versions are equal, return false (not less than)
    [[ "$v1" == "$v2" ]] && return 1
    # Sort versions and check if v1 comes first
    local lowest
    lowest=$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)
    [[ "$v1" == "$lowest" ]]
}

# Check if Claude Code needs installation or update
check_and_update_claude() {
    local installed_version latest_version

    # Ensure PATH includes common install location
    if [[ -x "$HOME/.claude/local/bin/claude" ]]; then
        export PATH="$HOME/.claude/local/bin:$PATH"
    fi

    installed_version=$(get_installed_claude_version)
    latest_version=$(get_latest_claude_version)

    if [[ -z "$installed_version" ]]; then
        echo "Claude Code not found. Installing..."
        install_claude_code
        # Source profile to get updated PATH
        if [[ -f "$HOME/.bashrc" ]]; then
            source "$HOME/.bashrc" 2>/dev/null || true
        fi
        if [[ -f "$HOME/.zshrc" ]]; then
            source "$HOME/.zshrc" 2>/dev/null || true
        fi
        # Check common install locations
        if [[ -x "$HOME/.claude/local/bin/claude" ]]; then
            export PATH="$HOME/.claude/local/bin:$PATH"
        fi
        if ! command -v claude &>/dev/null; then
            echo "Error: Claude Code installation failed."
            exit 1
        fi
        echo "Claude Code installed successfully: $(get_installed_claude_version)"
    elif [[ -z "$latest_version" ]]; then
        echo "Warning: Could not fetch latest Claude Code version. Skipping update check."
        echo "Current version: $installed_version"
    elif version_lt "$installed_version" "$latest_version"; then
        echo "Claude Code update available: $installed_version -> $latest_version"
        install_claude_code
        local new_version
        new_version=$(get_installed_claude_version)
        echo "Claude Code updated: $installed_version -> $new_version"
    else
        echo "Claude Code is up to date: $installed_version"
    fi
}

check_and_update_claude

# Ensure tmux config directory exists
mkdir -p "$TMUX_DIR/plugins"
mkdir -p "$TMUX_DIR/resurrect"

# Install TPM and plugins if needed
install_tpm
install_plugins

# Install mana if not present
if [[ ! -x "$MANA_BIN" ]]; then
    install_mana
    if [[ ! -x "$MANA_BIN" ]]; then
        echo "Warning: Failed to install mana. Continuing without it."
    fi
fi

# Start mana daemon if mana is installed
if [[ -x "$MANA_BIN" ]]; then
    start_mana_daemon
fi

# Source updated config for any existing tmux server
if tmux list-sessions &>/dev/null; then
    echo "Updating tmux configuration..."
    tmux source-file "$TMUX_CONF" 2>/dev/null || true
fi

# Find an available session name
SESSION_NAME=$(find_available_session_name)

if [[ -z "$SESSION_NAME" ]]; then
    echo "Error: All phonetic alphabet session names are in use (alpha through zulu)."
    echo "Please close an existing tmux session and try again."
    exit 1
fi

# Create the tmux session with our config and start claude code
echo "Creating tmux session: $SESSION_NAME"
tmux -f "$TMUX_CONF" new-session -d -s "$SESSION_NAME" -c "$SCRIPT_DIR"
tmux send-keys -t "$SESSION_NAME" "claude --dangerously-skip-permissions" Enter

# Attach to the session
echo "Attaching to session: $SESSION_NAME"
tmux -f "$TMUX_CONF" attach-session -t "$SESSION_NAME"

