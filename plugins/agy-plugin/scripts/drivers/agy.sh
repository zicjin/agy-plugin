# shellcheck shell=bash
#
# drivers/agy.sh — Antigravity CLI (`agy`) driver for agy-delegate.sh.
#
# A driver adapts one headless subagent CLI to the core's normalized contract.
# It is sourced (not executed) by scripts/agy-delegate.sh and must define the
# functions below. See docs/drivers.md for the full interface and how to add a
# new driver (e.g. grok, devin).
#
# Normalized inputs the core provides (read-only for the driver):
#   MODEL TIMEOUT ADD_DIRS[] YOLO SANDBOX CONTINUE CONV_ID PROMPT
#
# agy v1.0.x quirks this driver owns:
#   * `-p/--print` TAKES THE PROMPT AS ITS VALUE -> prompt args go last.
#   * No `--output-format json` -> plain-text only (core enforces the contract).
#   * Headless with no TTY it can drop stdout / hard-hang (worst on native
#     Windows without ConPTY) -> core's stdin detach + wall-clock guard.
#   * Without --dangerously-skip-permissions, headless agy only DESCRIBES
#     edits and writes nothing, yet still exits 0 (issue #10).
#   * `--add-dir` over a WSL /mnt/* Windows mount reads via a slow 9p bridge.

# Read by the sourcing core, which shellcheck can't see across files.
# shellcheck disable=SC2034
DRIVER_BIN="agy"
# shellcheck disable=SC2034
DRIVER_INSTALL_HINT="install the Antigravity CLI first"

# Map a tier (low|medium|high) to an exact model name (see `agy models`).
# Defaults are Gemini Flash thinking levels; each tier is remappable to any agy
# model via env vars, so non-Vertex/non-Gemini plans (Claude/GPT) work without
# code changes. Echoes the model name; returns 1 on an unknown tier.
driver_model_for_tier() {
  case "$1" in
    low)    echo "${AGY_TIER_LOW:-Gemini 3.5 Flash (Low)}" ;;
    medium) echo "${AGY_TIER_MEDIUM:-Gemini 3.5 Flash (Medium)}" ;;
    high)   echo "${AGY_TIER_HIGH:-Gemini 3.5 Flash (High)}" ;;
    *) return 1 ;;
  esac
}

# Fill DRIVER_ARGS (flags) and DRIVER_PROMPT_ARGS (prompt, appended last) from
# the normalized inputs. In agy, -p takes the prompt as its value, so it must
# come last with the prompt attached.
driver_build_args() {
  DRIVER_ARGS=(--model "$MODEL" --print-timeout "$TIMEOUT")
  local d
  for d in "${ADD_DIRS[@]:-}"; do [ -n "$d" ] && DRIVER_ARGS+=(--add-dir "$d"); done
  [ "$YOLO" -eq 1 ]     && DRIVER_ARGS+=(--dangerously-skip-permissions)
  [ "$SANDBOX" -eq 1 ]  && DRIVER_ARGS+=(--sandbox)
  [ "$CONTINUE" -eq 1 ] && DRIVER_ARGS+=(--continue)   # keep working context on the cheap side
  [ -n "$CONV_ID" ]     && DRIVER_ARGS+=(--conversation "$CONV_ID")
  # shellcheck disable=SC2034
  DRIVER_PROMPT_ARGS=(-p "$PROMPT")
  return 0
}

# Classify the CLI's stderr into a structured status. Echoes one of
# QUOTA_EXHAUSTED | AUTH_REQUIRED | TIMEOUT, or nothing for unclassified.
# Scans STDERR only — model-generated stdout could contain trigger words.
# Patterns are deliberately specific to avoid false positives.
driver_classify_error() {
  local blob="$1" status=""
  shopt -s nocasematch
  case "$blob" in
    *quota*|*"rate limit"*|*"resource exhausted"*)
      status=QUOTA_EXHAUSTED ;;
    *unauthenticated*|*unauthorized*|*"sign in"*|*"please authenticate"*|*reauth*)
      status=AUTH_REQUIRED ;;
    *"timed out"*|*"deadline exceeded"*|*"print-timeout"*)
      status=TIMEOUT ;;
  esac
  shopt -u nocasematch
  [ -n "$status" ] && echo "$status"
  return 0
}

# One-line hint appended to an AUTH_REQUIRED signal reason.
driver_auth_hint() { echo "agy not authenticated — run \`agy\` once"; }

# Pre-flight advisory notes (stderr only, never fail). Runs before the dry-run
# exit so --print-command output can be asserted in tests.
driver_prompt_notes() {
  # WSL gotcha: agy reads --add-dir over the /mnt/* Windows mount via a slow 9p
  # bridge, so even trivial calls can take 20s+. Warn (don't fail).
  local d
  if on_wsl; then
    for d in "${ADD_DIRS[@]:-}"; do
      [ -n "$d" ] || continue
      case "$d" in
        /mnt/*) echo "agy-delegate: note: --add-dir '$d' is on a Windows mount under WSL; agy reads it over a slow 9p bridge (calls can take 20s+). Move the repo into the Linux FS (~) for ~10x faster I/O." >&2; break ;;
      esac
    done
  fi
  # Likely write task without --yolo: headless agy only DESCRIBES edits and
  # returns success without writing files (issue #10). Best-effort; warn only.
  if [ "$YOLO" -eq 0 ] && [ "$PRINT_CMD" -ne 1 ]; then
    shopt -s nocasematch
    case "$PROMPT" in
      *implement*|*scaffold*|*migrate*|*refactor*|*"write the file"*|*"create the file"*|*"edit the file"*)
        echo "agy-delegate: note: this looks like a write task but --yolo is not set — without it agy only DESCRIBES edits and writes nothing (still returns success). Add --yolo (and run on a branch) to actually write files." >&2 ;;
    esac
    shopt -u nocasematch
  fi
  return 0
}

# Warning printed before running when the platform has the highest hang risk
# and no wall-clock guard is available.
driver_no_guard_warning() {
  if on_windows_native; then
    echo "agy-delegate: WARNING — native Windows without GNU \`timeout\`/\`gtimeout\` on PATH." >&2
    echo "agy-delegate:   headless \`agy -p\` can hang here with a 0-byte log (no ConPTY). If this" >&2
    echo "agy-delegate:   call never returns, run from WSL/macOS/Linux, or install coreutils \`timeout\`." >&2
  fi
  return 0
}

# Extra hint printed when the wall-clock guard had to kill the CLI.
driver_hang_hint() {
  if on_windows_native; then
    echo "agy-delegate:   native Windows: agy needs a console (ConPTY); run delegation from WSL/macOS/Linux." >&2
  fi
  return 0
}
