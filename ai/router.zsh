#!/usr/bin/env zsh
# ============================================================================
# TERMINAL OS v2.1 — AI Command Router (ao command)
# ============================================================================
# Context-aware AI assistant that enriches prompts with project state.
# Uses Claude Code as the backend. Falls back gracefully if unavailable.
# ============================================================================

# ── Ensure fzf is loaded for interactive mode ──────────────────────────────
[[ -z "$_TO_FZF_SOURCED" ]] && {
  source <(fzf --zsh 2>/dev/null) 2>/dev/null && _TO_FZF_SOURCED="true"
}

# ── Main Router ────────────────────────────────────────────────────────────
_ao_router() {
  local query="$*"

  # Handle empty query
  if [[ -z "$query" ]]; then
    _ao_interactive
    return
  fi

  # Parse flags
  local no_exec=""
  local raw=""
  local args=()

  for arg in "$@"; do
    case "$arg" in
      --no-exec|-n) no_exec="true" ;;
      --raw|-r)     raw="true" ;;
      *)            args+=("$arg") ;;
    esac
  done

  query="${args[*]}"

  # Check for Claude Code
  if ! command -v claude &>/dev/null; then
    echo "⚠ ao requires Claude Code (claude) — not found in PATH"
    echo "  Install: npm install -g @anthropic-ai/claude-code"
    return 1
  fi

  # ── Build context ────────────────────────────────────────────────────────
  _to_project_detect 2>/dev/null

  local context=""
  context+="Current directory: $PWD\n"

  if [[ -n "$TO_PROJECT_TYPE" ]]; then
    context+="Project type: $TO_PROJECT_TYPE:$TO_PROJECT_SUBTYPE\n"
  fi

  if [[ "$TO_GIT_REPO" == "true" ]]; then
    context+="Git branch: $TO_GIT_BRANCH\n"
    if [[ "$TO_GIT_DIRTY" -gt 0 ]]; then
      local git_diff
      git_diff=$(git diff --stat 2>/dev/null | head -10)
      context+="Uncommitted changes:\n$git_diff\n"
    fi
    # Last commit
    local last_commit
    last_commit=$(git log --oneline -3 2>/dev/null)
    context+="Recent commits:\n$last_commit\n"
  fi

  # Check for errors in the last command (from zsh prompt)
  if [[ -n "$?" && "$?" -ne 0 ]]; then
    context+="Last command exit code: $?\n"
    # Get last few lines of terminal output
    local last_output
    last_output=$(fc -l -5 2>/dev/null)
    context+="Last commands:\n$last_output\n"
  fi

  # ── Execute ──────────────────────────────────────────────────────────────
  if [[ -n "$raw" ]]; then
    # Raw mode: just pass query as-is to Claude
    claude --print "$query"
  elif [[ -n "$no_exec" ]]; then
    # No-exec mode: suggest only, don't run
    echo "🔍 Analyzing: $query"
    echo ""
    claude --print "Context:\n$context\n\nQuery: $query\n\nProvide a concise response with suggested commands (prefixed with $). Do NOT execute anything."
  else
    # Normal mode: with safety layer
    echo "🤖 ao: $query"
    echo ""

    # Ask Claude for a command
    local response
    response=$(claude --print "Context:\n$context\n\nTask: $query\n\nIMPORTANT: Respond with ONLY the shell commands needed (one per line, properly escaped). No explanations, no markdown. If multiple steps, prefix each with # step N." 2>/dev/null)

    if [[ -z "$response" ]]; then
      echo "⚠ No response from Claude"
      return 1
    fi

    echo "╔══════════════════════════════════════════╗"
    echo "║  ao — Suggested Commands                   ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "$response"
    echo ""
    echo "Execute? [y]es / [n]o / [e]dit / [v]iew in pager"

    local choice
    echo -n "❯ "
    read -r -k 1 choice
    echo ""

    case "$choice" in
      y|Y)
        echo "⚡ Executing..."
        eval "$response"
        ;;
      e|E)
        echo "Edit command:"
        local edited
        echo -n "❯ "
        read -r edited
        eval "$edited"
        ;;
      v|V)
        echo "$response" | ${PAGER:-less}
        ;;
      *)
        echo "✗ Cancelled"
        return 0
        ;;
    esac
  fi
}

# ── Interactive Mode (no query provided) ───────────────────────────────────
_ao_interactive() {
  echo "╔══════════════════════════════════════════╗"
  echo "║  TERMINAL OS — AI Assistant                ║"
  echo "╠══════════════════════════════════════════╣"
  echo "║  Type your question or request.             ║"
  echo "║  The AI will see your project context.      ║"
  echo "╠══════════════════════════════════════════╣"
  echo "║  Quick actions:                             ║"
  echo "║  • Explain last error                       ║"
  echo "║  • Review recent git changes                ║"
  echo "║  • Start a coding task                      ║"
  echo "║  • Debug a build failure                    ║"
  echo "║                                              ║"
  echo "║  Type 'exit' or Ctrl+C to quit.             ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  while true; do
    echo -n "ao> "
    local input
    read -r input || break
    [[ -z "$input" ]] && continue
    [[ "$input" == "exit" || "$input" == "quit" || "$input" == "q" ]] && break
    _ao_router "$input"
    echo ""
  done
}