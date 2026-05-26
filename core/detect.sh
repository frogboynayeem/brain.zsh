#!/usr/bin/env bash
# ============================================================================
# TERMINAL OS v2.1 — Project Detection Engine
# ============================================================================
# Detects project type by analysing directory contents.
# Output format: TYPE:SUBTYPE (e.g. "rust:library" or "python:fastapi")
# Exits with code 0 if detected, 1 if unknown.
# ============================================================================

set -euo pipefail

TOPDIR="${1:-$PWD}"

# ── Git Detection ──────────────────────────────────────────────────────────
if git -C "$TOPDIR" rev-parse --git-dir &>/dev/null; then
  GIT_REPO="true"
  GIT_BRANCH=$(git -C "$TOPDIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
  GIT_DIRTY=$(git -C "$TOPDIR" status --porcelain 2>/dev/null | wc -l)
  GIT_REMOTE=$(git -C "$TOPDIR" remote -v 2>/dev/null | head -1 | awk '{print $2}' || echo "")
else
  GIT_REPO="false"
  GIT_BRANCH=""
  GIT_DIRTY=0
  GIT_REMOTE=""
fi

# ── Rust Detection ─────────────────────────────────────────────────────────
if [[ -f "$TOPDIR/Cargo.toml" ]]; then
  IS_WORKSPACE=$(grep -c '\[workspace\]' "$TOPDIR/Cargo.toml" 2>/dev/null || echo 0)
  if [[ "$IS_WORKSPACE" -gt 0 ]]; then
    echo "rust:workspace"
  else
    echo "rust:binary"
  fi
  exit 0
fi

# ── Python Detection ───────────────────────────────────────────────────────
if [[ -f "$TOPDIR/pyproject.toml" ]]; then
  PROJECT_NAME=$(grep '^name\s*=' "$TOPDIR/pyproject.toml" 2>/dev/null | head -1 | tr -d ' "=')
  HAS_FASTAPI=$(grep -ci 'fastapi' "$TOPDIR/pyproject.toml" 2>/dev/null || echo 0)
  HAS_DJANGO=$(grep -ci 'django' "$TOPDIR/pyproject.toml" 2>/dev/null || echo 0)
  if [[ "$HAS_FASTAPI" -gt 0 ]]; then echo "python:fastapi"; exit 0; fi
  if [[ "$HAS_DJANGO" -gt 0 ]]; then echo "python:django"; exit 0; fi
  echo "python:pyproject"
  exit 0
fi
if [[ -f "$TOPDIR/requirements.txt" ]]; then
  echo "python:requirements"
  exit 0
fi
if [[ -f "$TOPDIR/setup.py" || -f "$TOPDIR/setup.cfg" ]]; then
  echo "python:package"
  exit 0
fi

# ── Node.js Detection ──────────────────────────────────────────────────────
if [[ -f "$TOPDIR/package.json" ]]; then
  HAS_NEXT=$(grep -ci 'next' "$TOPDIR/package.json" 2>/dev/null || echo 0)
  HAS_VITE=$(grep -ci 'vite' "$TOPDIR/package.json" 2>/dev/null || echo 0)
  HAS_NEST=$(grep -ci '@nestjs' "$TOPDIR/package.json" 2>/dev/null || echo 0)
  if [[ "$HAS_NEXT" -gt 0 ]]; then echo "node:next"; exit 0; fi
  if [[ "$HAS_VITE" -gt 0 ]]; then echo "node:vite"; exit 0; fi
  if [[ "$HAS_NEST" -gt 0 ]]; then echo "node:nest"; exit 0; fi
  echo "node:generic"
  exit 0
fi

# ── Go Detection ───────────────────────────────────────────────────────────
if [[ -f "$TOPDIR/go.mod" ]]; then
  echo "go:module"
  exit 0
fi

# ── Docker Detection ───────────────────────────────────────────────────────
if [[ -f "$TOPDIR/Dockerfile" || -f "$TOPDIR/docker-compose.yml" || -f "$TOPDIR/docker-compose.yaml" ]]; then
  echo "docker:compose"
  exit 0
fi

# ── Generic Git Repo ───────────────────────────────────────────────────────
if [[ "$GIT_REPO" == "true" ]]; then
  echo "git:generic"
  exit 0
fi

# ── No Project Detected ────────────────────────────────────────────────────
exit 1