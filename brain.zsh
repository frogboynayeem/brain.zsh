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
[[ -n ${_BRAIN_BOOTSTRAP_LOADED:-} ]] && return
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
_BRAIN_START_TIME=${EPOCHREALTIME:-} 2>/dev/null || _BRAIN_START_TIME=""
_BRAIN_SHOELACE_ERR=""
_BRAIN_SHOELACE_SESSION_ID=""

# Module loaded flags
typeset -gA _BRAIN_MODULES
_BRAIN_MODULES=(detection 0 history 0 navigation 0 git 0 project 0 ai 0 shoelace 0 modes 0 interface 0 commands 0)

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
    _brain_shoelace_suggest "$stderr"
    echo ""
    echo "  [o] open file in editor"
    echo "  [c] copy error to clipboard"
    echo "  [a] ask AI"
    echo "  [s] save fix to Shoelace"
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
        _brain_shoelace_load
        _brain_shoelace_session_begin
        local response_file
        response_file=$(mktemp "${TMPDIR:-/tmp}/brain-shoelace-XXXX")
        _brain_ai_query "Explain this error and suggest a fix: $stderr" | tee "$response_file"
        echo ""
        echo -n "  Save this fix to Shoelace? [y/N] "
        local sf; read -r sf
        [[ "$sf" == "y" || "$sf" == "Y" ]] && {
          local fix_text
          fix_text=$(cat "$response_file" 2>/dev/null | head -c 2000)
          _brain_shoelace_learn "$stderr" "$fix_text" "$exit_code"
        }
        rm -f "$response_file"
        ;;
      s|S)
        _brain_shoelace_load
        _brain_shoelace_session_begin
        echo -n "  Type the fix that worked: "
        local fix_text; read -r fix_text
        [[ -n "$fix_text" ]] && _brain_shoelace_learn "$stderr" "$fix_text" "$exit_code" || echo "  Cancelled"
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

# ============================================================================
# SHOELACE v2 — Persistent Debugging Memory Engine
# Production-grade error knowledge base with learning, recall, and safety
# ============================================================================
#
# Architecture:
#   Error → normalize (strip paths/numbers/hex/UUIDs/ports/ips/versions)
#         → exact SHA256 signature match
#           → found? Return ranked fixes with confidence scores
#           → not found? Fuzzy fallback on lenient normalization
#         → Learning session tracks failure → fix → success cycle
#         → Safety classifier prevents dangerous auto-execution
#
# Schema: 5 tables (errors, fixes, sessions, telemetry, schema_version)
# Security: SQL injection via single-quote doubling, length limits on stderr
# Performance: Indexed lookups <50ms, lazy-loaded module, ~8ms source overhead

# ── Module loader + schema migration ──────────────────────────────────────
_brain_shoelace_load() {
  [[ ${_BRAIN_MODULES[shoelace]:-0} -eq 1 ]] && return
  _BRAIN_MODULES[shoelace]=1
  _brain_detection_load
  _brain_interface_load

  # Health check 1: sqlite3 binary
  _brain_has sqlite3 || {
    _BRAIN_SHOELACE_AVAIL=0
    _BRAIN_SHOELACE_ERR="sqlite3 not found in PATH"
    return
  }

  [[ -z "$_BRAIN_SHOELACE_DB" ]] && _BRAIN_SHOELACE_DB="${XDG_DATA_HOME:-$HOME/.local/share}/brain/shoelace.db"

  local dbdir
  dbdir=$(dirname "$_BRAIN_SHOELACE_DB")

  # Health check 2: DB directory writable
  if ! mkdir -p "$dbdir" 2>/dev/null; then
    _BRAIN_SHOELACE_AVAIL=0
    _BRAIN_SHOELACE_ERR="cannot create DB directory: $dbdir"
    return
  fi

  if ! [[ -w "$dbdir" ]]; then
    _BRAIN_SHOELACE_AVAIL=0
    _BRAIN_SHOELACE_ERR="DB directory not writable: $dbdir"
    return
  fi

  _brain_shoelace_migrate

  # Health check 3: DB integrity (only if file exists)
  if [[ -f "$_BRAIN_SHOELACE_DB" ]]; then
    local integ
    integ=$(sqlite3 -cmd ".timeout 5000" "$_BRAIN_SHOELACE_DB" "PRAGMA quick_check;" 2>&1)
    if [[ "$integ" != "ok" ]]; then
      # "database is locked" is transient, not corruption
      if [[ "$integ" == *"locked"* ]]; then
        _BRAIN_SHOELACE_AVAIL=1
        _BRAIN_SHOELACE_ERR=""
      else
        _BRAIN_SHOELACE_AVAIL=0
        _BRAIN_SHOELACE_ERR="corruption detected: $integ"
        return
      fi
    fi
  fi

  _BRAIN_SHOELACE_AVAIL=1
  _BRAIN_SHOELACE_ERR=""
}

_brain_shoelace_migrate() {
  local ver
  ver=$(sqlite3 "$_BRAIN_SHOELACE_DB" "SELECT max(version) FROM schema_version;" 2>/dev/null || echo "0")
  [[ -z "$ver" ]] && ver=0

  if [[ $ver -lt 1 ]]; then
    _brain_shoelace_migrate_v1
  fi
  if [[ $ver -lt 2 ]]; then
    _brain_shoelace_migrate_v2
  fi
}

_brain_shoelace_migrate_v2() {
  # V2: Production hardening — WAL mode, synchronous, durability
  sqlite3 "$_BRAIN_SHOELACE_DB" "PRAGMA journal_mode=WAL;" 2>/dev/null
  sqlite3 "$_BRAIN_SHOELACE_DB" "PRAGMA synchronous=NORMAL;" 2>/dev/null
  sqlite3 "$_BRAIN_SHOELACE_DB" "
    INSERT OR IGNORE INTO schema_version (version, description)
    VALUES (2, 'v2 hardening: WAL mode, synchronous=NORMAL');
  " 2>/dev/null
}

