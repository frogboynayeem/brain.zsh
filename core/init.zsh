#!/usr/bin/env zsh
# ============================================================================
# TERMINAL OS v2.1 — Automation Core — Initialization
# ============================================================================
# This is the main entry point. Source this from .zshrc.
# It loads all subsystems with lazy initialization for startup performance.
# ============================================================================

export TERMINAL_OS_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/terminal-os"
export TERMINAL_OS_VERSION="2.1"
export TERMINAL_OS_LAYOUTS="$TERMINAL_OS_HOME/layouts"
export TERMINAL_OS_SESSIONS="$TERMINAL_OS_HOME/sessions"
export TERMINAL_OS_AI="$TERMINAL_OS_HOME/ai"

# ── Runtime State ──────────────────────────────────────────────────────────
export _TO_LAST_DIR=""               # last directory for cd hook comparison
export _TO_SESSION_ACTIVE=""         # currently attached session
export _TO_PROJECT_CACHE=""          # cached project type
export _TO_PROJECT_CACHE_DIR=""      # dir the cache is valid for
export _TO_FZF_SOURCED=""            # flag: fzf keybindings loaded

# ── Path Setup ─────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin/terminal-os:$PATH"

# ── Lazy-Loaded Components ─────────────────────────────────────────────────
# These are only loaded when their command is first invoked.
# This keeps shell startup under 50ms.

# Session manager: terminal-os session ...
terminal-os() {
  if [[ "${1:-}" == "session" ]]; then
    source "$TERMINAL_OS_HOME/core/session.zsh"
    _to_session "${@:2}"
  else
    # Delegate to the external binary for bootstrap, status, help, etc.
    command terminal-os "$@"
  fi
}

# AI command router: ao ...
ao() {
  source "$TERMINAL_OS_HOME/ai/router.zsh"
  _ao_router "$@"
}

# Unified launcher: tui
tui() {
  source "$TERMINAL_OS_HOME/utils/launcher.zsh"
  _to_launcher
}

# ── Project Detection Hook (pre-cd hook) ──────────────────────────────────
autoload -Uz add-zsh-hook

_to_cd_hook() {
  # Skip if pwd didn't change (noop cd)
  [[ "$PWD" == "$_TO_LAST_DIR" ]] && return
  _TO_LAST_DIR="$PWD"

  # Source hooks module on first directory change
  source "$TERMINAL_OS_HOME/core/hooks.zsh"
  _to_project_detect
}

add-zsh-hook chpwd _to_cd_hook
# Fire for initial directory
_TO_LAST_DIR="$PWD"