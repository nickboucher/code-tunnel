#!/usr/bin/env bash
# install.sh — Installer for code-tunnel
# https://github.com/nickboucher/code-tunnel
set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/nickboucher/code-tunnel/main"
DEFAULT_INSTALL_DIR="$HOME/.vscode-tunnel"

###############################################################################
# Helpers
###############################################################################
info()  { echo "[code-tunnel] $*"; }
warn()  { echo "[code-tunnel] WARNING: $*" >&2; }
die()   { echo "[code-tunnel] ERROR: $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install code-tunnel and the VS Code CLI.

Options:
  -d, --dir DIR          Installation directory (default: $DEFAULT_INSTALL_DIR)
  -a, --account ACCOUNT  Default SLURM account (sets CODE_TUNNEL_ACCOUNT)
  -p, --partition PART   Default SLURM partition (sets CODE_TUNNEL_PARTITION)
  -h, --help             Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --dir /opt/code-tunnel
  $(basename "$0") --account myacct --partition gpu
  curl -fsSL $REPO_URL/install.sh | bash
  curl -fsSL $REPO_URL/install.sh | bash -s -- --account myacct --partition gpu
EOF
    exit 0
}

###############################################################################
# Parse arguments
###############################################################################
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
SLURM_ACCOUNT=""
SLURM_PARTITION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)       INSTALL_DIR="$2";    shift 2 ;;
        -a|--account)   SLURM_ACCOUNT="$2";  shift 2 ;;
        -p|--partition) SLURM_PARTITION="$2"; shift 2 ;;
        -h|--help) usage ;;
        *)         die "Unknown option: $1" ;;
    esac
done

# Expand ~ just in case (should already be expanded, but be safe)
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

###############################################################################
# Prompt interactively for missing SLURM settings
# Read from /dev/tty so prompts work even when piped (curl | bash)
###############################################################################
if [[ -z "$SLURM_ACCOUNT" ]]; then
    read -rp "[code-tunnel] Enter your default SLURM account: " SLURM_ACCOUNT </dev/tty
fi
if [[ -z "$SLURM_PARTITION" ]]; then
    read -rp "[code-tunnel] Enter your default SLURM partition: " SLURM_PARTITION </dev/tty
fi

[[ -n "$SLURM_ACCOUNT" ]]   || die "SLURM account is required."
[[ -n "$SLURM_PARTITION" ]] || die "SLURM partition is required."

###############################################################################
# Detect architecture and libc
###############################################################################
detect_platform() {
    local arch os_tag

    case "$(uname -s)" in
        Linux)  ;;
        *)      die "code-tunnel is designed for Linux (SLURM clusters). Detected: $(uname -s)" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)   arch="x64" ;;
        aarch64|arm64)  arch="arm64" ;;
        armv7l|armhf)   arch="armhf" ;;
        *)              die "Unsupported architecture: $(uname -m)" ;;
    esac

    # Detect musl vs glibc
    local libc="linux"
    if ldd --version 2>&1 | grep -qi musl; then
        libc="alpine"
    elif [ -f /etc/alpine-release ]; then
        libc="alpine"
    fi

    echo "cli-${libc}-${arch}"
}

###############################################################################
# Download helper — works with curl or wget
###############################################################################
download() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        die "Neither curl nor wget found. Please install one of them."
    fi
}

###############################################################################
# Main installation
###############################################################################
PLATFORM=$(detect_platform)
info "Detected platform: $PLATFORM"
info "Installing to: $INSTALL_DIR"

# Create directories
mkdir -p "$INSTALL_DIR/bin"

# --- Download & extract VS Code CLI ---
VSCODE_URL="https://code.visualstudio.com/sha/download?build=stable&os=$PLATFORM"
TMPDIR_INSTALL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_INSTALL"' EXIT

info "Downloading VS Code CLI..."
download "$VSCODE_URL" "$TMPDIR_INSTALL/vscode_cli.tar.gz"

info "Extracting VS Code CLI..."
tar -xzf "$TMPDIR_INSTALL/vscode_cli.tar.gz" -C "$INSTALL_DIR/bin"

# The tarball extracts a binary named 'code'
if [[ ! -x "$INSTALL_DIR/bin/code" ]]; then
    die "Expected binary '$INSTALL_DIR/bin/code' not found after extraction."
fi

# --- Download code-tunnel.sh ---
info "Downloading code-tunnel.sh..."
download "$REPO_URL/code-tunnel.sh" "$INSTALL_DIR/code-tunnel.sh"
chmod +x "$INSTALL_DIR/code-tunnel.sh"

# --- Create 'tunnel' shim ---
cat > "$INSTALL_DIR/bin/tunnel" <<SHIM
#!/usr/bin/env bash
exec "$INSTALL_DIR/code-tunnel.sh" "\$@"
SHIM
chmod +x "$INSTALL_DIR/bin/tunnel"

# --- Add to PATH ---
BIN_DIR="$INSTALL_DIR/bin"
PATH_LINE="export PATH=\"$BIN_DIR:\$PATH\"  # Added by code-tunnel installer"
MARKER="# Added by code-tunnel installer"
ACCOUNT_MARKER="# Added by code-tunnel installer (account)"
PARTITION_MARKER="# Added by code-tunnel installer (partition)"

add_to_shell_config() {
    local rc_file="$1"
    if [[ -f "$rc_file" ]] && grep -qF "$MARKER" "$rc_file" 2>/dev/null; then
        info "PATH entry already present in $rc_file"
        return
    fi
    if [[ -f "$rc_file" ]] || [[ "$rc_file" == "$2" ]]; then
        echo "" >> "$rc_file"
        echo "$PATH_LINE" >> "$rc_file"
        info "Added $BIN_DIR to PATH in $rc_file"
    fi
}

