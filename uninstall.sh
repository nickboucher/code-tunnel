#!/usr/bin/env bash
# uninstall.sh — Uninstaller for code-tunnel
# https://github.com/nickboucher/code-tunnel
set -euo pipefail

DEFAULT_INSTALL_DIR="$HOME/.vscode-tunnel"

###############################################################################
# Helpers
###############################################################################
info() { echo "[code-tunnel] $*"; }
warn() { echo "[code-tunnel] WARNING: $*" >&2; }
die()  { echo "[code-tunnel] ERROR: $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Uninstall code-tunnel and the VS Code CLI.

Options:
  -d, --dir DIR    Installation directory (default: $DEFAULT_INSTALL_DIR)
  -h, --help       Show this help message
EOF
    exit 0
}

###############################################################################
# Parse arguments
###############################################################################
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)  INSTALL_DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *)         die "Unknown option: $1" ;;
    esac
done

INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

###############################################################################
# Remove PATH entries from shell config files
###############################################################################
MARKER="# Added by code-tunnel installer"

remove_from_file() {
    local file="$1"
    if [[ -f "$file" ]] && grep -qF "$MARKER" "$file" 2>/dev/null; then
        # Create a backup, then remove all lines containing any code-tunnel marker
        cp "$file" "${file}.code-tunnel-backup"
        if sed -i.bak "/$MARKER/d" "$file" 2>/dev/null; then
            rm -f "${file}.bak"
        elif sed -i'' "/$MARKER/d" "$file" 2>/dev/null; then
            :
        else
            grep -vF "$MARKER" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
        fi
        info "Removed code-tunnel entries from $file (backup at ${file}.code-tunnel-backup)"
    fi
}

# Check all common shell config files
for rc_file in \
    "$HOME/.bashrc" \
    "$HOME/.bash_profile" \
    "$HOME/.zshrc" \
    "$HOME/.config/fish/config.fish" \
    "$HOME/.profile"; do
    remove_from_file "$rc_file"
done

###############################################################################
# Remove installed files
###############################################################################
if [[ -d "$INSTALL_DIR" ]]; then
    info "Removing $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    info "Removed $INSTALL_DIR"
else
    warn "Install directory $INSTALL_DIR not found — nothing to remove."
fi

echo ""
info "============================================"
info " code-tunnel uninstalled successfully."
info "============================================"
info ""
info "Please restart your shell to update your PATH."
