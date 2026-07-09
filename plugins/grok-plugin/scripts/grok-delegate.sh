#!/usr/bin/env bash
#
# grok-delegate.sh — headless delegation wrapper for the grok executor (subvibe marketplace).
# Part of the "subvibe" project (subagent delegation plugin for Codex / Claude Code).
#
# Purpose: let the conductor agent hand a well-scoped subtask to the
# **grok** executor CLI and get clean text back on stdout.
# This plugin is single-driver — the executor is fixed to `grok` (no --driver /
# SUBVIBE_DRIVER switch).
#
# Architecture: CLI-agnostic core (this file) + this plugin's driver
# (scripts/drivers/grok.sh). Core owns arg parsing, tier resolution, digest
# contract, hang guard, structured exit codes, and SUBVIBE_SIGNAL. Driver owns
# flag mapping, tier->model, error classification, and CLI quirks.
#
# The core guarantees, whatever the CLI: non-empty stdout on success, non-zero
# exit on failure or empty output, and never blocking on stdin.
#
# Usage:
#   grok-delegate.sh [options] "the task prompt"
#   echo "long prompt" | grok-delegate.sh [options] -      # read prompt from stdin
#
# Options:
#   -t, --tier <low|medium|high>     Thinking/cost tier (default: medium)
#   -d, --dir  <path>                Add a workspace dir (repeatable)
#       --timeout <dur>              Print-mode timeout, e.g. 10m (default: 5m)
#       --yolo                       Auto-approve all tool permissions (DANGEROUS)
#       --sandbox                    Run agent with terminal sandbox restrictions
#       --digest                     Append a digest-only output contract to the prompt
#                                    (ingest digests, not raw dumps — the biggest cost lever)
#   -c, --continue                   Resume the most recent conversation (stateful)
#       --conversation <id>          Resume a specific conversation by ID (stateful)
#   -m, --model <exact name>         Use an exact model name (any the CLI lists)
#       --print-command              Print the resolved command and exit (dry run)
#   -h, --help                       Show this help
#
# Exit codes: 0 ok | 1 usage | 2 CLI failed | 3 empty | 10 quota | 11 auth | 12 timeout | 13 CLI missing
#
# On a classifiable failure, a machine-readable line is printed to stderr so
# orchestrators (e.g. grok-job.sh) can react without scraping prose:
#   SUBVIBE_SIGNAL {"status":"QUOTA_EXHAUSTED","reason":"...","model":"...","retry":"--continue"}
#
# Tiers map to grok-specific model names, remappable per tier. Defaults via
# env: SUBVIBE_DEFAULT_TIER, SUBVIBE_TIMEOUT, SUBVIBE_DEFAULT_MODEL (exact name).
# Per-tier remaps: GROK_TIER_*. Explicit --model/--tier win.
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# Several of these are the normalized inputs read by the sourced driver
# (driver_build_args / driver_prompt_notes), which shellcheck can't see.
# shellcheck disable=SC2034
TIER="${SUBVIBE_DEFAULT_TIER:-medium}"
TIMEOUT="${SUBVIBE_TIMEOUT:-5m}"
DRIVER="grok"  # fixed for this plugin; no env override
TIER_EXPLICIT=0
MODEL=""
YOLO=0
SANDBOX=0
DIGEST=0
ADD_DIRS=()
PROMPT=""
CONTINUE=0
CONV_ID=""
PRINT_CMD=0

die() { echo "grok-delegate: $*" >&2; exit 1; }
# $1 = remaining argc ($#). Fail with a friendly message if an option has no value
# (avoids `shift 2` aborting under `set -e` with a cryptic "shift count" error).
need() { [ "$1" -ge 2 ] || die "option '$2' needs a value"; }

