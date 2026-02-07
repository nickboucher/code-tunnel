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
  -a, --account ACCOUNT  Default SLURM account
  -p, --partition PART   Default SLURM partition
      --cpus N           Default CPUs per task
      --gpus GRES        Default GPU resource spec
      --mem MEM          Default memory (e.g. 16G)
      --qos QOS          Default quality of service
      --nodes N          Default number of nodes
      --ntasks N         Default number of tasks
  -h, --help             Show this help message

If not provided as flags, the installer will prompt interactively
for SLURM defaults.

Examples:
  $(basename "$0")
  $(basename "$0") --account myacct --partition gpu --qos high
  curl -fsSL $REPO_URL/install.sh | bash
EOF
    exit 0
}

###############################################################################
# Parse arguments
###############################################################################
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
SLURM_ACCOUNT=""
SLURM_PARTITION=""
SLURM_CPUS=""
SLURM_GPUS=""
SLURM_MEM=""
SLURM_QOS=""
SLURM_NODES=""
SLURM_NTASKS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)       INSTALL_DIR="$2";    shift 2 ;;
        -a|--account)   SLURM_ACCOUNT="$2";  shift 2 ;;
        -p|--partition) SLURM_PARTITION="$2"; shift 2 ;;
        --cpus)         SLURM_CPUS="$2";     shift 2 ;;
        --gpus)         SLURM_GPUS="$2";     shift 2 ;;
        --mem)          SLURM_MEM="$2";       shift 2 ;;
        --qos)          SLURM_QOS="$2";       shift 2 ;;
        --nodes)        SLURM_NODES="$2";     shift 2 ;;
        --ntasks)       SLURM_NTASKS="$2";    shift 2 ;;
        -h|--help) usage ;;
        *)         die "Unknown option: $1" ;;
    esac
done

# Expand ~ just in case (should already be expanded, but be safe)
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

###############################################################################
# Prompt interactively for SLURM defaults
# Read from /dev/tty so prompts work even when piped (curl | bash)
###############################################################################
prompt_default() {
    local var_name="$1" prompt_text="$2" required="${3:-false}" current_val="$4"
    if [[ -n "$current_val" ]]; then
        echo "$current_val"
        return
    fi
    local val=""
    if [[ "$required" == true ]]; then
        while [[ -z "$val" ]]; do
            read -rp "[code-tunnel] $prompt_text: " val </dev/tty
            [[ -n "$val" ]] || echo "[code-tunnel] This field is required." >/dev/tty
        done
    else
        read -rp "[code-tunnel] $prompt_text (press Enter to skip): " val </dev/tty
    fi
    echo "$val"
}

info ""
info "Configure default SLURM settings"
info "(these can always be overridden per-invocation with flags)"
info ""

SLURM_ACCOUNT=$(prompt_default  CODE_TUNNEL_ACCOUNT   "SLURM account (required)"       true  "$SLURM_ACCOUNT")
SLURM_PARTITION=$(prompt_default CODE_TUNNEL_PARTITION "SLURM partition (required)"     true  "$SLURM_PARTITION")
SLURM_QOS=$(prompt_default      CODE_TUNNEL_QOS       "Quality of service (QOS)"        false "$SLURM_QOS")
SLURM_CPUS=$(prompt_default     CODE_TUNNEL_CPUS      "CPUs per task [default: 2]"      false "$SLURM_CPUS")
SLURM_GPUS=$(prompt_default     CODE_TUNNEL_GPUS      "GPU GRES spec [default: gpu:1]"  false "$SLURM_GPUS")
SLURM_MEM=$(prompt_default      CODE_TUNNEL_MEM       "Memory (e.g. 16G)"               false "$SLURM_MEM")
SLURM_NODES=$(prompt_default    CODE_TUNNEL_NODES     "Nodes [default: 1]"              false "$SLURM_NODES")
SLURM_NTASKS=$(prompt_default   CODE_TUNNEL_NTASKS    "Tasks [default: 1]"              false "$SLURM_NTASKS")

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

    echo "cli-alpine-${arch}"
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

# --- Add to PATH and write SLURM defaults to shell config ---
BIN_DIR="$INSTALL_DIR/bin"
MARKER="# Added by code-tunnel installer"
BEGIN_MARKER="# >>> code-tunnel >>>"
END_MARKER="# <<< code-tunnel <<<"

###############################################################################
# Build the config block
###############################################################################
build_bash_block() {
    local lines=()
    lines+=("$BEGIN_MARKER")
    lines+=("export PATH=\"$BIN_DIR:\$PATH\"")
    [[ -n "$SLURM_ACCOUNT" ]]   && lines+=("export CODE_TUNNEL_ACCOUNT=\"$SLURM_ACCOUNT\"")
    [[ -n "$SLURM_PARTITION" ]] && lines+=("export CODE_TUNNEL_PARTITION=\"$SLURM_PARTITION\"")
    [[ -n "$SLURM_QOS" ]]       && lines+=("export CODE_TUNNEL_QOS=\"$SLURM_QOS\"")
    [[ -n "$SLURM_CPUS" ]]      && lines+=("export CODE_TUNNEL_CPUS=\"$SLURM_CPUS\"")
    [[ -n "$SLURM_GPUS" ]]      && lines+=("export CODE_TUNNEL_GPUS=\"$SLURM_GPUS\"")
    [[ -n "$SLURM_MEM" ]]       && lines+=("export CODE_TUNNEL_MEM=\"$SLURM_MEM\"")
    [[ -n "$SLURM_NODES" ]]     && lines+=("export CODE_TUNNEL_NODES=\"$SLURM_NODES\"")
    [[ -n "$SLURM_NTASKS" ]]    && lines+=("export CODE_TUNNEL_NTASKS=\"$SLURM_NTASKS\"")
    lines+=("$END_MARKER")
    printf '%s\n' "${lines[@]}"
}

