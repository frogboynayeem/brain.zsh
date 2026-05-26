#!/usr/bin/env bash
# ============================================================================
# TERMINAL OS v2.1 — Uninstall Script
# ============================================================================
# Safely removes all TERMINAL OS components and restores .zshrc.
#
# Usage: ./uninstall.sh [--force]
# ============================================================================

set -euo pipefail

echo "TERMINAL OS v2.1 — Uninstall"
echo "=============================="
echo ""

# ── Check backup ──────────────────────────────────────────────────────────
BACKUP_POSTFIX=".pre-terminal-os.bak"

restore_zshrc() {
    if [[ -f "$HOME/.zshrc$BACKUP_POSTFIX" ]]; then
        echo "Restoring .zshrc from backup..."
        cp "$HOME/.zshrc$BACKUP_POSTFIX" "$HOME/.zshrc"
        echo "✓ .zshrc restored"
    fi
}

remove_integration_line() {
    local file="$1"
    local marker="# TERMINAL OS v2.1"
    if [[ -f "$file" ]]; then
        grep -v "terminal-os.zsh" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
        echo "✓ Removed TERMINAL OS integration from $file"
    fi
}

# ── Remove files ──────────────────────────────────────────────────────────
remove_dirs() {
    local dirs=(
        "$HOME/.config/terminal-os"
        "$HOME/.local/bin/terminal-os"
    )

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "Removing $dir..."
            rm -rf "$dir"
            echo "✓ Removed"
        fi
    done
}

# ── Main ──────────────────────────────────────────────────────────────────
FORCE="${1:-}"
if [[ "$FORCE" != "--force" ]]; then
    echo "This will remove TERMINAL OS v2.1 from your system."
    echo "  - ~/.config/terminal-os/    (all configs, hooks, layouts)"
    echo "  - ~/.local/bin/terminal-os/  (scripts)"
    echo "  - Integration lines from .zshrc"
    echo ""
    echo -n "Continue? [y/N] "
    read -r choice
    [[ "$choice" != "y" && "$choice" != "Y" ]] && echo "Cancelled." && exit 0
fi

echo ""
echo "Uninstalling..."

# Remove zsh integration marker if present
remove_integration_line "$HOME/.zshrc"

# Remove all terminal-os directories
remove_dirs

echo ""
echo "✓ TERMINAL OS v2.1 has been removed."
echo ""
echo "To complete:"
echo "  1. Reload your shell: exec zsh"
echo "  2. Or remove any remaining references from ~/.zshrc"