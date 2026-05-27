#!/usr/bin/env zsh
# ============================================================================
# BRAIN — Unified, Context-Aware CLI Layer  v1.0
# ============================================================================
# Source this file from .zshrc. Startup: ~30ms. Everything else is lazy.
#
#   source /path/to/brain.zsh
#   export BRAIN_AI_MODEL=openrouter/hermes   # opencode requires provider/model format
# ============================================================================

# === BOOTSTRAP ===
[[ -n $_BRAIN_BOOTSTRAP_LOADED ]] && return
_BRAIN_BOOTSTRAP_LOADED=1

# Version guard: zsh 5.3+ for associative arrays
[[ $ZSH_VERSION < 5.3 ]] && echo "brain: requires zsh 5.3+" && return

# ── Global cache ───────────────────────────────────────────────────────────
typeset -gA _BRAIN_CACHE
typeset -gA _BRAIN_PROJECT_TYPE
typeset -gA _BRAIN_PROJECT_RUN
typeset -gA _BRAIN_PROJECT_TEST
typeset -gA _BRAIN_PROJECT_BUILD
typeset -gA _BRAIN_FAIL_COUNT
typeset -gA _BRAIN_FAIL_EXIT
typeset -ga _BRAIN_COMMAND_STACK
_BRAIN_LAST_EXIT=0
_BRAIN_LAST_PWD=""
_BRAIN_AI_BIN=""
_BRAIN_AI_MODEL=""
_BRAIN_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/brain/projects"
_BRAIN_START_TIME=$EPOCHREALTIME 2>/dev/null || _BRAIN_START_TIME=""

# Module loaded flags
typeset -gA _BRAIN_MODULES
_BRAIN_MODULES=(detection 0 history 0 navigation 0 git 0 project 0 ai 0 modes 0 interface 0 commands 0)

# ── Marker: nothing else runs at source time ───────────────────────────────

# ── Load persistent cache ──────────────────────────────────────────────────
_BRAIN_CACHE_FILE="${_BRAIN_CACHE_FILE:-${XDG_CACHE_HOME:-$HOME/.cache}/brain/projects}"
[[ -f "$_BRAIN_CACHE_FILE" ]] && {
  local _dir _type _run _test _build
  while IFS='|' read -r _dir _type _run _test _build; do
    [[ -n "$_dir" ]] || continue
    _BRAIN_PROJECT_TYPE[$_dir]="$_type"
    [[ -n "$_run"   ]] && _BRAIN_PROJECT_RUN[$_dir]="$_run"
    [[ -n "$_test"  ]] && _BRAIN_PROJECT_TEST[$_dir]="$_test"
    [[ -n "$_build" ]] && _BRAIN_PROJECT_BUILD[$_dir]="$_build"
  done < "$_BRAIN_CACHE_FILE"
}


# === DETECTION ===
_brain_detection_load() {
  [[ ${_BRAIN_MODULES[detection]} -eq 1 ]] && return
  _BRAIN_MODULES[detection]=1

  _BRAIN_OS=$(uname -s)
  _BRAIN_KERNEL=$(uname -r)
  _BRAIN_ARCH=$(uname -m)

  _brain_has() { command -v "$1" >/dev/null 2>&1; }

  _brain_os_like() {
    case "$_BRAIN_OS" in
      Linux)  echo "linux" ;;
      Darwin) echo "macos" ;;
      *)      echo "other" ;;
    esac
  }
}

# === HISTORY ===
_brain_history_load() {
  [[ ${_BRAIN_MODULES[history]} -eq 1 ]] && return
  _BRAIN_MODULES[history]=1
  _brain_detection_load

  _brain_history_search() {
    local q="$1"
    if _brain_has atuin; then
      if [[ -n "$q" ]]; then
        atuin search --interactive "$q" 2>/dev/null
      else
        atuin search --interactive 2>/dev/null
      fi
    else
      if [[ -n "$q" ]]; then
        fc -l 0 -1 2>/dev/null | grep -i -- "$q" | tail -30
      else
        fc -l 0 -1 2>/dev/null | tail -30
      fi
    fi
  }

  _brain_history_last() {
    fc -l -1 -1 2>/dev/null | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//'
  }
}

# === NAVIGATION ===
_brain_navigation_load() {
  [[ ${_BRAIN_MODULES[navigation]} -eq 1 ]] && return
  _BRAIN_MODULES[navigation]=1
  _brain_detection_load

  _brain_jump() {
    local dir
    if _brain_has zoxide; then
      if [[ -z "$1" ]]; then
        dir=$(zoxide query -l 2>/dev/null | fzf --prompt="jump> " --height=15 2>/dev/null)
        [[ -n "$dir" ]] && builtin cd "$dir"
      else
        zoxide query "$@" 2>/dev/null && builtin cd "$(zoxide query "$@")" 2>/dev/null || echo "  ✗ no match"
      fi
    else
      if [[ -n "$1" ]]; then
        builtin cd "$1" 2>/dev/null || echo "  ✗ no such directory"
      fi
    fi
  }

  _brain_dirs() {
    if _brain_has zoxide; then
      zoxide query -l 2>/dev/null | head -20
    else
      dirs -v 2>/dev/null | head -10
    fi
  }
}