build_fish_block() {
    local lines=()
    lines+=("$BEGIN_MARKER")
    lines+=("set -gx PATH \"$BIN_DIR\" \$PATH")
    [[ -n "$SLURM_ACCOUNT" ]]   && lines+=("set -gx CODE_TUNNEL_ACCOUNT \"$SLURM_ACCOUNT\"")
    [[ -n "$SLURM_PARTITION" ]] && lines+=("set -gx CODE_TUNNEL_PARTITION \"$SLURM_PARTITION\"")
    [[ -n "$SLURM_QOS" ]]       && lines+=("set -gx CODE_TUNNEL_QOS \"$SLURM_QOS\"")
    [[ -n "$SLURM_CPUS" ]]      && lines+=("set -gx CODE_TUNNEL_CPUS \"$SLURM_CPUS\"")
    [[ -n "$SLURM_GPUS" ]]      && lines+=("set -gx CODE_TUNNEL_GPUS \"$SLURM_GPUS\"")
    [[ -n "$SLURM_MEM" ]]       && lines+=("set -gx CODE_TUNNEL_MEM \"$SLURM_MEM\"")
    [[ -n "$SLURM_NODES" ]]     && lines+=("set -gx CODE_TUNNEL_NODES \"$SLURM_NODES\"")
    [[ -n "$SLURM_NTASKS" ]]    && lines+=("set -gx CODE_TUNNEL_NTASKS \"$SLURM_NTASKS\"")
    lines+=("$END_MARKER")
    printf '%s\n' "${lines[@]}"
}

###############################################################################
# Write (or replace) the config block in a shell rc file
###############################################################################
write_config_block() {
    local rc_file="$1" block="$2"

    if [[ -f "$rc_file" ]] && grep -qF "$BEGIN_MARKER" "$rc_file" 2>/dev/null; then
        # Remove existing block and replace
        local tmp="${rc_file}.code-tunnel-tmp"
        awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
            $0 == begin { skip=1; next }
            $0 == end   { skip=0; next }
            !skip
        ' "$rc_file" > "$tmp"
        echo "" >> "$tmp"
        echo "$block" >> "$tmp"
        mv "$tmp" "$rc_file"
        info "Updated code-tunnel config in $rc_file"
    else
        # Also clean up any legacy single-line markers from older installs
        if [[ -f "$rc_file" ]] && grep -qF "$MARKER" "$rc_file" 2>/dev/null; then
            local tmp="${rc_file}.code-tunnel-tmp"
            grep -vF "$MARKER" "$rc_file" > "$tmp"
            mv "$tmp" "$rc_file"
        fi
        echo "" >> "$rc_file"
        echo "$block" >> "$rc_file"
        info "Added code-tunnel config to $rc_file"
    fi
}

###############################################################################
# Determine the shell config file and write
###############################################################################
SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
UPDATED_RC=""

case "$SHELL_NAME" in
    bash)
        # Write to .bashrc if it exists (preferred), else .bash_profile, else create .bashrc
        if [[ -f "$HOME/.bashrc" ]]; then
            UPDATED_RC="$HOME/.bashrc"
        elif [[ -f "$HOME/.bash_profile" ]]; then
            UPDATED_RC="$HOME/.bash_profile"
        else
            UPDATED_RC="$HOME/.bashrc"
            touch "$UPDATED_RC"
        fi
        write_config_block "$UPDATED_RC" "$(build_bash_block)"
        ;;
    zsh)
        UPDATED_RC="$HOME/.zshrc"
        [[ -f "$UPDATED_RC" ]] || touch "$UPDATED_RC"
        write_config_block "$UPDATED_RC" "$(build_bash_block)"
        ;;
    fish)
        FISH_CONFIG="$HOME/.config/fish/config.fish"
        mkdir -p "$(dirname "$FISH_CONFIG")"
        [[ -f "$FISH_CONFIG" ]] || touch "$FISH_CONFIG"
        write_config_block "$FISH_CONFIG" "$(build_fish_block)"
        UPDATED_RC="$FISH_CONFIG"
        ;;
    *)
        warn "Unknown shell '$SHELL_NAME'. Please add $BIN_DIR to your PATH manually."
        ;;
esac

if [[ -n "$UPDATED_RC" ]]; then
    info ""
    info "Please restart your shell or run:"
    info "  source $UPDATED_RC"
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
