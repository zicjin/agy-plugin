#!/usr/bin/env bash
#
# doctor.sh — health check for grok-plugin (Grok Build executor).
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ok()   { printf '  ✓ %s\n' "$*"; }
bad()  { printf '  ✗ %s\n' "$*"; FAIL=1; }
warn() { printf '  ⚠ %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
FAIL=0

TO_CMD=""
if   command -v timeout  >/dev/null 2>&1; then TO_CMD=timeout
elif command -v gtimeout >/dev/null 2>&1; then TO_CMD=gtimeout
fi
cli_guard() {
  local secs="$1"; shift
  if [ -n "$TO_CMD" ]; then "$TO_CMD" --kill-after=5 "$secs" "$@"; return $?; fi
  "$@"
}

echo "grok-plugin — doctor"
echo ""

echo "Plugin scripts"
for s in grok-delegate.sh grok-job.sh doctor.sh; do
  if [ -x "$HERE/$s" ]; then ok "$s executable"; else
    bad "$s not executable"; info "fix: chmod +x \"$HERE/$s\""; fi
done
if [ -f "$HERE/drivers/grok.sh" ]; then ok "driver present: grok"; else bad "driver missing: drivers/grok.sh"; fi
echo ""

echo "Executor: grok (Grok Build)"
if command -v grok >/dev/null 2>&1; then
  ok "grok found: $(command -v grok)  ($(cli_guard 10 grok --version 2>/dev/null | head -1))"
  if [ -z "$TO_CMD" ]; then
    warn "no \`timeout\`/\`gtimeout\` on PATH — cannot bound a possible headless hang"
    info "install coreutils \`timeout\` (or Homebrew \`gtimeout\`)"
  fi
  GROK_OUT="$(cli_guard 20 grok models 2>/dev/null)"; GROK_RC=$?
  GROK_TIMED_OUT=0
  { [ "$GROK_RC" -eq 124 ] || [ "$GROK_RC" -eq 137 ]; } && GROK_TIMED_OUT=1
  if [ "$GROK_TIMED_OUT" -eq 1 ]; then
    bad "\`grok models\` hung and was killed after 20s — often means not authenticated"
    info "run \`grok login\` (or set XAI_API_KEY). Unauthenticated headless grok hangs instead of failing."
  elif [ -n "$GROK_OUT" ]; then
    ok "grok authenticated — models list returned output"
    LOW="${GROK_TIER_LOW:-grok-composer-2.5-fast}"
    MEDIUM="${GROK_TIER_MEDIUM:-grok-4.5}"
    HIGH="${GROK_TIER_HIGH:-grok-4.5}"
    for m in "$LOW" "$MEDIUM" "$HIGH"; do
      if printf '%s' "$GROK_OUT" | grep -qF "$m"; then ok "tier model present: $m"
      else
        warn "tier model not in 'grok models': $m"
        info "remap via GROK_TIER_* (or SUBVIBE_DEFAULT_MODEL), or pass --model <name from \`grok models\`>"
      fi
    done
  else
    bad "grok could not list models (not authenticated, or no network)"
    info "fix: run \`grok login\` (or set XAI_API_KEY)"
  fi
else
  bad "grok NOT on PATH"
  info "fix: install Grok Build — curl -fsSL https://x.ai/cli/install.sh | bash"
fi
echo ""

if [ "$FAIL" -eq 0 ]; then echo "All checks passed — ready to delegate with grok."; else
  echo "Some checks failed — see fixes above."; fi
exit "$FAIL"
