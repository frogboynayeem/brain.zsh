#!/usr/bin/env zsh
# ============================================================================
# TERMINAL OS v2.1 — Helper Functions & Aliases
# ============================================================================
# Shared utility functions used across the system.
# ============================================================================

# ── Color Output ───────────────────────────────────────────────────────────
_to_color() {
  local color="$1" text="$2"
  case "$color" in
    red)    echo -e "\033[31m$text\033[0m" ;;
    green)  echo -e "\033[32m$text\033[0m" ;;
    yellow) echo -e "\033[33m$text\033[0m" ;;
    blue)   echo -e "\033[34m$text\033[0m" ;;
    dim)    echo -e "\033[2m$text\033[0m" ;;
    bold)   echo -e "\033[1m$text\033[0m" ;;
    *)      echo "$text" ;;
  esac
}

# ── Git Status One-Liner ───────────────────────────────────────────────────
_to_git_status() {
  if git rev-parse --git-dir &>/dev/null 2>&1; then
    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    local dirty=$(git status --porcelain 2>/dev/null | wc -l)
    local ahead=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
    local behind=$(git rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0")
    echo "${branch}${dirty:+ ✗${dirty}}${ahead:+ ↑${ahead}}${behind:+ ↓${behind}}"
  fi
}

# ── Project Info ───────────────────────────────────────────────────────────
_to_project_info() {
  _to_project_detect 2>/dev/null
  echo "TERMINAL OS v$TERMINAL_OS_VERSION"
  echo "Location: $PWD"
  if [[ -n "$TO_PROJECT_TYPE" ]]; then
    echo "Project:  $TO_PROJECT_TYPE:$TO_PROJECT_SUBTYPE"
  fi
  if [[ "$TO_GIT_REPO" == "true" ]]; then
    echo "Git:      branch=$TO_GIT_BRANCH dirty=$TO_GIT_DIRTY"
  fi
  if [[ -n "$ZELLIJ" ]]; then
    echo "Session:  $ZELLIJ"
  fi
}

# ── Quick Edit (open in neovim with line number) ──────────────────────────
_to_edit() {
  if [[ -z "$1" ]]; then
    # Use fzf to pick a file
    local file
    file=$(fd --type f --hidden --exclude .git --exclude node_modules 2>/dev/null | fzf --prompt="edit> " --height=20 --preview="bat --color=always {} 2>/dev/null")
    [[ -n "$file" ]] && nvim "$file"
  else
    nvim "$@"
  fi
}

# ── Quick Directory Contents (eza with fzf preview) ────────────────────────
_to_ls() {
  eza --icons --group-directories-first -la "$@" | fzf --prompt="ls> " --height=20 --preview="echo {} | awk '{print \$NF}' | xargs bat --color=always 2>/dev/null || echo {}"
}

# ── Find Process ───────────────────────────────────────────────────────────
_to_ps() {
  ps aux | fzf --prompt="ps> " --height=15 --header-lines=1 | awk '{print $2}' | xargs -r echo "PID: "
}

# ── Quick Directory Jumper (zoxide + fzf) ──────────────────────────────────
j() {
  local dir
  dir=$(zoxide query -l 2>/dev/null | fzf --prompt="jump> " --height=15 --preview="eza --tree -L 1 {} 2>/dev/null" --preview-window=right:40%)
  [[ -n "$dir" ]] && builtin cd "$dir"
}


# ── Quick File Search (rg + fzf) ───────────────────────────────────────────
ff() {
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


# ── Aliases ────────────────────────────────────────────────────────────────
alias e='_to_edit'              # Quick file edit
alias l='_to_ls'                # Interactive ls
alias gs='_to_git_status'       # Git status one-liner
alias pj='_to_project_info'     # Project info
alias psf='_to_ps'              # Find process