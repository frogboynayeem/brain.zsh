#!/usr/bin/env zsh
# ============================================================================
# TERMINAL OS v2.1 — Zsh Hooks (cd hook + project detection)
# ============================================================================
# Loaded lazily on first directory change.
# All operations are non-blocking and cached.
# ============================================================================

# ── Project Detection (cached) ─────────────────────────────────────────────
_to_project_detect() {
  # Cache: skip if still in same directory
  [[ "$PWD" == "$_TO_PROJECT_CACHE_DIR" ]] && return
  _TO_PROJECT_CACHE_DIR="$PWD"

  local result
  result=$("$TERMINAL_OS_HOME/core/detect.sh" "$PWD" 2>/dev/null) || result=""

  if [[ -n "$result" ]]; then
    _TO_PROJECT_CACHE="$result"

    # Extract type and subtype
    local type="${result%%:*}"
    local subtype="${result#*:}"

    # Set environment context
    export TO_PROJECT_TYPE="$type"
    export TO_PROJECT_SUBTYPE="$subtype"

    # Git context
    if git rev-parse --git-dir &>/dev/null 2>&1; then
      export TO_GIT_REPO="true"
      export TO_GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
      local dirty=$(git status --porcelain 2>/dev/null | wc -l)
      export TO_GIT_DIRTY="$dirty"
    else
      export TO_GIT_REPO="false"
      export TO_GIT_BRANCH=""
      export TO_GIT_DIRTY=0
    fi
  else
    _TO_PROJECT_CACHE=""
    export TO_PROJECT_TYPE=""
    export TO_PROJECT_SUBTYPE=""
    export TO_GIT_REPO="false"
    export TO_GIT_BRANCH=""
    export TO_GIT_DIRTY=0
  fi
}

# ── Auto-Bootstrap Prompt (safe mode) ──────────────────────────────────────
_to_maybe_bootstrap() {
  # Only in interactive shells
  [[ -o interactive ]] || return
  # Only if project type changed (not on every cd)
  [[ -n "$TO_PROJECT_TYPE" ]] || return
  # Don't auto-bootstrap inside session (user already has a workspace)
  [[ -n "$ZELLIJ" ]] && return

  # If this is a git repo with uncommitted changes, don't auto-launch
  # (user might be mid-workflow)
  [[ "$TO_GIT_DIRTY" -gt 0 && "$TO_GIT_REPO" == "true" ]] && return

  # Only prompt once per project (cache file)
  local cache_key=$(echo "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$PWD" | cksum | cut -d' ' -f1)
  local prompt_file="/tmp/to-bootstrap-$cache_key"
  [[ -f "$prompt_file" ]] && return
  touch "$prompt_file"

  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║  TERMINAL OS — Project Detected           ║"
  echo "╠══════════════════════════════════════════╣"
  printf "║  Type:    %-32s ║\n" "$TO_PROJECT_TYPE:$TO_PROJECT_SUBTYPE"
  [[ -n "$TO_GIT_BRANCH" ]] && printf "║  Branch:  %-32s ║\n" "$TO_GIT_BRANCH"
  [[ "$TO_GIT_DIRTY" -gt 0 ]] && printf "║  Dirty:   %-32s ║\n" "${TO_GIT_DIRTY} files changed"
  echo "╠══════════════════════════════════════════╣"
  echo "║  Commands:                                ║"
  echo "║  [b] Bootstrap workspace (zellij layout)  ║"
  echo "║  [s] Skip (don't ask again)               ║"
  echo "║  [n] No (just cd)                         ║"
  echo "╚══════════════════════════════════════════╝"

  local choice
  echo -n "❯ "
  read -r -k 1 choice
  echo ""

  case "$choice" in
    b|B)
      echo "🚀 Bootstrapping workspace..."
      local session_name=$(basename "$PWD" | tr ' .' '--')
      "terminal-os" session new "$session_name" dev
      ;;
    s|S)
      # Keep prompt file — won't ask again
      echo "✓ Skipped (cached)"
      ;;
    *)
      rm -f "$prompt_file"  # Remove so it asks again on next cd
      echo "ok"
      ;;
  esac
}

# ── Full cd hook (called from chpwd) ──────────────────────────────────────
_to_cd_hook() {
  _to_project_detect
  _to_maybe_bootstrap
}

# ── Export Functions for Subshells ─────────────────────────────────────────
functions[_to_project_detect]=$functions[_to_project_detect]
functions[_to_maybe_bootstrap]=$functions[_to_maybe_bootstrap]
functions[_to_cd_hook]=$functions[_to_cd_hook]