# === GIT ===
_brain_git_load() {
  [[ ${_BRAIN_MODULES[git]} -eq 1 ]] && return
  _BRAIN_MODULES[git]=1
  _brain_detection_load

  _brain_git_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
  }

  _brain_git_dirty() {
    git status --porcelain 2>/dev/null | wc -l | tr -d ' '
  }

  _brain_git_log() {
    git log --oneline --graph --max-count=10 2>/dev/null
  }

  _brain_git_status_short() {
    local branch dirty
    branch=$(_brain_git_branch)
    dirty=$(_brain_git_dirty)
    [[ -z "$branch" ]] && return
    echo "$branch${dirty:+ ±$dirty}"
  }

  _brain_git_show() {
    if _brain_has lazygit; then
      lazygit
    else
      git status -sb
    fi
  }

  _brain_git_diff() {
    git diff --stat 2>/dev/null | head -15
  }
}

# === PROJECT ===
_brain_project_load() {
  [[ ${_BRAIN_MODULES[project]} -eq 1 ]] && return
  _BRAIN_MODULES[project]=1
  _brain_detection_load

  _brain_project_detect() {
    local dir="$1" type="" run="" test="" build=""
    # Check cache — return immediately with cached value
    if [[ -n "${_BRAIN_PROJECT_TYPE[$dir]}" ]]; then
      return
    fi

    # Walk up from dir to find project root
    local check="$dir"
    while [[ "$check" != "/" ]]; do
      if [[ -f "$check/Cargo.toml" ]]; then
        type="rust"; run="cargo run"; test="cargo test"; build="cargo build"; break
      elif [[ -f "$check/package.json" ]]; then
        type="node"; run="npm run dev"; test="npm test"; build="npm run build"
        break
      elif [[ -f "$check/pyproject.toml" ]]; then
        type="python"; run="python3 -m $(grep -oP 'module\s*=\s*\"\K[^\"]+' "$check/pyproject.toml" 2>/dev/null || echo 'main')"
        test="pytest"; build=""; break
      elif [[ -f "$check/requirements.txt" ]]; then
        type="python"; run="python3 main.py"; test="pytest"; build=""; break
      elif [[ -f "$check/go.mod" ]]; then
        type="go"; run="go run ."; test="go test ./..."; build="go build"; break
      elif [[ -f "$check/docker-compose.yml" || -f "$check/docker-compose.yaml" ]]; then
        type="docker"; run="docker compose up"; test=""; build=""; break
      elif [[ -d "$check/.git" ]]; then
        type="git"; run=""; test=""; build=""; break
      fi
      check=$(dirname "$check")
    done

    if [[ -n "$type" ]]; then
      _BRAIN_PROJECT_TYPE[$dir]="$type"
      [[ -n "$run"   ]] && _BRAIN_PROJECT_RUN[$dir]="$run"
      [[ -n "$test"  ]] && _BRAIN_PROJECT_TEST[$dir]="$test"
      [[ -n "$build" ]] && _BRAIN_PROJECT_BUILD[$dir]="$build"
      _brain_cache_save
    fi
  }

  # Cache invalidation helper
  _brain_project_invalidate() {
    _BRAIN_PROJECT_TYPE[$PWD]=""
    _BRAIN_PROJECT_RUN[$PWD]=""
    _BRAIN_PROJECT_TEST[$PWD]=""
    _BRAIN_PROJECT_BUILD[$PWD]=""
  }

  # ── Persistent cache ─────────────────────────────────────────────────────
  _brain_cache_load() {
    [[ -f "$_BRAIN_CACHE_FILE" ]] || return
    local dir type run test build
    while IFS='|' read -r dir type run test build; do
      [[ -n "$dir" ]] || continue
      _BRAIN_PROJECT_TYPE[$dir]="$type"
      [[ -n "$run"   ]] && _BRAIN_PROJECT_RUN[$dir]="$run"
      [[ -n "$test"  ]] && _BRAIN_PROJECT_TEST[$dir]="$test"
      [[ -n "$build" ]] && _BRAIN_PROJECT_BUILD[$dir]="$build"
    done < "$_BRAIN_CACHE_FILE"
  }

  _brain_cache_save() {
    mkdir -p "$(dirname "$_BRAIN_CACHE_FILE")"
    : > "$_BRAIN_CACHE_FILE"
    local k
    for k in "${(@k)_BRAIN_PROJECT_TYPE}"; do
      print -r -- "$k|$_BRAIN_PROJECT_TYPE[$k]|$_BRAIN_PROJECT_RUN[$k]|$_BRAIN_PROJECT_TEST[$k]|$_BRAIN_PROJECT_BUILD[$k]"
    done >> "$_BRAIN_CACHE_FILE"
  }

  _brain_cache_clear() {
    _BRAIN_PROJECT_TYPE=()
    _BRAIN_PROJECT_RUN=()
    _BRAIN_PROJECT_TEST=()
    _BRAIN_PROJECT_BUILD=()
    rm -f "$_BRAIN_CACHE_FILE"
    echo "  Cache cleared"
  }
}