# Emit a one-line machine-readable failure signal to stderr. $1=status $2=reason.
# QUOTA failures advertise `--continue` so a caller knows how to resume the session.
signal() {
  local status="$1" reason="$2" retry=""
  [ "$status" = "QUOTA_EXHAUSTED" ] && retry="--continue"
  # sanitize reason so the JSON stays single-line and valid (no quotes/backslashes/newlines)
  reason="$(printf '%s' "$reason" | tr '\n\r\t' '   ' | tr -d '"\\' | cut -c1-200)"
  printf 'SUBVIBE_SIGNAL {"status":"%s","reason":"%s","model":"%s","retry":"%s"}\n' \
    "$status" "$reason" "${MODEL:-}" "$retry" >&2
}

# Print the header comment between "# Usage:" and "# Exit codes:" (anchored to
# content, not line numbers, so it never desyncs when the header changes).
usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# True when running under WSL (Windows Subsystem for Linux).
on_wsl() { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; }

# True on native Windows (Git Bash / MSYS / Cygwin) — NOT WSL.
on_windows_native() {
  case "${OSTYPE:-}" in msys*|cygwin*|win32) return 0 ;; esac
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac
  return 1
}

# Resolve a usable `timeout`-style command: GNU coreutils `timeout`, or macOS
# Homebrew's `gtimeout`. Echoes the command name, or empty if neither exists.
# We wrap the CLI in this so a headless/no-TTY hang (the CLI never returns) is
# bounded by wall-clock — its own timeout can't fire if it hangs before starting.
timeout_cmd() {
  if command -v timeout  >/dev/null 2>&1; then echo timeout;  return 0; fi
  if command -v gtimeout >/dev/null 2>&1; then echo gtimeout; return 0; fi
  return 1
}

# Convert a duration (e.g. 5m, 300s, 1h, or a bare number=seconds) to whole
# seconds, then add a small head-room margin so the OUTER wall-clock guard
# fires only AFTER the CLI's own timeout has had its chance. Echoes seconds.
outer_timeout_secs() {
  local d="${1:-5m}" n unit secs
  n="${d%[smh]}"; unit="${d#"$n"}"
  case "$n" in (*[!0-9]*|'') n=300; unit=s ;; esac
  case "$unit" in
    h) secs=$(( n * 3600 )) ;;
    m) secs=$(( n * 60 )) ;;
    s|'') secs=$(( n )) ;;
    *) secs=$(( n )) ;;
  esac
  # head-room so the OUTER guard never pre-empts the CLI's own timeout on a
  # legitimately-slow-but-progressing call: +25% of the budget, min 10s, capped 120s.
  local pad=$(( secs / 4 ))
  [ "$pad" -lt 10 ]  && pad=10
  [ "$pad" -gt 120 ] && pad=120
  echo $(( secs + pad ))
}

# YOLO/SANDBOX/CONTINUE/CONV_ID are normalized inputs read by the sourced
# driver (driver_build_args), which shellcheck can't see across files.
# shellcheck disable=SC2034
while [ $# -gt 0 ]; do
  case "$1" in
    -t|--tier)      need "$#" "$1"; TIER="$2"; TIER_EXPLICIT=1; shift 2 ;;
    -d|--dir)       need "$#" "$1"; ADD_DIRS+=("$2"); shift 2 ;;
    --timeout)      need "$#" "$1"; TIMEOUT="$2"; shift 2 ;;
    --yolo)         YOLO=1; shift ;;
    --sandbox)      SANDBOX=1; shift ;;
    --digest)       DIGEST=1; shift ;;               # ask the subagent for a digest-only reply
    -c|--continue)  CONTINUE=1; shift ;;            # resume most recent conversation
    --conversation) need "$#" "$1"; CONV_ID="$2"; shift 2 ;; # resume a specific conversation by ID
    -m|--model)     need "$#" "$1"; MODEL="$2"; shift 2 ;;
    --print-command) PRINT_CMD=1; shift ;;          # dry run: show the resolved command
    -h|--help)      usage ;;
    -)              PROMPT="$(cat)"; shift ;;       # read prompt from stdin
    --)             shift; PROMPT="${*:-}"; break ;;
    -*)             die "unknown option '$1'" ;;
    *)              PROMPT="$*"; break ;;            # rest is the prompt
  esac
