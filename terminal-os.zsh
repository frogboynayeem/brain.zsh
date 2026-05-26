# ============================================================================
# TERMINAL OS v2.1 — Zsh Integration File
# ============================================================================
# Source this from .zshrc to activate the entire system.
#
# Usage: Add ONE line to ~/.zshrc:
#   source ~/.config/terminal-os/terminal-os.zsh
#
# All subsystems are lazily loaded — adding this line adds ~2ms to startup.
# ============================================================================

# ── Guard: only in zsh ─────────────────────────────────────────────────────
[[ -n "$ZSH_VERSION" ]] || return

# ── Bootstrap Core Init (lazy loading) ────────────────────────────────────
source "${XDG_CONFIG_HOME:-$HOME/.config}/terminal-os/core/init.zsh"
source "${XDG_CONFIG_HOME:-$HOME/.config}/terminal-os/utils/helpers.zsh"

# ── Activate fzf Keybindings ───────────────────────────────────────────────
# Only in interactive shells, only if fzf is available
if [[ -o interactive ]] && command -v fzf >/dev/null 2>&1; then
  # Source fzf keybindings and completion
  source <(fzf --zsh 2>/dev/null) 2>/dev/null
  export _TO_FZF_SOURCED="true"
fi

# ── Activate zoxide optimized init ─────────────────────────────────────────
if command -v zoxide >/dev/null 2>&1; then
  # Use --cmd cd so zoxide transparently replaces cd
  eval "$(zoxide init zsh --cmd cd 2>/dev/null)" 2>/dev/null
fi

# ── Activate atuin (if available) ──────────────────────────────────────────
if command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init zsh 2>/dev/null)" 2>/dev/null
fi

# ── Shell Prompt ──────────────────────────────────────────────────────────
# p10k is already configured via ~/.p10k.zsh (sourced from .zshrc)
# We enhance it with TERMINAL OS context

# Add TERMINAL OS version indicator to RPROMPT (conditional)
# Only if we're in a project directory
if [[ -n "$TO_PROJECT_TYPE" ]]; then
  # p10k handles prompt; this just sets an env var p10k can use
  export _TO_PROJECT_LABEL="$TO_PROJECT_TYPE:$TO_PROJECT_SUBTYPE"
fi