# brain.zsh

> A context-aware terminal OS layer for Zsh.
> Not a prompt. Not a plugin manager. A brain.

Single-file Zsh dispatcher with lazy-loaded modules. It detects your project, routes context to AI, parses errors, manages sessions, and persists cache — all under 8ms source time.

## What it is

| They built | brain.zsh does |
|------------|----------------|
| Pretty prompt (Starship) | State machine + event system |
| AI command suggestion (zsh-ai) | Full context injection + routing |
| Plugin management (oh-my-zsh) | Error parsing + autonomous mode |

**brain.zsh** combines state machine, event hooks, project detection, AI routing, error parsing, session management, and autonomous mode — into one unified thing that didn't exist before.

## Features

- **Project detection** — Node, Rust, Python, Go, Docker, git. Cached persistently across terminal restarts.
- **AI routing** — Builds rich context (project type, branch, git log, file tree, last command) and routes it to opencode, claude, or llm.
- **Error parsing** — Rust, Python, JS/TS, Go, and shell errors (`command not found`, `permission denied`, `syntax error`) with suggestions.
- **Auto-capture stderr** — Every command's stderr is saved automatically. `brain fix` works without manual piping.
- **Session manager** — `brain session new/attach/kill` for zellij and tmux.
- **Persistent cache** — `~/.cache/brain/projects` survives terminal restarts. Zero re-scan.
- **Plugin system** — `brain plugin list/load` scans `~/.config/brain/plugins/`.
- **Autonomous mode** — After 3 identical failures, suggests and optionally runs auto-fixes.
- **Tool degradation** — Every tool has a fallback chain. Never crashes on missing deps.
- **zsh-autocomplete** — Fish-style type-ahead completion (Marlon Richert, v25.03.19).
- **~30ms source time** — Everything is lazy-loaded. Nothing runs until you call `brain`.

## Usage

```zsh
source /path/to/brain.zsh
export BRAIN_AI_MODEL=opencode/claude-haiku-4-5  # optional

brain         # auto-detect: global or project mode
brain ai      # AI assistant with context
brain fix     # parse last error
brain session # manage terminal sessions (new/attach/kill)
brain doctor  # system check
brain plugin  # manage plugins (list/load)
brain cache   # clear project cache
```

## Architecture

```
brain.zsh (~1,070 lines)
├── Bootstrap          — version guard, cache vars, module flags
├── Detection          — OS, arch, tool availability
├── History            — atuin / fc integration
├── Navigation         — zoxide / cd / fzf
├── Git                — branch, dirty, log, diff
├── Project            — walk-up detection, persistent cache
├── AI                 — context builder, model routing
├── Error parsing      — Rust/Python/JS/Go/Shell regex engine
├── Plugins            — dir scan, lazy source
├── Interface          — colored headers, key bindings
├── Dispatcher         — brain() case switch
├── Doctor             — system health check
├── Modes              — global / project / error / git / files / session
└── Hooks              — preexec/precmd for failure tracking
```

## Files

```
~/.config/terminal-os/
├── brain.zsh           ← the brain (source this)
├── terminal-os.zsh     ← wrapper / legacy compat
├── uninstall.sh        ← clean removal
├── core/               ← detect, hooks, init, session
├── ai/                 ← router
├── layouts/            ← zellij layouts (dev, ops, research)
└── utils/              ← helpers, launcher
```

## License

MIT — do whatever you want with it.