done

# --- load the driver (flag mapping, tier->model, error classification, quirks) ---
case "$DRIVER" in
  */*|*..*) die "invalid driver name '$DRIVER'" ;;
esac
DRIVER_FILE="$HERE/drivers/$DRIVER.sh"
[ -f "$DRIVER_FILE" ] || die "driver file missing: $DRIVER_FILE"
# shellcheck source=drivers/grok.sh
. "$DRIVER_FILE"

[ -n "$PROMPT" ] || die "no prompt given (pass a string, or '-' to read stdin)"
# --print-command is a dry run (introspection), so it doesn't require the CLI on PATH.
if [ "$PRINT_CMD" -ne 1 ] && ! command -v "$DRIVER_BIN" >/dev/null 2>&1; then
  echo "grok-delegate: '$DRIVER_BIN' not found on PATH — $DRIVER_INSTALL_HINT" >&2
  signal CLI_MISSING "$DRIVER_BIN not on PATH"
  exit 13
fi

# Resolve the executor model. Precedence:
#   --model > explicit --tier > userConfig default_model > default tier (mapped).
# Tiers map to driver-specific model names and are remappable (see the driver).
if [ -z "$MODEL" ]; then
  if [ "$TIER_EXPLICIT" -eq 1 ]; then
    MODEL="$(driver_model_for_tier "$TIER")" || die "unknown tier '$TIER' (use low | medium | high)"
  elif [ -n "${SUBVIBE_DEFAULT_MODEL:-}" ]; then
    MODEL="$SUBVIBE_DEFAULT_MODEL"
  else
    # default tier from userConfig; a bad value shouldn't make every call die.
    case "$TIER" in
      low|medium|high) ;;
      *) echo "grok-delegate: invalid default tier '$TIER' (set SUBVIBE_DEFAULT_TIER to low|medium|high); using medium" >&2; TIER="medium" ;;
    esac
    MODEL="$(driver_model_for_tier "$TIER")" || die "unknown tier '$TIER'"
  fi
fi

# Driver-specific advisory notes (slow mounts, permission-mode gotchas, ...).
driver_prompt_notes

# --digest: append an explicit output contract so the subagent returns a compact
# digest instead of raw content. Ingesting digests (never dumps) is the plugin's
# single biggest cost lever — it keeps the conductor's context lean (issue #5).
# (Appended AFTER driver_prompt_notes so heuristics scan the user's prompt only.)
if [ "$DIGEST" -eq 1 ]; then
  PROMPT="$PROMPT

OUTPUT CONTRACT (digest): reply with ONLY a compact digest — short bullets (findings / decisions / errors, with file:line references where useful). NO full file contents, NO raw logs, NO long code blocks. End with exactly one line: DIGEST: <one-sentence summary>."
fi

# --- assemble the command via the driver ---
DRIVER_ARGS=()
DRIVER_PROMPT_ARGS=()
driver_build_args

# --- dry run: print the resolved (shell-quoted) invocation and exit ---
if [ "$PRINT_CMD" -eq 1 ]; then
  { printf '%s' "$DRIVER_BIN"; printf ' %q' "${DRIVER_ARGS[@]}" "${DRIVER_PROMPT_ARGS[@]}"; printf '\n'; }
  exit 0
fi

# --- run (always detach stdin so non-TTY stdout is not dropped) ---
# Per-invocation temp file for stderr (mktemp avoids the race + symlink risk of a
# fixed /tmp path when multiple delegations run concurrently). Cleaned up on exit.
ERR="$(mktemp "${TMPDIR:-/tmp}/grok-delegate.XXXXXX")"
trap 'rm -f "$ERR"' EXIT

# Wall-clock guard: on a non-TTY caller (the whole point of this wrapper), the
# CLI can hard-hang before its own timeout engages. Wrap in GNU `timeout`/
# `gtimeout` when available so we always return instead of hanging forever.
# `timeout` exits 124 on kill -> map to our TIMEOUT (12) and emit the structured
# signal, so orchestrators react cleanly.
TO_CMD="$(timeout_cmd || true)"
TO_SECS="$(outer_timeout_secs "$TIMEOUT")"

[ -z "$TO_CMD" ] && driver_no_guard_warning

set +e
if [ -n "$TO_CMD" ]; then
  # --kill-after sends SIGKILL if the CLI ignores the initial SIGTERM (defensive).
  OUT="$("$TO_CMD" --kill-after=10 "$TO_SECS" "$DRIVER_BIN" "${DRIVER_ARGS[@]}" "${DRIVER_PROMPT_ARGS[@]}" < /dev/null 2>"$ERR")"
  RC=$?
else
  OUT="$("$DRIVER_BIN" "${DRIVER_ARGS[@]}" "${DRIVER_PROMPT_ARGS[@]}" < /dev/null 2>"$ERR")"
  RC=$?
fi
set -e

# `timeout` exits 124 (SIGTERM) or 137 (SIGKILL after --kill-after) when it had
# to kill the CLI. Treat that as our structured TIMEOUT (exit 12).
if [ -n "$TO_CMD" ] && { [ $RC -eq 124 ] || [ $RC -eq 137 ]; }; then
  echo "grok-delegate: $DRIVER_BIN hit the wall-clock guard (${TO_SECS}s) and was terminated — likely a headless/no-TTY hang." >&2
  driver_hang_hint
  signal TIMEOUT "$DRIVER_BIN wall-clock guard fired after ${TO_SECS}s (headless/no-TTY hang?)"
  exit 12
fi

if [ $RC -ne 0 ]; then
  echo "grok-delegate: $DRIVER_BIN exited $RC" >&2
  [ -s "$ERR" ] && cat "$ERR" >&2
  # Best-effort classification into a structured code (the generic 2 is the safe
  # fallback). The driver owns the CLI-specific stderr patterns.
  STATUS="$(driver_classify_error "$(cat "$ERR" 2>/dev/null)")"
  case "$STATUS" in
    QUOTA_EXHAUSTED) signal QUOTA_EXHAUSTED "$DRIVER_BIN quota / rate limit"; exit 10 ;;
    AUTH_REQUIRED)   signal AUTH_REQUIRED "$(driver_auth_hint)"; exit 11 ;;
    TIMEOUT)         signal TIMEOUT "$DRIVER_BIN timeout / deadline exceeded"; exit 12 ;;
  esac
  signal CLI_FAILED "$DRIVER_BIN exited $RC"
  exit 2
fi
if [ -z "${OUT//[$' \t\n\r']/}" ]; then
  echo "grok-delegate: $DRIVER_BIN returned empty output (model='$MODEL')" >&2
  exit 3
fi

# Digest-size guard: the cost saving depends on the conductor ingesting a DIGEST,
# not a raw dump — if the reply is dump-sized, say so on stderr (advisory only;
# stdout passes through untouched). Tune via env SUBVIBE_DIGEST_WARN_CHARS
# (empty = 8000, 0 = off).
WARN_CHARS="${SUBVIBE_DIGEST_WARN_CHARS:-8000}"
case "$WARN_CHARS" in (*[!0-9]*|'') WARN_CHARS=8000 ;; esac
if [ "$WARN_CHARS" -gt 0 ] && [ "${#OUT}" -gt "$WARN_CHARS" ]; then
  echo "grok-delegate: note: output is ${#OUT} chars (> ${WARN_CHARS}) — that looks like a raw dump, not a digest. Don't ingest this into the conductor's context: re-run with --digest, or have the executor summarize it first. (env SUBVIBE_DIGEST_WARN_CHARS tunes this; 0 disables.)" >&2
fi

printf '%s\n' "$OUT"
