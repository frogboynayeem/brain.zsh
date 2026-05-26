# terminal-os

A unified, context-aware Zsh CLI layer. Single-file brain.zsh dispatcher with lazy-loaded modules.

## Features

- **Project detection** — Node, Rust, Python, Go, Docker, git. Cached persistently.
- **AI routing** — Routes context + query to opencode, claude, or llm
- **Error parsing** — Rust, Python, JS/TS, Go, shell errors with suggestions
- **Session manager** — Create/attach/kill zellij/tmux sessions
- **Persistent cache** — Project types survive terminal restarts
- **Plugin system** — Extend via `~/.config/brain/plugins/`
- **zsh-autocomplete** — Fish-style type-ahead completion
- **Tool degradation** — Every tool has a fallback chain

## Usage

```zsh
source /path/to/brain.zsh
export BRAIN_AI_MODEL=opencode/claude-haiku-4-5  # optional

brain         # auto-detect: global or project mode
brain ai      # AI assistant with context
brain fix     # parse last error
brain session # manage terminal sessions
brain doctor  # system check
```