# === AI ===
_brain_ai_load() {
  [[ ${_BRAIN_MODULES[ai]} -eq 1 ]] && return
  _BRAIN_MODULES[ai]=1
  _brain_detection_load

  _brain_ai_detect() {
    [[ -n "$_BRAIN_AI_BIN" ]] && return 0
    for bin in opencode claude llm; do
      if _brain_has "$bin"; then
        _BRAIN_AI_BIN="$bin"
        return 0
      fi
    done
    return 1
  }

  _brain_ai_model_flag() {
    local model="${1:-$BRAIN_AI_MODEL}"
    [[ -z "$model" ]] && return
    # Warn if model name lacks provider/ prefix (opencode requires provider/model format)
    if [[ "$model" != */* ]]; then
      echo "  ${_BRAIN_YELLOW}⚠ BRAIN_AI_MODEL='$model' may be invalid.${_BRAIN_RESET}" >&2
      echo "  ${_BRAIN_DIM}  opencode requires provider/model format, e.g. openrouter/hermes${_BRAIN_RESET}" >&2
    fi
    case "$_BRAIN_AI_BIN" in
      opencode) echo "--model $model" ;;
      claude)   echo "--model $model" ;;
      llm)      echo "-m $model" ;;
    esac
  }

  _brain_ai_build_context() {
    local prompt="" dir="$PWD"
    _brain_project_load
    _brain_git_load

    _brain_project_detect "$dir"
    local ptype="${_BRAIN_PROJECT_TYPE[$dir]}"
    [[ -n "$ptype" ]] && prompt+="[project: $ptype] "

    if git rev-parse --git-dir >/dev/null 2>&1; then
      local branch=$(_brain_git_branch)
      local dirty=$(_brain_git_dirty)
      prompt+="[branch: $branch${dirty:+ | dirty: $dirty files}] "
      # Last 3 commits
      prompt+="[commits: $(git log --oneline -3 2>/dev/null | tr '\n' '; ')] "
    fi

    # Last command
    _brain_history_load
    local last_cmd=$(_brain_history_last)
    prompt+="[last command: $last_cmd | exit: $_BRAIN_LAST_EXIT] "

    # File tree (shallow)
    if _brain_has fd; then
      prompt+="[files: $(fd --max-depth 2 --type f 2>/dev/null | head -30 | tr '\n' ' ')] "
    else
      prompt+="[files: $(find . -maxdepth 2 -type f 2>/dev/null | head -20 | tr '\n' ' ')] "
    fi

    echo "$prompt"
  }

  _brain_ai_query() {
    _brain_ai_detect || {
      echo "  ✗ No AI CLI detected."
      echo "    Install one: opencode / claude / llm"
      return 1
    }

    local model="" file="" query=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --model) shift; model="$1" ;;
        --file)  shift; file="$1" ;;
        *)       query+="$1 " ;;
      esac
      shift
    done

    local context=$(_brain_ai_build_context)
    local model_flag=$(_brain_ai_model_flag "$model")
    local full_prompt="$context"

    if [[ -n "$file" && -f "$file" ]]; then
      full_prompt+="\n\n-- File: $file --\n$(head -200 "$file")\n-- end --\n"
    fi

    [[ -n "$query" ]] && full_prompt+="\n\n$query"

    # Invoke detected AI
    case "$_BRAIN_AI_BIN" in
      opencode)
        local args=()
        [[ -n "$file" && -f "$file" ]] && args+=(--file "$file")
        [[ -n "$model_flag" ]] && args+=(${=model_flag})
        # Restore stderr in case brain fix captured it (opencode outputs to stderr)
        opencode run "${args[@]}" "$full_prompt" 2>&${_BRAIN_STDERR_SAVE:-1}
        ;;
      claude)
        echo "$full_prompt" | claude $model_flag --print -
        ;;
      llm)
        echo "$full_prompt" | llm $model_flag -
        ;;
    esac
  }
}

# === ERROR PARSING ===
_brain_error_load() {
  [[ ${_BRAIN_MODULES[error]} -eq 1 ]] && return
  _BRAIN_MODULES[error]=1

  _brain_parse_error() {
    local stderr="$1" exit_code="$2" line file msg
    local found=0

    while IFS= read -r line; do
      # Rust
      if [[ "$line" =~ 'error\[E[0-9]+\]:[[:space:]](.*)' ]]; then
        msg="${match[1]}"
        # Next line has the file reference: --> src/file.rs:LINE:COL
        IFS= read -r loc
        if [[ "$loc" =~ '-->[[:space:]]([^:]+):([0-9]+):([0-9]+)' ]]; then
          file="${match[1]}"; local ln="${match[2]}"
          echo "  Rust error at line ${ln}:${match[3]}"
          echo "  File: $file:$ln"
          echo "  $msg"
          found=1
        fi
      # Node/TS
      elif [[ "$line" =~ 'at[[:space:]]Object\.<anonymous>[[:space:]]\(([^:]+):([0-9]+):([0-9]+)\)' ]]; then
        file="${match[1]}"; local ln="${match[2]}"
        msg="${line#*at }"
        echo "  JS/TS error"
        echo "  File: $file:$ln"
        echo "  $msg"
        found=1
      # Python
      elif [[ "$line" =~ 'File[[:space:]]+"([^"]+)",[[:space:]]+line[[:space:]]+([0-9]+)' ]]; then
        file="${match[1]}"; local ln="${match[2]}"
        echo "  Python error"
        echo "  File: $file:$ln"
        found=1
      # Go
      elif [[ "$line" =~ '([^:]+)\.go:([0-9]+):([0-9]+):[[:space:]]*(.*)' ]]; then
        file="${match[1]}.go"; local ln="${match[2]}"
        msg="${match[4]}"
        echo "  Go error"
        echo "  File: $file:$ln"
        echo "  $msg"
        found=1
      # Shell: command not found
      elif [[ "$line" =~ '([^:]+):[[:space:]]command[[:space:]]not[[:space:]]found' ]]; then
        echo "  Shell: command not found — ${match[1]}"
        echo "  Install it or check PATH/typo"
        found=1
      # Shell: permission denied
      elif [[ "$line" =~ '[Pp]ermission[[:space:]]denied' ]]; then
        echo "  Permission denied — try: chmod +x <file> or check ownership"
        found=1
      # Shell: syntax error
      elif [[ "$line" =~ 'syntax[[:space:]]error' ]]; then
        echo "  Shell syntax error — check quotes, braces, brackets"
        found=1
      fi
    done <<< "$stderr"

    [[ $found -eq 0 ]] && echo "  Unknown error (exit $exit_code)"
    return $found
  }

  _brain_error_fix() {
    local stderr="$1" exit_code="$2"
    # Check for autonomous trigger
    if [[ ${_BRAIN_FAIL_COUNT[$PWD]} -ge 3 && ${_BRAIN_FAIL_EXIT[$PWD]} -eq $exit_code ]]; then
      local pattern=""
      if [[ "$stderr" =~ "not found" || "$stderr" =~ "No such file" ]]; then
        pattern="missing_dependency"
      elif [[ "$stderr" =~ "Permission denied" ]]; then
        pattern="permission"
      elif [[ "$stderr" =~ "port.*in use" || "$stderr" =~ "EADDRINUSE" ]]; then
        pattern="port_in_use"
      fi

      if [[ -n "$pattern" ]]; then
        _brain_interface_warn
        echo "  ⚡ SUGGESTION: Persistent error detected ($pattern)"
        echo "  Exit code $exit_code, ${_BRAIN_FAIL_COUNT[$PWD]} consecutive failures"
        echo ""
        echo -n "  Run auto-fix? [y/N] "
        local resp; read -r resp
        [[ "$resp" == "y" || "$resp" == "Y" ]] && _brain_auto_suggest_fix "$pattern"
        return
      fi
    fi

    echo ""
    echo "  [o] open file in editor"
    echo "  [c] copy error to clipboard"
    echo "  [a] ask AI"
    echo -n "  ❯ "
    local action; read -r action
    case "$action" in
      o|O)
        local target=$(echo "$stderr" | grep -oP '(/[^:]+):\d+' | head -1)
        [[ -n "$target" ]] && ${EDITOR:-vi} "$target" || echo "  ✗ could not extract file path"
        ;;
      c|C)
        if _brain_has wl-copy; then
          echo "$stderr" | wl-copy && echo "  ✓ copied"
        elif _brain_has xclip; then
          echo "$stderr" | xclip -selection clipboard && echo "  ✓ copied"
        else
          echo "$stderr" | head -20
        fi
        ;;
      a|A)
        _brain_ai_load
        _brain_ai_query "Explain this error and suggest a fix: $stderr"
        ;;
    esac
  }

  _brain_auto_suggest_fix() {
    local pattern="$1"
    case "$pattern" in
      missing_dependency)
        echo "  Run: npm install  or  pip install -r requirements.txt"
        echo -n "  Execute? [y/N] "
        local resp; read -r resp
        [[ "$resp" == "y" || "$resp" == "Y" ]] && {
          [[ -f package.json ]] && npm install
          [[ -f requirements.txt ]] && pip install -r requirements.txt
          [[ -f Cargo.toml ]] && cargo build
        }
        ;;
      permission)
        echo "  Try: chmod +x on the target file"
        ;;
      port_in_use)
        echo "  Try: kill the process using the port"
        local port=$(echo "$stderr" | grep -oP 'port\s+\K[0-9]+' | head -1)
        [[ -n "$port" ]] && echo "  Port $port may be in use. Run: lsof -i :$port"
        ;;
    esac
  }
}

# === PLUGINS ===
_brain_plugin_cmd() {
  _brain_detection_load
  _brain_interface_load
  local action="${1:-list}"
  shift 2>/dev/null || true

  case "$action" in
    list)
      _brain_interface_header "PLUGINS"
      local dir="${_BRAIN_PLUGIN_DIR:-$HOME/.config/brain/plugins}"
      local plugins=($dir/*.zsh(N))
      if [[ ${#plugins} -eq 0 ]]; then
        echo "  No plugins loaded"
        echo "  Add .zsh files to $dir"
      else
        for p in $plugins; do
          echo "  $(basename $p .zsh)"
        done
      fi
      _brain_interface_hr
      ;;
    load)
      local name="$1"
      [[ -z "$name" ]] && { echo "  Usage: brain plugin load <name>"; return; }
      local dir="${_BRAIN_PLUGIN_DIR:-$HOME/.config/brain/plugins}"
      local file="$dir/$name.zsh"
      if [[ -f "$file" ]]; then
        source "$file" && echo "  ✓ loaded $name" || echo "  ✗ failed to load $name"
      else
        echo "  ✗ plugin not found: $name"
        echo "  Expected: $file"
      fi
      ;;
    *)
      echo "  brain plugin: unknown action '$action'"
      echo "  Usage: brain plugin [list|load <name>]"
      ;;
  esac
}

# === INTERFACE ===
_brain_interface_load() {
  [[ ${_BRAIN_MODULES[interface]} -eq 1 ]] && return
  _BRAIN_MODULES[interface]=1

  _BRAIN_CYAN=$'\033[36m'
  _BRAIN_GREEN=$'\033[32m'
  _BRAIN_YELLOW=$'\033[33m'
  _BRAIN_RED=$'\033[31m'
  _BRAIN_DIM=$'\033[2m'
  _BRAIN_RESET=$'\033[0m'

  _brain_interface_hr() {
    echo "─────────────────────────────────────"
  }

  _brain_interface_header() {
    local label="$1" project="$2" git="$3"
    _brain_interface_hr
    echo "${_BRAIN_CYAN} 🧠 BRAIN${_BRAIN_RESET}  ${project:+$project }${git:+$git}"
    _brain_interface_hr
  }

  _brain_interface_key() {
    local key="$1" desc="$2"
    printf "  ${_BRAIN_GREEN}%s${_BRAIN_RESET}  ${_BRAIN_DIM}%s${_BRAIN_RESET}\n" "$key" "$desc"
  }

  _brain_interface_warn() {
    echo "${_BRAIN_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_BRAIN_RESET}"
  }

  _brain_interface_error() {
    echo "${_BRAIN_RED}${1:-!}${_BRAIN_RESET}"
  }
}

# === COMMANDS — BRAIN DISPATCHER ===
# brain() is the ONLY top-level public function. Everything else is lazy.

brain() {
  local cmd="${1:-auto}"
  shift 2>/dev/null || true
  _brain_interface_load

  case "$cmd" in
    auto|"")
      _brain_project_load
      _brain_git_load
      _brain_ai_load
      local dir="$PWD"
      _brain_project_detect "$dir"
      local ptype="${_BRAIN_PROJECT_TYPE[$dir]}"
      if [[ -n "$ptype" ]]; then
        _brain_mode_project
      else
        _brain_mode_global
      fi
      ;;
    ai)
      _brain_ai_load
      _brain_ai_query "$@"
      ;;
    fix)
      _brain_error_load
      _brain_session_error
      ;;
    git)
      _brain_git_load
      _brain_mode_git
      ;;
    project)
      _brain_project_load
      _brain_git_load
      _brain_mode_project
      ;;
    files)
      _brain_mode_files "$@"
      ;;
    history|h)
      _brain_history_load
      _brain_history_search "$@"
      ;;
    session)
      _brain_mode_session "$@"
      ;;
    jump)
      _brain_navigation_load
      _brain_jump "$@"
      ;;
    dirs)
      _brain_navigation_load
      _brain_dirs
      ;;
    doctor)
      _brain_doctor
      ;;
    cache)
      _brain_project_load
      _brain_cache_clear
      ;;
    plugin)
      _brain_plugin_cmd "$@"
      ;;
    help|--help|-h)
      _brain_help
      ;;
    run)
      _brain_project_load
      local dir="$PWD"
      _brain_project_detect "$dir"
      local runcmd="${_BRAIN_PROJECT_RUN[$dir]}"
      if [[ -n "$runcmd" ]]; then
        echo "  Running: $runcmd"
        eval "$runcmd"
      else
        echo "  No run command defined for this project"
      fi
      ;;
    test)
      _brain_project_load
      local dir="$PWD"
      _brain_project_detect "$dir"
      local testcmd="${_BRAIN_PROJECT_TEST[$dir]}"
      if [[ -n "$testcmd" ]]; then
        echo "  Running: $testcmd"
        eval "$testcmd"
      else
        echo "  No test command defined for this project"
      fi
      ;;
    build)
      _brain_project_load
      local dir="$PWD"
      _brain_project_detect "$dir"
      local buildcmd="${_BRAIN_PROJECT_BUILD[$dir]}"
      if [[ -n "$buildcmd" ]]; then
        echo "  Running: $buildcmd"
        eval "$buildcmd"
      else
        echo "  No build command defined for this project"
      fi
      ;;
    *)
      echo "  brain: unknown command '$cmd'"
      echo "  Try: brain help"
      ;;
  esac
}

# ── Doctor ────────────────────────────────────────────────────────────────
_brain_doctor() {
  _brain_detection_load
  _brain_interface_load

  echo "🧠 BRAIN — System Check"
  echo ""
    printf "  %-16s %s\n" "OS" "$_BRAIN_OS $_BRAIN_ARCH"
    printf "  %-16s %s\n" "Kernel" "$_BRAIN_KERNEL"
    printf "  %-16s zsh %s\n" "Shell" "$ZSH_VERSION"
    echo ""

    echo "  ── Tools ──"
    local tools=(opencode claude llm atuin zoxide fzf lazygit yazi nvim btop zellij fd rg bat eza)
    local _st
    for tool in "${tools[@]}"; do
      if _brain_has "$tool"; then
        _st="${_BRAIN_GREEN}✓${_BRAIN_RESET}"
      else
        _st="${_BRAIN_DIM}✗${_BRAIN_RESET}"
      fi
      printf "  %s %s\n" "$_st" "$tool"
    done | column -c 4 2>/dev/null || {
      for tool in "${tools[@]}"; do
        _brain_has "$tool" && echo "  ✓ $tool" || echo "  ✗ $tool"
      done
    }
    echo ""
    echo "  ── AI ──"
    _brain_ai_load
    if _brain_ai_detect; then
      printf "  %-16s %s\n" "Detected" "$_BRAIN_AI_BIN"
      [[ -n "$BRAIN_AI_MODEL" ]] && printf "  %-16s %s\n" "Default model" "$BRAIN_AI_MODEL"
    else
      echo "  No AI CLI found. Install: opencode / claude / llm"
    fi
    echo ""
    echo "  ── Environment ──"
    printf "  %-16s %s\n" "TERM" "$TERM"
    printf "  %-16s %s\n" "EDITOR" "${EDITOR:-vi}"
    echo ""
    echo "  ── Cache ──"
    echo "  Projects cached: ${#_BRAIN_PROJECT_TYPE}"
    echo "  Failures tracked: ${#_BRAIN_FAIL_COUNT}"
    local cache_size=0
    [[ -f "$_BRAIN_CACHE_FILE" ]] && cache_size=$(wc -l < "$_BRAIN_CACHE_FILE" 2>/dev/null)
    echo "  Persistent file: ${cache_size} entries"
  }

  # ── Help ─────────────────────────────────────────────────────────────────
  _brain_help() {
    echo "🧠 BRAIN — Unified CLI Layer"
    echo ""
    printf "  %-10s  %s\n" "brain" "Auto-detect mode, show dashboard"
    printf "  %-10s  %s\n" "brain ai" "AI assistant with context"
    printf "  %-10s  %s\n" "brain fix" "Parse last error, offer actions"
    printf "  %-10s  %s\n" "brain git" "Git dashboard"
    printf "  %-10s  %s\n" "brain project" "Project overview"
    printf "  %-10s  %s\n" "brain files" "File browser"
    printf "  %-10s  %s\n" "brain history" "History search"
    printf "  %-10s  %s\n" "brain session" "Session manager (list/new/attach/kill)"
    printf "  %-10s  %s\n" "brain jump" "Directory jump"
    printf "  %-10s  %s\n" "brain doctor" "Check all tools"
    printf "  %-10s  %s\n" "brain cache" "Clear project cache"
    printf "  %-10s  %s\n" "brain plugin" "Manage plugins (list/load)"
    printf "  %-10s  %s\n" "brain run" "Run project command"
    printf "  %-10s  %s\n" "brain test" "Test project"
    printf "  %-10s  %s\n" "brain build"  "Build project"
    echo ""
    echo "  Export BRAIN_AI_MODEL=hermes for custom AI model"
}

# === MODES ===
# ── MODE 1: GLOBAL (no project) ──────────────────────────────────────────
_brain_mode_global() {
    _brain_interface_header "GLOBAL MODE"

    printf " %s  %s\n" "1" "brain history   — search command history"
    printf " %s  %s\n" "2" "brain files     — browse files"
    printf " %s  %s\n" "3" "brain jump      — jump to directory"
    printf " %s  %s\n" "4" "brain session   — manage sessions (new/attach/kill)"
    printf " %s  %s\n" "5" "brain doctor    — system check"
    printf " %s  %s\n" "6" "brain ai        — ask AI"
    printf " %s  %s\n" "h" "help"
    _brain_interface_hr
  }

  # ── MODE 2: PROJECT ──────────────────────────────────────────────────────
  _brain_mode_project() {
    _brain_project_load
    _brain_git_load
    local dir="$PWD"
    _brain_project_detect "$dir"
    local ptype="${_BRAIN_PROJECT_TYPE[$dir]}"
    local gitstat=$(_brain_git_status_short)

    _brain_interface_header "PROJECT MODE" "$ptype" "$gitstat"

    local runcmd="${_BRAIN_PROJECT_RUN[$dir]}"
    local testcmd="${_BRAIN_PROJECT_TEST[$dir]}"
    local buildcmd="${_BRAIN_PROJECT_BUILD[$dir]}"
    local ai_bin=$(_brain_ai_detect 2>/dev/null && echo "$_BRAIN_AI_BIN" || echo "none")

    [[ -n "$runcmd" ]] && echo "  ${_BRAIN_GREEN}r${_BRAIN_RESET} run      ${_BRAIN_DIM}$runcmd${_BRAIN_RESET}"
    [[ -n "$testcmd" ]] && echo "  ${_BRAIN_GREEN}t${_BRAIN_RESET} test     ${_BRAIN_DIM}$testcmd${_BRAIN_RESET}"
    [[ -n "$buildcmd" ]] && echo "  ${_BRAIN_GREEN}b${_BRAIN_RESET} build    ${_BRAIN_DIM}$buildcmd${_BRAIN_RESET}"
    echo "  ${_BRAIN_GREEN}g${_BRAIN_RESET} git      ${_BRAIN_DIM}lazygit / git${_BRAIN_RESET}"
    echo "  ${_BRAIN_GREEN}f${_BRAIN_RESET} files    ${_BRAIN_DIM}yazi / fzf${_BRAIN_RESET}"
    echo "  ${_BRAIN_GREEN}a${_BRAIN_RESET} ai       ${_BRAIN_DIM}$ai_bin${_BRAIN_RESET}"
    echo "  ${_BRAIN_GREEN}x${_BRAIN_RESET} fix      ${_BRAIN_DIM}parse last error${_BRAIN_RESET}"
    echo "  ${_BRAIN_GREEN}?${_BRAIN_RESET} help     ${_BRAIN_DIM}show all commands${_BRAIN_RESET}"
    _brain_interface_hr
  }

  # ── MODE 3: ERROR ────────────────────────────────────────────────────────
  _brain_mode_error() {
    _brain_error_load
    _brain_project_load
    _brain_git_load

    local dir="$PWD"
    _brain_project_detect "$dir"
    local ptype="${_BRAIN_PROJECT_TYPE[$dir]}"
    local gitstat=$(_brain_git_status_short)
    local exit_code=$_BRAIN_LAST_EXIT

    _brain_interface_header "ERROR MODE" "$ptype" "$gitstat"
    echo "  Last command failed (exit $exit_code)"

    if [[ -n "${_BRAIN_LAST_STDERR:-}" ]]; then
      _brain_parse_error "$_BRAIN_LAST_STDERR" "$exit_code"
      echo ""
      _brain_error_fix "$_BRAIN_LAST_STDERR" "$exit_code"
    else
      echo "  No captured error. Run a command that fails first."
    fi
    _brain_interface_hr
  }

  # ── Show last error (session-scoped) ──────────────────────────────────────
  _brain_session_error() {
    _brain_error_load
    _brain_interface_load
    _brain_project_load
    _brain_git_load

    local dir="$PWD"
    _brain_project_detect "$dir"
    local ptype="${_BRAIN_PROJECT_TYPE[$dir]}"
    local gitstat=$(_brain_git_status_short)
    local exit_code=$_BRAIN_LAST_EXIT

    _brain_interface_header "ERROR" "$ptype" "$gitstat"
    echo "  Last exit code: $exit_code"

    if [[ -n "${_BRAIN_LAST_STDERR:-}" ]]; then
      _brain_parse_error "$_BRAIN_LAST_STDERR" "$exit_code"
      echo ""
      _brain_error_fix "$_BRAIN_LAST_STDERR" "$exit_code"
    else
      echo "  No captured error. Run a command that fails first."
    fi
    _brain_interface_hr
  }

  # ── MODE 4: GIT ──────────────────────────────────────────────────────────
  _brain_mode_git() {
    _brain_detection_load
    _brain_git_load
    _brain_interface_load

    local branch=$(_brain_git_branch)
    local dirty=$(_brain_git_dirty)

    _brain_interface_header "GIT" "" "$branch ±$dirty"
    echo ""
    [[ $dirty -gt 0 ]] && {
      echo "  Uncommitted changes ($dirty files):"
      _brain_git_diff | sed 's/^/  /'
      echo ""
    }
    echo "  Recent commits:"
    _brain_git_log | sed 's/^/  /'
    echo ""
    echo "  [g] launch lazygit   [s] status   [d] diff"
    echo "  [l] log              [p] pull"
    _brain_interface_hr
  }

  # ── MODE: FILES ──────────────────────────────────────────────────────────
  _brain_mode_files() {
    _brain_detection_load
    _brain_interface_load
    _brain_interface_header "FILES"

    if _brain_has yazi; then
      yazi "$@" 2>/dev/null || {
        fd --type f --hidden --exclude .git --exclude node_modules 2>/dev/null \
          | fzf --prompt="files> " --height=20 \
                --preview="bat --color=always {} 2>/dev/null" \
                --bind="enter:execute(${EDITOR:-nvim} {})"
      }
    elif _brain_has fzf; then
      fd --type f --hidden --exclude .git --exclude node_modules 2>/dev/null \
        | fzf --prompt="files> " --height=20 \
              --preview="bat --color=always {} 2>/dev/null" \
              --bind="enter:execute(${EDITOR:-nvim} {})"
    else
      ls -la
    fi
  }

  # ── MODE: SESSION ────────────────────────────────────────────────────────
  _brain_mode_session() {
    _brain_detection_load
    _brain_interface_load
    local action="${1:-list}"

    case "$action" in
      list|"")
        _brain_interface_header "SESSION"
        if _brain_has zellij; then
          local sessions
          sessions=$(zellij list-sessions 2>/dev/null)
          if [[ -z "$sessions" ]]; then
            echo "  No active sessions."
            echo "  Create: brain session new <name>"
          else
            echo "  Active sessions:"
            echo "$sessions" | sed 's/^/  /'
            echo ""
            echo "  [a] attach   [n] new   [k] kill"
          fi
        elif _brain_has tmux; then
          tmux list-sessions 2>/dev/null | sed 's/^/  /' || echo "  No sessions"
        else
          echo "  No session manager found (zellij/tmux)"
        fi
        _brain_interface_hr
        ;;
      new)
        local name="${2:-main}"
        if _brain_has zellij; then
          echo "  Creating session: $name"
          zellij --session "$name" --attach 2>/dev/null
        elif _brain_has tmux; then
          tmux new-session -d -s "$name" 2>/dev/null
          echo "  Created tmux session: $name"
          tmux attach-session -t "$name" 2>/dev/null
        else
          echo "  No session manager found"
        fi
        ;;
      attach)
        local name="$2"
        if _brain_has zellij; then
          if [[ -z "$name" ]]; then
            local sessions
            sessions=$(zellij list-sessions 2>/dev/null)
            if [[ -z "$sessions" ]]; then
              echo "  No sessions to attach."
              return
            fi
            name=$(echo "$sessions" | fzf --prompt="session> " --height=10 2>/dev/null | awk '{print $1}')
            [[ -z "$name" ]] && return
          fi
          zellij attach "$name" 2>/dev/null
        elif _brain_has tmux; then
          if [[ -z "$name" ]]; then
            name=$(tmux list-sessions 2>/dev/null | fzf --prompt="session> " --height=10 2>/dev/null | awk -F: '{print $1}')
            [[ -z "$name" ]] && return
          fi
          tmux attach-session -t "$name" 2>/dev/null
        else
          echo "  No session manager found"
        fi
        ;;
      kill)
        local name="$2"
        if _brain_has zellij; then
          if [[ -z "$name" ]]; then
            local sessions
            sessions=$(zellij list-sessions 2>/dev/null)
            name=$(echo "$sessions" | fzf --prompt="kill> " --height=10 2>/dev/null | awk '{print $1}')
            [[ -z "$name" ]] && return
          fi
          zellij kill-session "$name" 2>/dev/null && echo "  Killed session: $name"
        elif _brain_has tmux; then
          if [[ -z "$name" ]]; then
            name=$(tmux list-sessions 2>/dev/null | fzf --prompt="kill> " --height=10 2>/dev/null | awk -F: '{print $1}')
            [[ -z "$name" ]] && return
          fi
          tmux kill-session -t "$name" 2>/dev/null && echo "  Killed session: $name"
        else
          echo "  No session manager found"
        fi
        ;;
      *)
        echo "  brain session: unknown action '$action'"
        echo "  Usage: brain session [list|new <name>|attach [name]|kill [name]]"
        ;;
    esac
  }

  # ── MODE: AUTO (main dispatcher) ─────────────────────────────────────────
  _brain_mode_auto() {
    _brain_project_load
    _brain_git_load
    _brain_ai_load

    local dir="$PWD"
    _brain_project_detect "$dir"
    local ptype="${_BRAIN_PROJECT_TYPE[$dir]}"

    if [[ -n "$ptype" ]]; then
      _brain_mode_project
    else
      _brain_mode_global
    fi
  }

# === PREEXEC/PRECMD HOOKS ===
_brain_preexec() {
  _BRAIN_LAST_PWD="$PWD"
  # Save stderr fd and redirect to a temp file for brain fix
  exec {_BRAIN_STDERR_SAVE}>&2
  _BRAIN_STDERR_FILE=$(mktemp /tmp/brain-stderr-XXXX)
  exec 2>"$_BRAIN_STDERR_FILE"
}

_brain_precmd() {
  _BRAIN_LAST_EXIT=$?
  # Restore stderr and read captured output
  if [[ -n "${_BRAIN_STDERR_FILE:-}" && -f "$_BRAIN_STDERR_FILE" ]]; then
    exec 2>&${_BRAIN_STDERR_SAVE:-} 2>/dev/null
    _BRAIN_LAST_STDERR=$(cat "$_BRAIN_STDERR_FILE" 2>/dev/null)
    rm -f "$_BRAIN_STDERR_FILE"
    unset _BRAIN_STDERR_FILE _BRAIN_STDERR_SAVE
  fi

  # Track failures for autonomous mode
  if [[ $_BRAIN_LAST_EXIT -ne 0 ]]; then
    _BRAIN_FAIL_COUNT[$PWD]=$(( _BRAIN_FAIL_COUNT[$PWD] + 1 ))
    _BRAIN_FAIL_EXIT[$PWD]=$_BRAIN_LAST_EXIT
  else
    _BRAIN_FAIL_COUNT[$PWD]=0
  fi
}

# ── Register hooks ─────────────────────────────────────────────────────────
autoload -Uz add-zsh-hook
add-zsh-hook preexec _brain_preexec
add-zsh-hook precmd _brain_precmd

# ── Auto-load modules on first brain call ──────────────────────────────────
# Everything above is declared but NOT executed until brain() is called.
# Source time: ~30ms (just declarations + hook registration).

# ── zsh-autocomplete (marlonrichert) — IDE-style type-ahead completion ─────
# Conflicts with zsh-autosuggestions + zsh-syntax-highlighting — remove those
# from .zshrc plugins=() list if enabled.
if [[ -f /usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh
fi

# === END brain.zsh ===