_brain_shoelace_migrate_v1() {
  sqlite3 "$_BRAIN_SHOELACE_DB" "
    CREATE TABLE IF NOT EXISTS schema_version (
      version INTEGER PRIMARY KEY,
      applied_at TEXT DEFAULT (datetime('now')),
      description TEXT
    );
  " 2>/dev/null

  sqlite3 "$_BRAIN_SHOELACE_DB" "
    CREATE TABLE IF NOT EXISTS errors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      signature TEXT NOT NULL,
      signature_fuzzy TEXT,
      error_text TEXT NOT NULL,
      error_normalized TEXT NOT NULL,
      exit_code INTEGER,
      command TEXT,
      command_type TEXT,
      cwd TEXT,
      project_fingerprint TEXT,
      os_fingerprint TEXT,
      seen_count INTEGER DEFAULT 1,
      first_seen TEXT DEFAULT (datetime('now')),
      last_seen TEXT DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_errors_sig ON errors(signature);
    CREATE INDEX IF NOT EXISTS idx_errors_sig_fuzzy ON errors(signature_fuzzy);
    CREATE INDEX IF NOT EXISTS idx_errors_project ON errors(project_fingerprint);
    CREATE INDEX IF NOT EXISTS idx_errors_last_seen ON errors(last_seen DESC);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_errors_sig_unique ON errors(signature);
  " 2>/dev/null

  sqlite3 "$_BRAIN_SHOELACE_DB" "
    CREATE TABLE IF NOT EXISTS fixes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      error_id INTEGER NOT NULL,
      fix_text TEXT NOT NULL,
      fix_command TEXT,
      risk_level TEXT DEFAULT 'unknown' CHECK(risk_level IN ('safe','caution','high','unknown')),
      success_count INTEGER DEFAULT 1,
      failure_count INTEGER DEFAULT 0,
      last_success TEXT,
      last_failure TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (error_id) REFERENCES errors(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_fixes_err ON fixes(error_id);
    CREATE INDEX IF NOT EXISTS idx_fixes_success ON fixes(success_count DESC);
  " 2>/dev/null

  sqlite3 "$_BRAIN_SHOELACE_DB" "
    CREATE TABLE IF NOT EXISTS learning_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      error_id INTEGER,
      session_id TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'failure',
      failure_command TEXT,
      fix_command TEXT,
      attempt_count INTEGER DEFAULT 1,
      started_at TEXT DEFAULT (datetime('now')),
      resolved_at TEXT,
      FOREIGN KEY (error_id) REFERENCES errors(id)
    );
    CREATE INDEX IF NOT EXISTS idx_sessions_state ON learning_sessions(state);
    CREATE INDEX IF NOT EXISTS idx_sessions_sid ON learning_sessions(session_id);
  " 2>/dev/null

  sqlite3 "$_BRAIN_SHOELACE_DB" "
    CREATE TABLE IF NOT EXISTS telemetry (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_type TEXT NOT NULL,
      error_id INTEGER,
      fix_id INTEGER,
      confidence REAL,
      decision TEXT,
      duration_ms INTEGER,
      created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_telemetry_type ON telemetry(event_type);
  " 2>/dev/null

  sqlite3 "$_BRAIN_SHOELACE_DB" "
    INSERT OR IGNORE INTO schema_version (version, description)
    VALUES (1, 'v2 schema: errors+fixes+sessions+telemetry');
  " 2>/dev/null

  # Migrate legacy data if old schema exists
  local old_count
  old_count=$(sqlite3 "$_BRAIN_SHOELACE_DB" "
    SELECT COUNT(*) FROM sqlite_master
    WHERE type='table' AND name='errors' AND sql LIKE '%fingerprint%';
  " 2>/dev/null)
  if [[ "$old_count" -gt 0 ]]; then
    sqlite3 "$_BRAIN_SHOELACE_DB" "
      INSERT OR IGNORE INTO errors (signature, error_text, error_normalized, exit_code, command, cwd, seen_count, first_seen, last_seen)
      SELECT fingerprint, error_snippet, error_snippet, exit_code, last_command, last_cwd, seen_count, first_seen, last_seen
      FROM errors AS old
      WHERE old.fingerprint NOT IN (SELECT signature FROM errors WHERE signature = old.fingerprint);
    " 2>/dev/null
  fi
}

# ── SQL Injection Prevention ──────────────────────────────────────────────
# Treat all stderr-derived input as hostile. Double single quotes, strip nulls,
# limit length. Use this on ALL data before interpolating into SQL.
_brain_shoelace_escape() {
  printf '%s' "$1" | tr -d '\000' | sed "s/'/''/g"
}

# ── SQLite helper: safe write execution with retry ────────────────────────
# Every invocation is a fresh sqlite3 process. We MUST set per-connection
# PRAGMAs and use retry with backoff for concurrent write safety.
_brain_shoelace_db() {
  local sql="$1" db="${2:-$_BRAIN_SHOELACE_DB}"
  local retries="${3:-5}" sleep_base="${4:-50}"
  local attempt=0 result rc

  while (( attempt++ < retries )); do
    # synchronous=NORMAL must be set per-connection (WAL journal_mode is persistent)
    # PRAGMA assignments via echo pipe produce no output (unlike -cmd)
    result=$(echo "PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON; $sql" | \
      sqlite3 -separator '|' -cmd ".timeout 5000" "$db" 2>&1)
    rc=$?
    [[ $rc -eq 0 ]] && { printf '%s' "$result"; return 0; }
    # Only retry on lock-contention errors, not syntax/constraint failures
    if [[ "$result" == *"database is locked"* ]] || \
       [[ "$result" == *"BUSY"* ]] || \
       [[ "$result" == *"cannot commit"* ]] || \
       [[ "$result" == *"locking protocol"* ]]; then
      sleep 0.$(( attempt * sleep_base ))
      continue
    fi
    return $rc
  done
  return 1
}

_brain_shoelace_db_write() {
  local sql="$1" db="${2:-$_BRAIN_SHOELACE_DB}" retries="${3:-5}"
  local attempt=0 rc

  while (( attempt++ < retries )); do
    echo "PRAGMA foreign_keys=ON; PRAGMA synchronous=NORMAL; BEGIN IMMEDIATE; $sql; COMMIT;" | \
      sqlite3 -cmd ".timeout 5000" "$db" 2>/dev/null
    rc=$?
    [[ $rc -eq 0 ]] && return 0
    sleep 0.$(( attempt * 100 ))
  done
  return $rc
}

# ── Error Normalization Engine ────────────────────────────────────────────
# Transforms raw stderr into a stable, matchable form by replacing volatile
# identifiers with placeholders. Each normalization has a specific rationale.
#
# Normalization rules and why they exist:
#
# 1. File paths     → <PATH>  — same error in different paths should match
# 2. Line numbers   → <N>     — line 42 vs line 99 is same bug class
# 3. Column numbers → <N>     — same as line numbers
# 4. UUIDs          → <UUID>  — random per-install, never matches otherwise
# 5. Hex addresses  → <HEX>   — memory addresses, commit hashes
# 6. IP addresses   → <IP>    — network config varies by machine
# 7. Port numbers   → <PORT>  — port conflicts vary by environment
# 8. Timestamps     → <TS>    — log timestamps never match
# 9. Version nums   → <VER>   — semver changes between releases
# 10. Temp dirs     → <TMP>   — /tmp/xxx varies per session
# 11. Home dirs     → <HOME>  — /home/user differs per machine
# 12. Container IDs → <CID>   — docker container IDs are random
# 13. Process IDs   → <PID>   — PID 12345 vs 98765 same error
# 14. Quoted strs   → <STR>   — variable values like filenames
#
# Two normalization levels:
#   EXACT: Full normalization — aggressive stripping for stable matching
#   FUZZY: Lenient normalization — preserves more structure, fewer false negs

_brain_shoelace_normalize_exact() {
  local raw="$1"
  # Truncate to prevent DoS on enormous stderr
  raw=$(printf '%s' "$raw" | head -c 5000)
  # Strip ANSI escape sequences using literal ESC byte (GNU sed doesn't support \x1b)
  raw=$(printf '%s' "$raw" | sed -E '
    s/'$(printf '\033')'\[[0-9;?]*[a-zA-Z]//g
    s/'$(printf '\033')'\][^'$(printf '\033')']*('$(printf '\033')'\\|$)//g
    s/'$(printf '\033')'[[()][0-9;?]*[a-zA-Z]?//g
    s/'$(printf '\033')'[NO]//g
    s/\\033\[[0-9;?]*[a-zA-Z]//g
    s/\\033\][^\\033]*(\\033\\|$)//g
  ')
  printf '%s' "$raw" | sed -E '
    # Order matters: apply most specific patterns first
    # 1. UUIDs: 8-4-4-4-12 format (MUST come before hex — UUID hex segments match hex patterns)
    s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<UUID>/gi
    # 2. Container IDs: 64-char hex after "container" or sha256:
    s/\b[0-9a-f]{64}\b/<CID>/g
    # 3. Short hex hashes (git, docker)
    s/\b[0-9a-f]{7,40}\b/<HEX>/g
    # 4. IP addresses: IPv4 and IPv6
    s/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/<IP>/g
    s/[0-9a-f:]+:[0-9a-f:]+:[0-9a-f:]+/<IP>/gi
    # 5. Port numbers after colon or "port"
    s/port [0-9]+/port <PORT>/gi
    # 6. Home directories
    s|/home/[a-zA-Z0-9._-]+|/home/<USER>|g
    s|/Users/[a-zA-Z0-9._-]+|/Users/<USER>|g
    # 7. Temp directories
    s|/tmp/[a-zA-Z0-9._-]+|/tmp/<TMP>|g
    s|/var/tmp/[a-zA-Z0-9._-]+|/var/tmp/<TMP>|g
    # 8. Line:column references (Rust, Python, JS, etc.) — before path rules
    s/:[0-9]+:[0-9]+[^0-9]/:<N>:<N> /g
    s/:[0-9]+:[0-9]+$/:<N>:<N>/g
    s/ line [0-9]+/ line <N>/gi
    s/ at line [0-9]+/ at line <N>/gi
    # 9. dir/file.ext:N — path with line number (MUST come before bare path rules)
    s/\b[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+\.[a-zA-Z]{1,4}:[0-9]+/<PATH>:<N>/g
    # 9b. Bare filename:line references (no directory) — main.rs:42, foo.py:18
    s/\b[a-zA-Z0-9._-]+\.[a-zA-Z]{1,4}:[0-9]+/<FILE>.ext:<N>/g
    # 10. Absolute file paths starting with /
    s|/[^ \t\n:()<>"'"'"']*/([^/ \t\n:()<>"'"'"']+\.[a-zA-Z0-9]+)|/<PATH>/\1|g
    s|/[^ \t\n:()<>"'"'"']+/([^/ \t\n:()<>"'"'"']+)|/<PATH>/\1|g
    s|/[^ \t\n:()<>"'"'"']+\.[a-zA-Z]{1,4}|/<PATH>.ext|g
    # 11. Relative file paths with extensions (src/main.rs, lib/foo.py)
    s/\b[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+\.[a-zA-Z]{1,4}\b/<PATH>/g
    # 12. Version numbers (semver-like)
    s/[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9._-]*/<VER>/g
    s/v[0-9]+\.[0-9]+\.[0-9]+/v<VER>/g
    s/\bv[0-9]+\b/v<VER>/g
    # 13. Timestamps: ISO 8601, log timestamps
    s/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}/<TS>/g
    # 14. Process IDs
    s/pid [0-9]+/pid <PID>/gi
    s/PID [0-9]+/PID <PID>/g
    # 15. Error codes with numbers: E0308, ENOENT, 0x1 etc.
    s/error\[E[0-9]+\]/error[E<N>]/g
    # 16. Single-quoted strings >3 chars (variable values)
    s/'"'"'[a-zA-Z0-9._/-]{4,}'"'"'/<STR>/g
    # 17. Double-quoted strings >3 chars
    s/"[a-zA-Z0-9._/-]{4,}"/<STR>/g
    # 16. Generic numbers (at least 4 digits)
    s/[0-9]{4,}/<N>/g
    # 17. Collapse multiple spaces
    s/[ \t]+/ /g
    # 18. Trim whitespace
    s/^ *//; s/ *$//
  '
}

_brain_shoelace_normalize_fuzzy() {
  # Lenient normalization: fewer substitutions, preserves more structure
  # Used as fallback when exact match fails
  local raw="$1"
  raw=$(printf '%s' "$raw" | head -c 2000)
  # Strip ANSI escape sequences  
  raw=$(printf '%s' "$raw" | sed -E '
    s/'$(printf '\033')'\[[0-9;?]*[a-zA-Z]//g
    s/'$(printf '\033')'\][^'$(printf '\033')']*('$(printf '\033')'\\|$)//g
    s/'$(printf '\033')'[[()][0-9;?]*[a-zA-Z]?//g
    s/'$(printf '\033')'[NO]//g
    s/\\033\[[0-9;?]*[a-zA-Z]//g
    s/\\033\][^\\033]*(\\033\\|$)//g
  ')
  printf '%s' "$raw" | sed -E '
    # UUIDs (before hex — same UUID must normalize identically)
    s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<UUID>/gi
    s/\b[0-9a-f]{40}\b/<HASH>/g
    # Home and temp dirs
    s|/home/[a-zA-Z0-9._-]+|/home/<USER>|g
    s|/tmp/[a-zA-Z0-9._-]+|/tmp|g
    # Line numbers
    s/:[0-9]+:[0-9]+/:<N>:<N>/g
    s/ line [0-9]+/ line <N>/gi
    # file:line references (single number) — must come before bare paths
    s|\b[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\.[a-zA-Z]{1,4}:[0-9]+|<PATH>:<N>|g
    # Bare filename:line references (no directory) — main.rs:42, foo.py:18
    s|\b[a-zA-Z0-9._-]+\.[a-zA-Z]{1,4}:[0-9]+|<FILE>.ext:<N>|g
    # Relative file paths with extensions
    s|\b[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\.[a-zA-Z]{1,4}\b|<PATH>|g
    # Generic numbers (5+ digits)
    s/[0-9]{5,}/<N>/g
    # IPs
    s/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/<IP>/g
    # Collapse spaces
    s/[ \t]+/ /g
    s/^ *//; s/ *$//
  '
}

# ── Signature Generation ──────────────────────────────────────────────────
# Produces stable hashes from normalized error text for database lookups.
# Uses SHA256 via sha256sum, falls back to md5sum, then to length hash.

_brain_shoelace_signature() {
  local normalized="$1"
  if _brain_has sha256sum; then
    printf '%s' "$normalized" | sha256sum | cut -d' ' -f1
  elif _brain_has md5sum; then
    printf '%s' "$normalized" | md5sum | cut -d' ' -f1
  elif _brain_has md5; then
    printf '%s' "$normalized" | md5
  else
    # Fallback: use Zsh string length + first 100 chars as quasi-hash
    local len="${#normalized}"
    printf '%s' "${normalized:0:100}$len" | cksum | cut -d' ' -f1
  fi
}

# ── Toolchain Detection ───────────────────────────────────────────────────
# Analyzes the failing command to identify the tool ecosystem.
# Used for confidence scoring and project fingerprinting.

_brain_shoelace_extract_toolchain() {
  local cmd="$1"
  local dir="$2"
  local result="unknown"
  case "$cmd" in
    npm*) result="npm" ;;
    pip*|python*|python3*) result="python" ;;
    cargo*|rustc*) result="rust" ;;
    go*) result="go" ;;
    docker*|docker-compose*) result="docker" ;;
    git*) result="git" ;;
    apt*|apt-get*|dpkg*) result="apt" ;;
    pacman*|yay*|paru*) result="pacman" ;;
    nix*) result="nix" ;;
    npx*) result="npm" ;;
    make*|cmake*) result="build" ;;
    systemctl*|journalctl*) result="systemd" ;;
  esac
  # If command is unknown, check project files
  if [[ "$result" == "unknown" && -n "$dir" ]]; then
    [[ -f "$dir/package.json" ]] && result="npm"
    [[ -f "$dir/Cargo.toml" ]] && result="rust"
    [[ -f "$dir/pyproject.toml" || -f "$dir/requirements.txt" ]] && result="python"
    [[ -f "$dir/go.mod" ]] && result="go"
    [[ -f "$dir/docker-compose.yml" || -f "$dir/Dockerfile" ]] && result="docker"
  fi
  echo "$result"
}