# Determine which shell config files to update
SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
UPDATED_ANY=false

case "$SHELL_NAME" in
    bash)
        # Prefer .bashrc for interactive shells; also handle .bash_profile for login shells
        if [[ -f "$HOME/.bashrc" ]]; then
            add_to_shell_config "$HOME/.bashrc" "$HOME/.bashrc"
            UPDATED_ANY=true
        fi
        if [[ -f "$HOME/.bash_profile" ]]; then
            add_to_shell_config "$HOME/.bash_profile" "$HOME/.bash_profile"
            UPDATED_ANY=true
        fi
        if [[ "$UPDATED_ANY" == false ]]; then
            # No existing config — create .bashrc
            add_to_shell_config "$HOME/.bashrc" "$HOME/.bashrc"
            UPDATED_ANY=true
        fi
        ;;
    zsh)
        add_to_shell_config "$HOME/.zshrc" "$HOME/.zshrc"
        UPDATED_ANY=true
        ;;
    fish)
        # Fish uses a different syntax
        FISH_CONFIG="$HOME/.config/fish/config.fish"
        FISH_LINE="set -gx PATH \"$BIN_DIR\" \$PATH  $MARKER"
        mkdir -p "$(dirname "$FISH_CONFIG")"
        if [[ -f "$FISH_CONFIG" ]] && grep -qF "$MARKER" "$FISH_CONFIG" 2>/dev/null; then
            info "PATH entry already present in $FISH_CONFIG"
        else
            echo "" >> "$FISH_CONFIG"
            echo "$FISH_LINE" >> "$FISH_CONFIG"
            info "Added $BIN_DIR to PATH in $FISH_CONFIG"
        fi
        UPDATED_ANY=true
        ;;
    *)
        warn "Unknown shell '$SHELL_NAME'. Please add $BIN_DIR to your PATH manually."
        ;;
esac

# --- Write SLURM defaults to shell config if provided ---
write_env_var() {
    local rc_file="$1" var_name="$2" var_value="$3" marker="$4"
    [[ -z "$var_value" ]] && return
    if [[ -f "$rc_file" ]] && grep -qF "$marker" "$rc_file" 2>/dev/null; then
        # Update existing line
        if sed -i.bak "/$marker/c\\export ${var_name}=\"${var_value}\"  $marker" "$rc_file" 2>/dev/null; then
            rm -f "${rc_file}.bak"
        elif sed -i'' "/$marker/c\\export ${var_name}=\"${var_value}\"  $marker" "$rc_file" 2>/dev/null; then
            :
        fi
        info "Updated $var_name in $rc_file"
    elif [[ -f "$rc_file" ]]; then
        echo "export ${var_name}=\"${var_value}\"  $marker" >> "$rc_file"
        info "Added $var_name=$var_value to $rc_file"
    fi
}

write_fish_env_var() {
    local rc_file="$1" var_name="$2" var_value="$3" marker="$4"
    [[ -z "$var_value" ]] && return
    if [[ -f "$rc_file" ]] && grep -qF "$marker" "$rc_file" 2>/dev/null; then
        if sed -i.bak "/$marker/c\\set -gx ${var_name} \"${var_value}\"  $marker" "$rc_file" 2>/dev/null; then
            rm -f "${rc_file}.bak"
        elif sed -i'' "/$marker/c\\set -gx ${var_name} \"${var_value}\"  $marker" "$rc_file" 2>/dev/null; then
            :
        fi
        info "Updated $var_name in $rc_file"
    elif [[ -f "$rc_file" ]]; then
        echo "set -gx ${var_name} \"${var_value}\"  $marker" >> "$rc_file"
        info "Added $var_name=$var_value to $rc_file"
    fi
}

# Write account/partition to the same shell config files we updated for PATH
case "$SHELL_NAME" in
    bash)
        for rc in "$HOME/.bashrc" "$HOME/.bash_profile"; do
            [[ -f "$rc" ]] || continue
            write_env_var "$rc" CODE_TUNNEL_ACCOUNT   "$SLURM_ACCOUNT"   "$ACCOUNT_MARKER"
            write_env_var "$rc" CODE_TUNNEL_PARTITION "$SLURM_PARTITION" "$PARTITION_MARKER"
        done
        ;;
    zsh)
        write_env_var "$HOME/.zshrc" CODE_TUNNEL_ACCOUNT   "$SLURM_ACCOUNT"   "$ACCOUNT_MARKER"
        write_env_var "$HOME/.zshrc" CODE_TUNNEL_PARTITION "$SLURM_PARTITION" "$PARTITION_MARKER"
        ;;
    fish)
        FISH_CONFIG="$HOME/.config/fish/config.fish"
        write_fish_env_var "$FISH_CONFIG" CODE_TUNNEL_ACCOUNT   "$SLURM_ACCOUNT"   "$ACCOUNT_MARKER"
        write_fish_env_var "$FISH_CONFIG" CODE_TUNNEL_PARTITION "$SLURM_PARTITION" "$PARTITION_MARKER"
        ;;
esac

if [[ "$UPDATED_ANY" == true ]]; then
    info ""
    info "Please restart your shell or run:"
    info "  export PATH=\"$BIN_DIR:\$PATH\""
fi

echo ""
info "============================================"
info " code-tunnel installed successfully!"
info "============================================"
info ""
info "Quick start:"
info "  tunnel 60"
info ""
info "Run 'tunnel --help' for all options."
