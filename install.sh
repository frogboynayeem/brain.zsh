#!/usr/bin/env bash
set -euo pipefail

REPO="frogboynayeem/brain.zsh"
BRANCH="${BRAIN_INSTALL_BRANCH:-main}"
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/terminal-os"
SOURCE_LINE="source \"\$HOME/.config/terminal-os/brain.zsh\""

# ── Colors ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

info()  { printf "${CYAN}  →${NC} %s\n" "$1"; }
ok()    { printf "${GREEN}  ✓${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}  ⚠${NC} %s\n" "$1"; }
err()   { printf "${RED}  ✗${NC} %s\n" "$1"; exit 1; }

echo ""
printf "${BOLD}🧠 brain.zsh — Installer${NC}\n"
echo ""

# ── Detect shell ────────────────────────────────────────────────────────────
case "${SHELL:-}" in
  */zsh)  RC_FILE="${ZDOTDIR:-$HOME}/.zshrc" ;;
  */bash) RC_FILE="${HOME}/.bashrc" ;;
  *)      err "Unsupported shell: $SHELL. brain.zsh requires zsh." ;;
esac

[[ -f "$RC_FILE" ]] || touch "$RC_FILE"

# ── Download ─────────────────────────────────────────────────────────────────
info "Downloading brain.zsh ($BRANCH)..."

mkdir -p "$INSTALL_DIR"
TARBALL="https://api.github.com/repos/$REPO/tarball/$BRANCH"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$TARBALL" -o "$TMPDIR/repo.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -q "$TARBALL" -O "$TMPDIR/repo.tar.gz"
else
  err "Need curl or wget to download."
fi

tar xzf "$TMPDIR/repo.tar.gz" -C "$TMPDIR" --strip-components=1
cp "$TMPDIR/brain.zsh" "$INSTALL_DIR/brain.zsh"
chmod 644 "$INSTALL_DIR/brain.zsh"

# Copy support files
for f in ai/router.zsh core/detect.sh core/hooks.zsh core/init.zsh core/session.zsh \
         layouts/dev.kdl layouts/ops.kdl layouts/research.kdl \
         utils/helpers.zsh utils/launcher.zsh; do
  mkdir -p "$INSTALL_DIR/$(dirname "$f")"
  cp "$TMPDIR/$f" "$INSTALL_DIR/$f"
done
cp "$TMPDIR/LICENSE" "$INSTALL_DIR/" 2>/dev/null || true

ok "brain.zsh installed to $INSTALL_DIR/brain.zsh"

# ── Configure shell ─────────────────────────────────────────────────────────
if grep -qsF "$SOURCE_LINE" "$RC_FILE"; then
  info "Source line already in $RC_FILE"
else
  {
    echo ""
    echo "# brain.zsh — context-aware CLI layer"
    echo "$SOURCE_LINE"
  } >> "$RC_FILE"
  ok "Added source line to $RC_FILE"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
printf "  ${GREEN}Install complete!${NC}\n"
echo ""
echo "  Reload your shell to start using brain:"
echo ""
echo "    ${CYAN}source $RC_FILE${NC}"
echo ""
echo "  Or open a new terminal. Then type:"
echo ""
echo "    ${BOLD}brain${NC}        — show dashboard"
echo "    ${BOLD}brain doctor${NC} — check all tools"
echo "    ${BOLD}brain help${NC}   — list all commands"
echo ""

# ── Post-install hint ──────────────────────────────────────────────────────
if ! command -v opencode >/dev/null 2>&1 && \
   ! command -v claude >/dev/null 2>&1; then
  echo "  ${DIM}Tip: Install an AI CLI (opencode, claude) to use 'brain ai'.${NC}"
fi
