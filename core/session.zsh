#!/usr/bin/env zsh
# ============================================================================
# TERMINAL OS v2.1 — Session Manager (backed by zellij)
# ============================================================================

_to_session() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  case "$cmd" in
    new|create)
      _to_session_new "$@"
      ;;
    attach|a)
      _to_session_attach "$@"
      ;;
    list|ls)
      _to_session_list
      ;;
    kill|stop)
      _to_session_kill "$@"
      ;;
    rename)
      _to_session_rename "$@"
      ;;
    help|--help|-h)
      echo "TERMINAL OS Session Manager"
      echo ""
      echo "USAGE:"
      echo "  terminal-os session new [name] [layout]   Create new session"
      echo "  terminal-os session attach [name]          Attach to session"
      echo "  terminal-os session list                   List all sessions"
      echo "  terminal-os session kill [name]             Kill a session"
      echo "  terminal-os session rename [old] [new]     Rename session"
      echo ""
      echo "EXAMPLES:"
      echo "  terminal-os session new myproject          Creates 'myproject'"
      echo "  terminal-os session new myproject dev      ...with dev layout"
      echo "  terminal-os session attach                 Fzf picker"
      echo "  terminal-os session ls"
      ;;
    *)
      echo "terminal-os session: unknown command '$cmd'"
      echo "Try: terminal-os session help"
      return 1
      ;;
  esac
}

# ── Create Session ─────────────────────────────────────────────────────────
_to_session_new() {
  local name="$1"
  local layout="${2:-dev}"

  if [[ -z "$name" ]]; then
    # Auto-name from current directory
    name=$(basename "$PWD" | tr ' .' '--')
  fi

  # Validate layout
  local layout_file="$TERMINAL_OS_LAYOUTS/$layout.kdl"
  if [[ ! -f "$layout_file" ]]; then
    echo "⚠ Layout '$layout' not found at $layout_file"
    echo "  Available layouts:"
    ls "$TERMINAL_OS_LAYOUTS/"*.kdl 2>/dev/null | sed 's/.*\///; s/\.kdl$//' | while read l; do echo "    - $l"; done
    return 1
  fi

  echo "🚀 Creating session '$name' with layout '$layout'..."
  zellij --session "$name" --layout "$layout_file" --attach

  _TO_SESSION_ACTIVE="$name"
}

# ── Attach to Session ──────────────────────────────────────────────────────
_to_session_attach() {
  local name="$1"

  if [[ -z "$name" ]]; then
    # Fzf picker
    local sessions
    sessions=$(zellij list-sessions 2>/dev/null)
    if [[ -z "$sessions" ]]; then
      echo "No active sessions."
      echo "Create one: terminal-os session new <name>"
      return 1
    fi
    name=$(echo "$sessions" | fzf --prompt="Attach session> " --height=10)
    [[ -z "$name" ]] && return 1
    name=$(echo "$name" | awk '{print $1}')
  fi

  zellij attach "$name"
  _TO_SESSION_ACTIVE="$name"
}

# ── List Sessions ─────────────────────────────────────────────────────────
_to_session_list() {
  local sessions
  sessions=$(zellij list-sessions 2>/dev/null)
  if [[ -z "$sessions" ]]; then
    echo "No active sessions."
    return 0
  fi
  echo "Active Sessions:"
  echo "$sessions" | while read line; do
    local name=$(echo "$line" | awk '{print $1}')
    echo "  📌 $line"
  done
}

# ── Kill Session ──────────────────────────────────────────────────────────
_to_session_kill() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: terminal-os session kill <name>"
    _to_session_list
    return 1
  fi
  zellij kill-session "$name" 2>/dev/null && echo "✓ Session '$name' killed" || echo "✗ Session '$name' not found"
}

# ── Rename Session ────────────────────────────────────────────────────────
_to_session_rename() {
  local old="$1" new="$2"
  if [[ -z "$old" || -z "$new" ]]; then
    echo "Usage: terminal-os session rename <old-name> <new-name>"
    return 1
  fi
  zellij rename-session "$old" "$new" 2>/dev/null && echo "✓ Renamed '$old' -> '$new'" || echo "✗ Failed to rename"
}