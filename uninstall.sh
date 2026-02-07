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
# Remove code-tunnel config from shell config files
###############################################################################
LEGACY_MARKER="# Added by code-tunnel installer"
BEGIN_MARKER="# >>> code-tunnel >>>"
END_MARKER="# <<< code-tunnel <<<"

remove_from_file() {
    local file="$1"
    [[ -f "$file" ]] || return

    local found=false

    # Check for new block-style markers or legacy single-line markers
    if grep -qF "$BEGIN_MARKER" "$file" 2>/dev/null || grep -qF "$LEGACY_MARKER" "$file" 2>/dev/null; then
        found=true
    fi

    [[ "$found" == true ]] || return

    cp "$file" "${file}.code-tunnel-backup"

    # Remove block between >>> and <<< markers, plus any legacy single-line markers
    local tmp="${file}.code-tunnel-tmp"
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v legacy="$LEGACY_MARKER" '
        $0 == begin { skip=1; next }
        $0 == end   { skip=0; next }
        skip { next }
        index($0, legacy) { next }
        1
    ' "$file" > "$tmp"
    mv "$tmp" "$file"

    info "Removed code-tunnel config from $file (backup at ${file}.code-tunnel-backup)"
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
