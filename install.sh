#!/usr/bin/env bash
#
# install.sh — wire agy-plugin-codex into Codex.
#
# What it does (idempotent, reversible with --uninstall):
#   1. symlinks prompts/*.md into ~/.codex/prompts/  (slash commands: /agy-delegate …)
#   2. adds this repo's bin/ to PATH via a line in ~/.bashrc + ~/.zshrc (if present),
#      so Codex's shell tool can call `agy-delegate`, `agy-job`, `agy-doctor` bare.
#   3. prints the AGENTS.md snippet path — paste docs/AGENTS-snippet.md into the
#      AGENTS.md of any repo where Codex should delegate to agy proactively.
#
# Usage:  ./install.sh [--uninstall]
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PROMPTS_DIR="$CODEX_HOME/prompts"
PATH_LINE="export PATH=\"$ROOT/bin:\$PATH\"  # agy-plugin-codex"

uninstall() {
  for p in "$ROOT"/prompts/*.md; do
    t="$PROMPTS_DIR/$(basename "$p")"
    [ -L "$t" ] && rm -f "$t" && echo "removed $t"
  done
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    if grep -qF '# agy-plugin-codex' "$rc"; then
      tmp="$(mktemp)"; grep -vF '# agy-plugin-codex' "$rc" > "$tmp"; cat "$tmp" > "$rc"; rm -f "$tmp"
      echo "removed PATH line from $rc"
    fi
  done
  echo "uninstalled."
}

if [ "${1:-}" = "--uninstall" ]; then uninstall; exit 0; fi

# 1. prompts
mkdir -p "$PROMPTS_DIR"
for p in "$ROOT"/prompts/*.md; do
  t="$PROMPTS_DIR/$(basename "$p")"
  ln -sf "$p" "$t"
  echo "installed prompt: /$(basename "$p" .md)"
done

# 2. PATH
chmod +x "$ROOT"/bin/* "$ROOT"/scripts/*.sh
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  grep -qF '# agy-plugin-codex' "$rc" || { printf '\n%s\n' "$PATH_LINE" >> "$rc"; echo "added bin/ to PATH in $rc"; }
done

# 3. next steps
echo ""
echo "Done. Next:"
echo "  * restart your shell (or: export PATH=\"$ROOT/bin:\$PATH\")"
echo "  * verify: agy-doctor"
echo "  * per repo: paste docs/AGENTS-snippet.md into that repo's AGENTS.md so Codex"
echo "    delegates to agy proactively (Codex reads AGENTS.md automatically)"
echo "  * in Codex: /agy-setup   /agy-delegate <task>   /agy-review   /agy-research <topic>"