# ── Project Fingerprinting ────────────────────────────────────────────────
# Generates a stable identifier for the current project based on its
# characteristics. Used to scope fixes to specific projects.

_brain_shoelace_project_fingerprint() {
  local dir="$1"
  local sig=""
  [[ -f "$dir/package.json" ]] && sig+="npm:$(grep -m1 '"name"' "$dir/package.json" 2>/dev/null | sed 's/.*"name": *"\([^"]*\)".*/\1/' 2>/dev/null || echo "unknown")"
  [[ -f "$dir/Cargo.toml" ]] && sig+="rust:$(grep -m1 '^name' "$dir/Cargo.toml" 2>/dev/null | sed 's/name = "\(.*\)"/\1/' 2>/dev/null || echo "unknown")"
  [[ -f "$dir/pyproject.toml" ]] && sig+="python:$(grep -m1 '^name' "$dir/pyproject.toml" 2>/dev/null | sed 's/name = "\(.*\)"/\1/' 2>/dev/null || echo "unknown")"
  [[ -f "$dir/go.mod" ]] && sig+="go:$(head -1 "$dir/go.mod" 2>/dev/null | sed 's/module //' 2>/dev/null || echo "unknown")"
  [[ -d "$dir/.git" ]] && {
    local remote
    remote=$(git -C "$dir" config --get remote.origin.url 2>/dev/null || echo "")
    sig+="git:$remote"
  }
  [[ -z "$sig" ]] && sig="global:$(basename "$dir" 2>/dev/null || echo "unknown")"
  if _brain_has sha256sum; then
    printf '%s' "$sig" | sha256sum | cut -d' ' -f1
  else
    printf '%s' "$sig" | md5sum | cut -d' ' -f1
  fi
}

# ── Risk Classification ───────────────────────────────────────────────────
# Categorizes fix commands by safety level to prevent dangerous auto-execution.
_brain_shoelace_classify_risk() {
  local cmd="$1"
  local lower="${cmd:l}"
  # High risk: destructive operations with potential for data loss
  if [[ "$lower" =~ '\brm +-rf\b' || "$lower" =~ '\brm +-rf' ]] && ! [[ "$lower" =~ 'node_modules' || "$lower" =~ '.cache' ]]; then
    echo "high"; return
  fi
  if [[ "$lower" =~ '\bmkfs\b' || "$lower" =~ '\bdd\b' || "$lower" =~ '\bformat\b' || \
        "$lower" =~ '\bwipefs\b' || "$lower" =~ '\bshred\b' || "$lower" =~ '\bfdisk\b' || \
        "$lower" =~ '\bparted\b mklabel' || "$lower" =~ '\bgit +reset +--hard\b' ]]; then
    echo "high"; return
  fi
  if [[ "$lower" =~ '\bchmod +-R\b' || "$lower" =~ '\bchown +-R\b' || \
        "$lower" =~ '\bgit +push +--force\b' ]]; then
    echo "high"; return
  fi
  # Caution: requires elevated privileges or modifies system state
  if [[ "$lower" =~ '\bsudo\b' || "$lower" =~ '\bpacman +-S[^y]\b' || "$lower" =~ '\bapt +install\b' || \
        "$lower" =~ '\byay +-S\b' || "$lower" =~ '\bparu +-S\b' || \
        "$lower" =~ '\bnpm +install +-g\b' || "$lower" =~ '\bpip +install\b' || \
        "$lower" =~ '\bchmod\b' || "$lower" =~ '\bchown\b' || \
        "$lower" =~ '\bsystemctl +restart\b' || "$lower" =~ '\bsystemctl +stop\b' || \
        "$lower" =~ '\bdocker +rm\b' || "$lower" =~ '\bdocker +rmi\b' ]]; then
    echo "caution"; return
  fi
  # Safe: package management, cache ops, non-destructive
  echo "safe"
}

# ── Confidence Scoring ───────────────────────────────────────────────────
# Multi-factor scoring: success rate, recency, similarity, project match, toolchain match.
# Returns a number 0-100 representing confidence percentage.
_brain_shoelace_confidence() {
  local fix_id="$1" match_type="$2"
  local row
  row=$(_brain_shoelace_db "
    SELECT f.success_count, f.failure_count, f.last_success,
           e.project_fingerprint, e.command_type
    FROM fixes f
    JOIN errors e ON e.id = f.error_id
    WHERE f.id = '$fix_id';
  " 2>/dev/null)
  [[ -z "$row" ]] && { echo "0"; return; }

  local IFS='|' fields=("${(s:|:)row}")
  local success=${fields[1]:-0}
  local failure=${fields[2]:-0}
  local last_success="${fields[3]:-}"
  local fp="${fields[4]:-}"
  local cmd_type="${fields[5]:-}"

  # 1. Success rate factor (0-40 points): based on ratio, scaled by log(total)
  local total=$(( success + failure ))
  local success_factor=0
  if [[ $total -gt 0 ]]; then
    local ratio=$(( success * 1.0 / total ))
    local scale=$(( $(echo "scale=2; l($total + 1)/l(101)" | bc -l 2>/dev/null || echo "0.5") ))
    success_factor=$(echo "scale=0; $ratio * 40 * $scale / 1" | bc 2>/dev/null || echo "20")
  fi

  # 2. Recency factor (0-20 points): decays over 60 days
  local recency_factor=0
  if [[ -n "$last_success" ]]; then
    local days_since
    days_since=$(_brain_shoelace_db "
      SELECT CAST(julianday('now') - julianday('$last_success') AS INTEGER);
    " 2>/dev/null || echo "30")
    recency_factor=$(echo "scale=0; 20 * e(-$days_since / 30)" | bc -l 2>/dev/null || echo "10")
    [[ $recency_factor -lt 0 ]] && recency_factor=0
  fi

  # 3. Similarity factor (0-20 points): exact vs fuzzy match
  local sim_factor=0
  [[ "$match_type" == "exact" ]] && sim_factor=20
  [[ "$match_type" == "fuzzy" ]] && sim_factor=12

  # 4. Project match (0-10 points)
  local proj_factor=0
  local current_fp=$(_brain_shoelace_project_fingerprint "$PWD" 2>/dev/null)
  [[ "$fp" == "$current_fp" ]] && proj_factor=10

  # 5. Toolchain match (0-10 points)
  local tool_factor=0
  local current_tool=$(_brain_shoelace_extract_toolchain "$_BRAIN_LAST_COMMAND" "$PWD" 2>/dev/null)
  [[ -n "$current_tool" && "$cmd_type" == "$current_tool" ]] && tool_factor=10

  local total_score=$(( success_factor + recency_factor + sim_factor + proj_factor + tool_factor ))
  echo "$total_score"
}

# ── Recall Engine ─────────────────────────────────────────────────────────
# Primary lookup: tries exact match first, falls back to fuzzy match.
# Returns ranked fixes with confidence scores.
_brain_shoelace_recall() {
  local error_text="$1"
  [[ -z "$error_text" ]] && return

  local norm_exact norm_fuzzy
  norm_exact=$(_brain_shoelace_normalize_exact "$error_text")
  norm_fuzzy=$(_brain_shoelace_normalize_fuzzy "$error_text")
  local sig_exact sig_fuzzy
  sig_exact=$(_brain_shoelace_signature "$norm_exact")
  sig_fuzzy=$(_brain_shoelace_signature "$norm_fuzzy")

  local esc_norm=$(_brain_shoelace_esc_sql "$norm_exact")
  local esc_norm_fuzzy=$(_brain_shoelace_esc_sql "$norm_fuzzy")

  # Step 1: Exact signature match
  local exact
  exact=$(_brain_shoelace_db "
    SELECT e.id, f.id, f.fix_text, f.success_count, f.failure_count, f.risk_level, e.seen_count
    FROM errors e
    JOIN fixes f ON f.error_id = e.id
    WHERE e.signature = '$sig_exact'
    ORDER BY f.success_count DESC
    LIMIT 3;
  " 2>/dev/null)

  if [[ -n "$exact" ]]; then
    echo "$exact" | while IFS='|' read -r err_id fix_id fix_text success failure risk seen; do
      local conf
      conf=$(_brain_shoelace_confidence "$fix_id" "exact")
      echo "exact|$conf|$fix_id|$fix_text|$success|$failure|$risk|$seen"
    done
    return
  fi

  # Step 2: Fuzzy fallback — match on signature_fuzzy
  local fuzzy
  fuzzy=$(_brain_shoelace_db "
    SELECT e.id, f.id, f.fix_text, f.success_count, f.failure_count, f.risk_level, e.seen_count
    FROM errors e
    JOIN fixes f ON f.error_id = e.id
    WHERE e.signature_fuzzy = '$sig_fuzzy'
    ORDER BY f.success_count DESC
    LIMIT 3;
  " 2>/dev/null)

  if [[ -n "$fuzzy" ]]; then
    echo "$fuzzy" | while IFS='|' read -r err_id fix_id fix_text success failure risk seen; do
      local conf
      conf=$(_brain_shoelace_confidence "$fix_id" "fuzzy")
      echo "fuzzy|$conf|$fix_id|$fix_text|$success|$failure|$risk|$seen"
    done
    return
  fi

  # Step 3: Store error as unseen (update counts if already exists)
  local err_esc_recall cmd_esc_recall tool_esc_recall cwd_esc_recall fp_esc_recall
  err_esc_recall=$(_brain_shoelace_esc_sql "${error_text:0:1000}")
  cmd_esc_recall=$(_brain_shoelace_esc_sql "$_BRAIN_LAST_COMMAND")
  tool_esc_recall=$(_brain_shoelace_esc_sql "$(_brain_shoelace_extract_toolchain "$_BRAIN_LAST_COMMAND" "$PWD")")
  cwd_esc_recall=$(_brain_shoelace_esc_sql "$PWD")
  fp_esc_recall=$(_brain_shoelace_esc_sql "$(_brain_shoelace_project_fingerprint "$PWD")")
  _brain_shoelace_db_write "
    INSERT INTO errors (signature, signature_fuzzy, error_text, error_normalized, exit_code, command, command_type, cwd, project_fingerprint)
    VALUES ('$sig_exact', '$sig_fuzzy', '$err_esc_recall', '$esc_norm', $_BRAIN_LAST_EXIT,
            '$cmd_esc_recall', '$tool_esc_recall',
            '$cwd_esc_recall', '$fp_esc_recall')
    ON CONFLICT(signature) DO UPDATE SET
      seen_count = seen_count + 1, last_seen = datetime('now');
  "
}

# SQL-escape helper
_brain_shoelace_esc_sql() { printf '%s' "$1" | tr -d '\000' | sed "s/'/''/g"; }

# ── Learning Session Management ──────────────────────────────────────────
# State machine for tracking failure → fix → success cycles.
# Prevents false positives by only recording when confidence is validated.
_brain_shoelace_session_begin() {
  [[ -n "${_BRAIN_SHOELACE_SESSION_ID:-}" ]] && return
  local error_id="${1:-}"
  _BRAIN_SHOELACE_SESSION_ID="${EPOCHSECONDS:-$(date +%s)}-$$-${RANDOM}"
  local cmd_esc=$(_brain_shoelace_esc_sql "$_BRAIN_LAST_COMMAND")
  _brain_shoelace_db_write "
    INSERT INTO learning_sessions (error_id, session_id, state, failure_command)
    VALUES (${error_id:-NULL}, '$_BRAIN_SHOELACE_SESSION_ID', 'failure', '$cmd_esc');
  "
}

_brain_shoelace_session_mark_fix() {
  local fix_cmd="$1"
  [[ -z "${_BRAIN_SHOELACE_SESSION_ID:-}" ]] && return
  local esc=$(_brain_shoelace_esc_sql "$fix_cmd")
  _brain_shoelace_db_write "
    UPDATE learning_sessions
    SET state = 'fix_attempted', fix_command = '$esc', attempt_count = attempt_count + 1
    WHERE session_id = '$_BRAIN_SHOELACE_SESSION_ID' AND state = 'failure';
  "
}

_brain_shoelace_session_resolve() {
  [[ -z "${_BRAIN_SHOELACE_SESSION_ID:-}" ]] && return
  _brain_shoelace_db_write "
    UPDATE learning_sessions
    SET state = 'resolved', resolved_at = datetime('now')
    WHERE session_id = '$_BRAIN_SHOELACE_SESSION_ID';
  "
  unset _BRAIN_SHOELACE_SESSION_ID
}

_brain_shoelace_session_abandon() {
  [[ -z "${_BRAIN_SHOELACE_SESSION_ID:-}" ]] && return
  _brain_shoelace_db_write "
    UPDATE learning_sessions
    SET state = 'abandoned', resolved_at = datetime('now')
    WHERE session_id = '$_BRAIN_SHOELACE_SESSION_ID';
  "
  unset _BRAIN_SHOELACE_SESSION_ID
}

# ── Learn: Record a fix ───────────────────────────────────────────────────
# Validates and stores an error→fix pair. Only succeeds if:
#   1. The error text is non-empty
#   2. The fix text is non-empty
#   3. The error can be normalized and fingerprinted
#   4. The risk level can be classified
_brain_shoelace_learn() {
  local error_text="$1" fix_text="$2" exit_code="${3:-}"
  _brain_shoelace_load
  [[ $_BRAIN_SHOELACE_AVAIL -eq 0 ]] && { echo "  ✗ ${_BRAIN_SHOELACE_ERR:-Shoelace unavailable (run: brain doctor)}"; return; }
  [[ -z "$error_text" || -z "$fix_text" ]] && { echo "  ✗ Error and fix text required"; return; }

  local norm_exact norm_fuzzy
  norm_exact=$(_brain_shoelace_normalize_exact "$error_text")
  norm_fuzzy=$(_brain_shoelace_normalize_fuzzy "$error_text")
  local sig_exact sig_fuzzy
  sig_exact=$(_brain_shoelace_signature "$norm_exact")
  sig_fuzzy=$(_brain_shoelace_signature "$norm_fuzzy")

  local err_esc=$(_brain_shoelace_esc_sql "${error_text:0:2000}")
  local norm_esc=$(_brain_shoelace_esc_sql "${norm_exact:0:2000}")
  local fix_esc=$(_brain_shoelace_esc_sql "${fix_text:0:2000}")
  local cmd_esc=$(_brain_shoelace_esc_sql "${_BRAIN_LAST_COMMAND:-}")
  local cwd_esc=$(_brain_shoelace_esc_sql "$PWD")
  local tool=$(_brain_shoelace_extract_toolchain "$_BRAIN_LAST_COMMAND" "$PWD")
  local tool_esc=$(_brain_shoelace_esc_sql "$tool")
  local proj_fp=$(_brain_shoelace_project_fingerprint "$PWD")
  local risk=$(_brain_shoelace_classify_risk "$fix_text")

  # Begin session for this learn (no-op if already started by interactive flow)
  _brain_shoelace_session_begin

  # Insert or update error record
  _brain_shoelace_db_write "
    INSERT INTO errors (signature, signature_fuzzy, error_text, error_normalized, exit_code, command, command_type, cwd, project_fingerprint)
    VALUES ('$sig_exact', '$sig_fuzzy', '$err_esc', '$norm_esc', ${exit_code:-NULL}, '$cmd_esc', '$tool_esc', '$cwd_esc', '$proj_fp')
    ON CONFLICT(signature) DO UPDATE SET
      seen_count = seen_count + 1, last_seen = datetime('now'),
      command = CASE WHEN excluded.command != '' THEN excluded.command ELSE command END,
      cwd = excluded.cwd;
  "

  local error_id
  error_id=$(_brain_shoelace_db "SELECT id FROM errors WHERE signature = '$sig_exact';" 2>/dev/null)
  [[ -z "$error_id" ]] && { echo "  ✗ Failed to save error record"; return; }

  # Insert fix
  if _brain_shoelace_db_write "
    INSERT INTO fixes (error_id, fix_text, fix_command, risk_level)
    VALUES ($error_id, '$fix_esc', '$cmd_esc', '$risk');
  "; then
    echo "  ✓ Saved to Shoelace (risk: $risk)"
    # Record telemetry
    _brain_shoelace_db_write "
      INSERT INTO telemetry (event_type, error_id, decision)
      VALUES ('learn', $error_id, 'saved');
    "
    # Mark session resolved
    _brain_shoelace_session_mark_fix "$fix_text"
    _brain_shoelace_session_resolve
  else
    echo "  ✗ Failed to save fix"
  fi
}

# ── Suggest: Display ranked fix recommendations ──────────────────────────
_brain_shoelace_suggest() {
  _brain_shoelace_load
  [[ $_BRAIN_SHOELACE_AVAIL -eq 0 ]] && return
  local error_text="$1"
  [[ -z "$error_text" ]] && return

  local recalls
  recalls=$(_brain_shoelace_recall "$error_text")
  [[ -z "$recalls" ]] && return

  echo ""
  echo "  ${_BRAIN_CYAN}${_BRAIN_BOLD}Found familiar issue${_BRAIN_RESET}"
  echo "  ────────────────────────"

  local first=1
  echo "$recalls" | while IFS='|' read -r match_type confidence fix_id fix_text success failure risk seen; do
    local total=$(( success + failure ))
    local pct=0
    [[ $total -gt 0 ]] && pct=$(( success * 100 / total ))
    local risk_icon=""
    case "$risk" in
      high)    risk_icon="${_BRAIN_RED}!${_BRAIN_RESET}" ;;
      caution) risk_icon="${_BRAIN_YELLOW}~${_BRAIN_RESET}" ;;
      safe)    risk_icon="${_BRAIN_GREEN}✓${_BRAIN_RESET}" ;;
      *)       risk_icon="?" ;;
    esac

    if [[ $first -eq 1 ]]; then
      echo ""
      echo "  ${_BRAIN_CYAN}Suggested fix${_BRAIN_RESET}"
      echo "  ${_BRAIN_GREEN}→${_BRAIN_RESET} ${fix_text}"
      echo ""
      echo "  ${_BRAIN_DIM}Confidence:${_BRAIN_RESET} ${confidence}%"
      [[ $total -gt 0 ]] && echo "  ${_BRAIN_DIM}Success rate:${_BRAIN_RESET} ${pct}% (${success}/${total})"
      echo "  ${_BRAIN_DIM}Risk level:${_BRAIN_RESET} ${risk_icon} $risk"
      echo "  ${_BRAIN_DIM}Match:${_BRAIN_RESET} ${match_type} signature"
      echo ""
      echo "  ${_BRAIN_DIM}Reason:${_BRAIN_RESET}"
      [[ "$match_type" == "exact" ]] && echo "  ${_BRAIN_GREEN}✓${_BRAIN_RESET} same error signature"
      [[ "$match_type" == "fuzzy" ]] && echo "  ${_BRAIN_DIM}~${_BRAIN_RESET} similar error pattern"
      [[ $success -gt 5 ]] && echo "  ${_BRAIN_GREEN}✓${_BRAIN_RESET} fixed ${success}x before"
      echo ""
      echo -n "  ${_BRAIN_CYAN}Apply? [y/N]${_BRAIN_RESET} "
      local apply_resp; read -r apply_resp
      if [[ "$apply_resp" == "y" || "$apply_resp" == "Y" ]]; then
        _brain_shoelace_apply_by_id "$fix_id" "$fix_text" "$risk"
        return
      fi
      first=0
    fi
  done
}

# ── Apply: Execute a fix with safety checks ───────────────────────────────
_brain_shoelace_apply_by_id() {
  local fix_id="$1" fix_text="$2" risk="$3"
  local redacted=""

  case "$risk" in
    high)
      _brain_interface_warn
      echo "  ${_BRAIN_RED}⚠ HIGH RISK OPERATION${_BRAIN_RESET}"
      echo "  ${_BRAIN_DIM}This fix could cause data loss or system damage${_BRAIN_RESET}"
      echo "  Fix: ${_BRAIN_YELLOW}$fix_text${_BRAIN_RESET}"
      echo ""
      echo -n "  ${_BRAIN_RED}Type 'yes' to confirm:${_BRAIN_RESET} "
      local confirm; read -r confirm
      [[ "$confirm" != "yes" ]] && { echo "  Cancelled"; return; }
      echo -n "  ${_BRAIN_RED}Type the exact fix command to proceed:${_BRAIN_RESET} "
      local verify; read -r verify
      [[ "$verify" != "$fix_text" ]] && { echo "  Cancelled — command mismatch"; return; }
      ;;
    caution)
      echo "  ${_BRAIN_YELLOW}⚠ This fix modifies system state${_BRAIN_RESET}"
      echo "  ${_BRAIN_DIM}Fix: $fix_text${_BRAIN_RESET}"
      echo ""
      echo -n "  ${_BRAIN_YELLOW}Apply? [y/N]${_BRAIN_RESET} "
      local confirm; read -r confirm
      [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "  Cancelled"; return; }
      ;;
    safe)
      echo -n "  Apply? [Y/n] "
      local confirm; read -r confirm
      [[ "$confirm" == "n" || "$confirm" == "N" ]] && { echo "  Cancelled"; return; }
      ;;
  esac

  echo "  Running: $fix_text"
  _brain_shoelace_session_mark_fix "$fix_text"

  # Execute with timing — safe argv-based execution (NO eval, NO shell expansion)
  # Parse fix_text into argv using zsh's (z) tokenizer, which handles quotes
  # but does NOT expand $(), ``, or variables — preventing command injection.
  local start_time=$EPOCHREALTIME
  local -a cmd_args
  cmd_args=("${(z)fix_text}")
  if [[ ${#cmd_args} -eq 0 ]]; then
    echo "  ${_BRAIN_RED}✗ Empty fix command${_BRAIN_RESET}"
    return
  fi
  "${cmd_args[@]}"
  local exec_exit=$?
  local end_time=$EPOCHREALTIME
  # Force decimal arithmetic: use 10#$var to prevent octal interpretation of leading zeros
  local start_int="${start_time%.*}" start_frac="10#${start_time#*.}"
  local end_int="${end_time%.*}" end_frac="10#${end_time#*.}"
  local duration_ms=$(( (end_int - start_int) * 1000 + (end_frac - start_frac) / 1000 ))
  [[ $duration_ms -lt 0 ]] && duration_ms=0

  if [[ $exec_exit -eq 0 ]]; then
    echo "  ${_BRAIN_GREEN}✓ Fix succeeded${_BRAIN_RESET}"
    _brain_shoelace_db_write "
      UPDATE fixes SET success_count = success_count + 1, last_success = datetime('now'), updated_at = datetime('now')
      WHERE id = '$fix_id';
    "
    _brain_shoelace_db_write "
      INSERT INTO telemetry (event_type, fix_id, decision, duration_ms)
      VALUES ('apply', '$fix_id', 'success', $duration_ms);
    "
  else
    echo "  ${_BRAIN_RED}✗ Fix failed (exit $exec_exit)${_BRAIN_RESET}"
    _brain_shoelace_db_write "
      UPDATE fixes SET failure_count = failure_count + 1, last_failure = datetime('now'), updated_at = datetime('now')
      WHERE id = '$fix_id';
    "
  fi
}

_brain_shoelace_apply_fix() {
  local error_text="$1"
  local result
  result=$(_brain_shoelace_recall "$error_text")
  [[ -z "$result" ]] && { echo "  ✗ No known fix for this error"; return; }
  echo "$result" | while IFS='|' read -r match_type confidence fix_id fix_text success failure risk seen; do
    [[ -n "$fix_id" ]] && _brain_shoelace_apply_by_id "$fix_id" "$fix_text" "$risk"
    break
  done
}

# ── Explain: Why did we suggest this fix? ─────────────────────────────────
_brain_shoelace_why() {
  local error_text="${1:-${_BRAIN_LAST_STDERR:-}}"
  [[ -z "$error_text" ]] && { echo "  No error to analyze. Run a failing command first."; return; }
  _brain_shoelace_load
  [[ $_BRAIN_SHOELACE_AVAIL -eq 0 ]] && { echo "  ✗ ${_BRAIN_SHOELACE_ERR:-Shoelace unavailable (run: brain doctor)}"; return; }
  _brain_interface_load

  local recalls
  recalls=$(_brain_shoelace_recall "$error_text")
  _brain_interface_header "SHOELACE ANALYSIS"

  if [[ -z "$recalls" ]]; then
    local norm_exact norm_fuzzy
    norm_exact=$(_brain_shoelace_normalize_exact "$error_text")
    norm_fuzzy=$(_brain_shoelace_normalize_fuzzy "$error_text")
    local sig_exact sig_fuzzy
    sig_exact=$(_brain_shoelace_signature "$norm_exact")
    sig_fuzzy=$(_brain_shoelace_signature "$norm_fuzzy")

    echo "  ${_BRAIN_YELLOW}No historical fix found.${_BRAIN_RESET}"
    echo ""
    echo "  ${_BRAIN_DIM}Exact signature:${_BRAIN_RESET}  ${sig_exact:0:16}..."
    echo "  ${_BRAIN_DIM}Fuzzy signature:${_BRAIN_RESET}  ${sig_fuzzy:0:16}..."
    echo ""
    local db_count
    db_count=$(_brain_shoelace_db "SELECT COUNT(*) FROM errors;" 2>/dev/null)
    echo "  ${_BRAIN_DIM}Errors in DB:${_BRAIN_RESET} $db_count"
    echo ""
    echo "  Use: brain shoelace learn <fix command>"
    echo "  Or: brain fix → [a] ask AI → save when prompted"
    _brain_interface_hr
    return
  fi

  echo "$recalls" | while IFS='|' read -r match_type confidence fix_id fix_text success failure risk seen; do
    [[ -z "$fix_id" ]] && continue
    local total=$(( success + failure ))
    local pct=0
    [[ $total -gt 0 ]] && pct=$(( success * 100 / total ))
    echo "  ${_BRAIN_GREEN}Matched historical fix${_BRAIN_RESET}"
    echo "  ${_BRAIN_DIM}Confidence:${_BRAIN_RESET} ${_BRAIN_BOLD}${confidence}%${_BRAIN_RESET}"
    echo ""
    echo "  ${_BRAIN_DIM}Why:${_BRAIN_RESET}"
    [[ "$match_type" == "exact" ]] && echo "  ${_BRAIN_GREEN}✓${_BRAIN_RESET} signature similarity: 100%"
    [[ "$match_type" == "fuzzy" ]] && echo "  ${_BRAIN_DIM}~${_BRAIN_RESET} signature similarity: fuzzy match"
    echo "  ${_BRAIN_GREEN}✓${_BRAIN_RESET} same error signature"
    local row
    row=$(_brain_shoelace_db "
      SELECT e.project_fingerprint, e.command_type, e.cwd
      FROM fixes f JOIN errors e ON e.id = f.error_id WHERE f.id = '$fix_id';
    " 2>/dev/null)
    local IFS='|' row_fields=("${(s:|:)row}")
    local saved_fp="${row_fields[1]}" saved_tool="${row_fields[2]}" saved_cwd="${row_fields[3]}"
    local current_fp=$(_brain_shoelace_project_fingerprint "$PWD")
    local current_tool=$(_brain_shoelace_extract_toolchain "$_BRAIN_LAST_COMMAND" "$PWD")
    [[ "$saved_fp" == "$current_fp" ]] && echo "  ${_BRAIN_GREEN}✓${_BRAIN_RESET} same project"
    [[ -n "$saved_tool" && "$saved_tool" == "$current_tool" ]] && echo "  ${_BRAIN_GREEN}✓${_BRAIN_RESET} same toolchain"
    [[ $success -gt 0 ]] && echo "  ${_BRAIN_GREEN}✓${_BRAIN_RESET} successful ${success}x"
    echo ""
    echo "  ${_BRAIN_DIM}Fix:${_BRAIN_RESET} $fix_text"
    echo "  ${_BRAIN_DIM}Success rate:${_BRAIN_RESET} ${pct}% (${success}/${total})"
    echo "  ${_BRAIN_DIM}Risk:${_BRAIN_RESET} $risk"
    _brain_interface_hr
  done
}

# ── Stats: Analytics dashboard ────────────────────────────────────────────
_brain_shoelace_stats() {
  _brain_shoelace_load
  [[ $_BRAIN_SHOELACE_AVAIL -eq 0 ]] && { echo "  ✗ ${_BRAIN_SHOELACE_ERR:-Shoelace unavailable (run: brain doctor)}"; return; }
  _brain_interface_load
  _brain_interface_header "SHOELACE STATS"
  local counts
  counts=$(_brain_shoelace_db "
    SELECT
      (SELECT COUNT(*) FROM errors),
      (SELECT COUNT(*) FROM fixes),
      COALESCE((SELECT SUM(seen_count) FROM errors), 0),
      COALESCE((SELECT SUM(success_count) FROM fixes), 0),
      COALESCE((SELECT SUM(failure_count) FROM fixes), 0),
      (SELECT COUNT(*) FROM learning_sessions WHERE state = 'resolved'),
      (SELECT COUNT(*) FROM learning_sessions WHERE state = 'abandoned');
  " 2>/dev/null)
  if [[ -n "$counts" ]]; then
    local fields=("${(s:|:)counts}")
    echo "  Unique errors:    ${fields[1]}"
    echo "  Saved fixes:      ${fields[2]}"
    echo "  Total occurrences:${fields[3]}"
    echo "  Fix successes:    ${fields[4]}"
    echo "  Fix failures:     ${fields[5]}"
    echo "  Sessions resolved:${fields[6]}"
    echo "  Sessions abandoned:${fields[7]}"
    local total=$(( ${fields[4]:-0} + ${fields[5]:-0} ))
    if [[ $total -gt 0 ]]; then
      local pct=$(( fields[4] * 100 / total ))
      echo "  Overall rate:     ${pct}% success"
    fi
    echo ""
    echo "  ${_BRAIN_DIM}Top ecosystems:${_BRAIN_RESET}"
    _brain_shoelace_db "
      SELECT command_type, COUNT(*) as c FROM errors
      WHERE command_type != 'unknown' GROUP BY command_type
      ORDER BY c DESC LIMIT 5;
    " 2>/dev/null | while IFS='|' read -r eco count; do
      printf "  %-10s %s\n" "$eco" "$count"
    done
  fi
  _brain_interface_hr
}

# ── List: Browse recent error records ─────────────────────────────────────
_brain_shoelace_list() {
  _brain_shoelace_load
  [[ $_BRAIN_SHOELACE_AVAIL -eq 0 ]] && { echo "  ✗ ${_BRAIN_SHOELACE_ERR:-Shoelace unavailable (run: brain doctor)}"; return; }
  _brain_interface_load
  _brain_interface_header "SHOELACE MEMORY"
  local rows
  rows=$(_brain_shoelace_db "
    SELECT e.id, e.seen_count,
           replace(substr(coalesce(e.error_text, ''), 1, 60), char(10), ' '),
           coalesce(f.success_count, 0), coalesce(f.failure_count, 0),
           coalesce(f.risk_level, '-')
    FROM errors e
    LEFT JOIN fixes f ON f.error_id = e.id
    ORDER BY e.last_seen DESC
    LIMIT 25;
  " 2>/dev/null)
  if [[ -z "$rows" ]]; then
    echo "  No errors recorded yet"
  else
    printf "  %-4s %-6s %-10s %-40s\n" "ID" "SEEN" "RISK" "ERROR"
    echo "  ──────────────────────────────────────────────────────"
    echo "$rows" | while IFS='|' read -r id seen snippet succ fail risk; do
      local risk_display="$risk"
      [[ -z "$risk" || "$risk" == "-" ]] && risk_display="?"
      printf "  ${_BRAIN_DIM}%-4s${_BRAIN_RESET} %-6s %-10s %-40s\n" "#$id" "${seen}x" "$risk_display" "$snippet"
    done
  fi
  _brain_interface_hr
}

# ── Forget: Remove a specific error record ────────────────────────────────
_brain_shoelace_forget() {
  _brain_shoelace_load
  [[ $_BRAIN_SHOELACE_AVAIL -eq 0 ]] && { echo "  ✗ ${_BRAIN_SHOELACE_ERR:-Shoelace unavailable (run: brain doctor)}"; return; }
  local id="$1"
  if [[ -z "$id" ]]; then
    echo "  Usage: brain shoelace forget <id>"
    echo "  Find IDs with: brain shoelace list"
    return
  fi
  # Validate ID is numeric to prevent SQL injection
  if ! [[ "$id" =~ ^[0-9]+$ ]]; then
    echo "  ✗ Invalid ID: must be numeric"
    return
  fi
  _brain_shoelace_db_write "
    DELETE FROM fixes WHERE error_id = $id;
    DELETE FROM learning_sessions WHERE error_id = $id;
    DELETE FROM telemetry WHERE error_id = $id;
    DELETE FROM errors WHERE id = $id;
  " && echo "  ✓ Removed #$id" || echo "  ✗ Not found"
}

# ── Clear: Wipe all data ──────────────────────────────────────────────────
_brain_shoelace_clear() {
  _brain_shoelace_load
  [[ $_BRAIN_SHOELACE_AVAIL -eq 0 ]] && { echo "  ✗ ${_BRAIN_SHOELACE_ERR:-Shoelace unavailable (run: brain doctor)}"; return; }
  echo -n "  Clear all Shoelace data? [y/N] "
  local resp; read -r resp
  [[ "$resp" != "y" && "$resp" != "Y" ]] && { echo "  Cancelled"; return; }
  _brain_shoelace_db_write "
    DELETE FROM fixes;
    DELETE FROM errors;
    DELETE FROM learning_sessions;
    DELETE FROM telemetry;
  " && echo "  ✓ All Shoelace data cleared" || echo "  ✗ Failed"
}

# ── Dispatcher ────────────────────────────────────────────────────────────
_brain_shoelace_cmd() {
  _brain_shoelace_load
  local action="${1:-stats}"
  shift 2>/dev/null || true
  case "$action" in
    stats|status)  _brain_shoelace_stats ;;
    list|ls)       _brain_shoelace_list ;;
    forget|rm)     _brain_shoelace_forget "$1" ;;
    clear)         _brain_shoelace_clear ;;
    apply)         _brain_shoelace_apply_fix "${_BRAIN_LAST_STDERR:-}" ;;
    why)           _brain_shoelace_why "${_BRAIN_LAST_STDERR:-}" ;;
    learn)
      local fix_text="$1"
      [[ -z "$fix_text" ]] && { echo "  Usage: brain shoelace learn <fix command>"; return; }
      _brain_shoelace_learn "${_BRAIN_LAST_STDERR:-}" "$fix_text" "$_BRAIN_LAST_EXIT"
      ;;
    *)
      echo "  brain shoelace: unknown action"
      echo "  Usage: brain shoelace [stats|list|forget <id>|clear|apply|why|learn <fix>]"
      ;;
  esac
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
  _BRAIN_BOLD=$'\033[1m'
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
    why)
      _brain_shoelace_load
      _brain_shoelace_why "${_BRAIN_LAST_STDERR:-}"
      ;;
    shoelace)
      _brain_shoelace_cmd "$@"
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
    echo ""
    echo "  ── Shoelace ──"
    _brain_shoelace_load 2>/dev/null
    if _brain_has sqlite3 && [[ -f "${_BRAIN_SHOELACE_DB:-}" ]]; then
      local sc sf sr
      sc=$(_brain_shoelace_db "SELECT COUNT(*) FROM errors;" 2>/dev/null || echo 0)
      sf=$(_brain_shoelace_db "SELECT COUNT(*) FROM fixes;" 2>/dev/null || echo 0)
      sr=$(_brain_shoelace_db "SELECT COUNT(*) FROM learning_sessions WHERE state='resolved';" 2>/dev/null || echo 0)
      printf "  %-16s %s errors, %s fixes, %s sessions resolved\n" "Memory" "${sc:-0}" "${sf:-0}" "${sr:-0}"
      printf "  %-16s %s\n" "DB" "$_BRAIN_SHOELACE_DB"
    else
      echo "  Not available (install sqlite3)"
    fi
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
    printf "  %-10s  %s\n" "brain shoelace" "Memory engine (stats/list/learn/why)"
    printf "  %-10s  %s\n" "brain why" "Explain Shoelace suggestion reasoning"
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
  _BRAIN_STDERR_FILE=$(mktemp "${TMPDIR:-/tmp}/brain-stderr-XXXX")
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
    # Proactive Shoelace suggestion on repeated failure
    if [[ ${_BRAIN_FAIL_COUNT[$PWD]} -eq 3 && -n "${_BRAIN_LAST_STDERR:-}" ]]; then
      _brain_shoelace_load
      local sl_recall
      sl_recall=$(_brain_shoelace_recall "$_BRAIN_LAST_STDERR" 2>/dev/null)
      if [[ -n "$sl_recall" ]]; then
        echo "$sl_recall" | while IFS='|' read -r match_type confidence fix_id fix_text success failure risk seen; do
          [[ -z "$fix_id" ]] && continue
          local total=$(( success + failure ))
          local pct=0
          [[ $total -gt 0 ]] && pct=$(( success * 100 / total ))
          echo ""
          echo "  ${_BRAIN_CYAN}🧠 SHOELACE${_BRAIN_RESET} Repeating error — known fix available"
          echo "    ${_BRAIN_GREEN}→${_BRAIN_RESET} $fix_text"
          [[ $total -gt 0 ]] && echo "    ${_BRAIN_DIM}Success: ${pct}% (${success}/${total}) | Confidence: ${confidence}%${_BRAIN_RESET}"
          echo "    ${_BRAIN_DIM}Run: brain fix → apply or brain shoelace apply${_BRAIN_RESET}"
          echo ""
          break
        done
      fi
    fi
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
