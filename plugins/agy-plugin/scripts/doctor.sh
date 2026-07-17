#!/usr/bin/env bash
#
# doctor.sh — health check for agy-plugin (Antigravity / Gemini executor).
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
on_windows_native() {
  case "${OSTYPE:-}" in msys*|cygwin*|win32) return 0 ;; esac
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac
  return 1
}

echo "agy-plugin — doctor"
echo ""

echo "Plugin scripts"
for s in agy-delegate.sh agy-job.sh doctor.sh; do
  if [ -x "$HERE/$s" ]; then ok "$s executable"; else
    bad "$s not executable"; info "fix: chmod +x \"$HERE/$s\""; fi
done
if [ -f "$HERE/drivers/agy.sh" ]; then ok "driver present: agy"; else bad "driver missing: drivers/agy.sh"; fi
echo ""

echo "Executor: agy (Antigravity / Gemini)"
if command -v agy >/dev/null 2>&1; then
  ok "agy found: $(command -v agy)  ($(cli_guard 10 agy --version 2>/dev/null | head -1))"
  if [ -z "$TO_CMD" ]; then
    warn "no \`timeout\`/\`gtimeout\` on PATH — cannot bound a possible \`agy models\` hang"
  fi
  MODELS="$(cli_guard 20 agy models 2>/dev/null)"; AGY_RC=$?
  AGY_TIMED_OUT=0
  { [ "$AGY_RC" -eq 124 ] || [ "$AGY_RC" -eq 137 ]; } && AGY_TIMED_OUT=1
  if [ "$AGY_TIMED_OUT" -eq 1 ]; then
    bad "\`agy models\` hung and was killed after 20s — this is NOT an auth problem"
    info "agy hangs when run headless with no TTY/console (0-byte log, no output)."
    if on_windows_native; then
      info "native Windows: agy needs a real console (ConPTY). Run delegation from WSL/macOS/Linux."
    fi
    MODELS=""
  fi
  if [ -n "$MODELS" ]; then
    ok "agy authenticated — $(printf '%s' "$MODELS" | grep -c . ) models available"
    LOW="${AGY_TIER_LOW:-Gemini 3.5 Flash (Low)}"
    MEDIUM="${AGY_TIER_MEDIUM:-Gemini 3.5 Flash (Medium)}"
    HIGH="${AGY_TIER_HIGH:-Gemini 3.5 Flash (High)}"
    for m in "$LOW" "$MEDIUM" "$HIGH"; do
      if printf '%s' "$MODELS" | grep -qF "$m"; then ok "tier model present: $m"
      else
        warn "tier model not in 'agy models': $m"
        info "remap via AGY_TIER_* (or SUBVIBE_DEFAULT_MODEL), or pass --model <name from \`agy models\`>"
      fi
    done
  elif [ "$AGY_TIMED_OUT" -eq 0 ]; then
    bad "agy could not list models (not authenticated, or no network)"
    info "fix: authenticate agy (run \`agy\` once interactively) and check GCP access"
  fi
  SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
  if [ -f "$SETTINGS" ]; then
    PROJ="$(sed -n 's/.*"project"[: ]*"\([^"]*\)".*/\1/p' "$SETTINGS" | head -1)"
    LOC="$(sed -n 's/.*"location"[: ]*"\([^"]*\)".*/\1/p' "$SETTINGS" | head -1)"
    ok "agy settings: ${SETTINGS/#$HOME/~}"
    [ -n "$PROJ" ] && info "GCP project: $PROJ   location: ${LOC:-?}"
  else
    info "no agy settings.json yet (${SETTINGS/#$HOME/~})"
  fi
else
  bad "agy NOT on PATH"
  info "fix: install the Antigravity CLI, then ensure its bin dir is on PATH"
fi
echo ""

if grep -qi microsoft /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
  echo "Environment"
  case "$PWD" in
    /mnt/*)
      warn "WSL + workspace on a Windows mount ($PWD)"
      info "agy --add-dir reads this over a slow 9p bridge (calls can take 20s+)."
      info "fix: move the repo into the WSL Linux filesystem (e.g. ~/projects)" ;;
    *) ok "WSL detected; workspace is on the Linux filesystem" ;;
  esac
  echo ""
fi

if [ "$FAIL" -eq 0 ]; then echo "All checks passed — ready to delegate with agy."; else
  echo "Some checks failed — see fixes above."; fi
exit "$FAIL"
