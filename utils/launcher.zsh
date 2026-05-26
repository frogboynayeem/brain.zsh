#!/usr/bin/env zsh
# ============================================================================
# TERMINAL OS v2.1 — Unified Fzf Launcher (tui command)
# ============================================================================
# Keyboard-driven launcher that replaces the need for multiple TUI windows.
# Uses fzf as the core UI engine.
# ============================================================================

_to_launcher() {
  # Ensure fzf keybindings are available
  [[ -z "$_TO_FZF_SOURCED" ]] && {
    source <(fzf --zsh 2>/dev/null) 2>/dev/null && _TO_FZF_SOURCED="true"
  }

  local header="TERMINAL OS v$TERMINAL_OS_VERSION — Unified Launcher"

  local choice=$(printf "%s\n" \
    "📁  Files          yazi — File manager" \
    "🔀  Git            lazygit — Git TUI" \
    "📜  History        atuin — Command history search" \
    "📂  Directories    zoxide — Smart directory jump" \
    "📊  Processes      btop — System monitor" \
    "⚡  Tasks           taskwarrior — Task management" \
    "📅  Calendar        calcurse — Calendar & schedule" \
    "🤖  AI Assistant    ao — AI command router" \
    "🔧  Session         terminal-os session — Session manager" \
    "📖  Cheatsheets     navi — Interactive cheatsheets" \
    "🔄  Tmux/Zellij     Attach to existing session" \
    "❌  Exit" \
    | fzf --header="$header" --prompt="tui> " --height=20 --with-nth=1)

  [[ -z "$choice" ]] && return 0

  case "$choice" in
    *Files*)
      yazi "$PWD"
      ;;
    *Git*)
      lazygit
      ;;
    *History*)
      if command -v atuin &>/dev/null; then
        atuin search --interactive
      else
        fc -l 1 | fzf --prompt="history> " | awk '{$1=""; print substr($0,2)}' | source /dev/stdin
      fi
      ;;
    *Directories*)
      local dir
      dir=$(_to_zoxide_fzf)
      [[ -n "$dir" ]] && cd "$dir"
      ;;
    *Processes*)
      btop
      ;;
    *Tasks*)
      taskwarrior-tui 2>/dev/null || task
      ;;
    *Calendar*)
      calcurse
      ;;
    *AI*)
      _ao_interactive
      ;;
    *Session*)
      "terminal-os" session
      ;;
    *Cheatsheets*)
      navi
      ;;
    *Tmux*|*Zellij*)
      "terminal-os" session attach
      ;;
    *Exit*)
      return 0
      ;;
  esac
}

# ── Zoxide + Fzf Integration ───────────────────────────────────────────────
_to_zoxide_fzf() {
  local dir
  dir=$(zoxide query -l 2>/dev/null | fzf --prompt="jump> " --height=15 --preview="eza --tree -L 1 {}" --preview-window=right:40%)
  echo "$dir"
}

# ── Quick Directory Jumper (wraps zoxide with fzf preview) ─────────────────
_to_jump() {
  local dir
  dir=$(_to_zoxide_fzf)
  [[ -n "$dir" ]] && builtin cd "$dir"
}

# ── Quick File Search (rg + fzf) ───────────────────────────────────────────
_to_search_files() {
  local query="${1:-}"
  if [[ -z "$query" ]]; then
    echo -n "Search for: "
    read -r query
  fi
  [[ -z "$query" ]] && return

  rg --line-number --no-heading --color=always "$query" 2>/dev/null \
    | fzf --prompt="results> " --height=20 --preview="echo {} | awk -F: '{print \$1}' | xargs bat --color=always -n {} 2>/dev/null" \
    | awk -F: '{print $1}' | head -1 | xargs -r nvim
}

# ── Register additional commands ───────────────────────────────────────────
# Jump: j (interactive zoxide with fzf)
j() { _to_jump; }

# File search: ff <pattern>
ff() { _to_search_files "$@"; }