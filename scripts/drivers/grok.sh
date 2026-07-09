# shellcheck shell=bash
#
# drivers/grok.sh — Grok Build CLI (`grok`, x.ai/cli) driver for agy-delegate.sh.
#
# Sourced (not executed) by scripts/agy-delegate.sh. See docs/drivers.md for
# the driver interface. Select with `--driver grok` or `AGY_DRIVER=grok`.
#
# Flag mapping (verified against grok 0.2.93 `--help`):
#   prompt        -> -p/--single <PROMPT>   (takes the prompt as its value, last)
#   tier          -> low = grok-composer-2.5-fast (cheap composer model);
#                    medium/high = grok-4.5 + --reasoning-effort medium|high
#                    (remap via GROK_TIER_* / --model; see `grok models`)
#   --dir         -> --cwd <dir>  (grok takes ONE working dir; extras are warned about)
#   --yolo        -> --always-approve
#   --sandbox     -> --sandbox <profile>  (default `readonly`; env GROK_SANDBOX_PROFILE)
#   --continue    -> -c/--continue
#   --conversation-> --resume <session-id>
#   --timeout     -> no CLI equivalent; bounded by the core's wall-clock guard
#
# grok quirks this driver owns:
#   * Unauthenticated headless `grok -p` HANGS (no prompt, no error exit) — the
#     core's wall-clock guard kills it; the hang hint points at `grok login`.
#   * `--sandbox` REQUIRES a named profile and refuses to start on an unknown
#     one ("could not apply the '<name>' sandbox profile").

# Read by the sourcing core, which shellcheck can't see across files.
# shellcheck disable=SC2034
DRIVER_BIN="grok"
# shellcheck disable=SC2034
DRIVER_INSTALL_HINT="install Grok Build: curl -fsSL https://x.ai/cli/install.sh | bash"

# Tier defaults verified against a live subscriber account (`grok models`):
# grok-4.5 (default, supports --reasoning-effort) and grok-composer-2.5-fast
# (fast composer model; ignores effort with a warning). Note the unauthenticated
# CLI advertises a `grok-build` model id that real accounts REJECT. Each tier
# is remappable to any `grok models` entry via env vars.
driver_model_for_tier() {
  case "$1" in
    low)    echo "${GROK_TIER_LOW:-grok-composer-2.5-fast}" ;;
    medium) echo "${GROK_TIER_MEDIUM:-grok-4.5}" ;;
    high)   echo "${GROK_TIER_HIGH:-grok-4.5}" ;;
    *) return 1 ;;
  esac
}

driver_build_args() {
  DRIVER_ARGS=(--model "$MODEL")
  # Effort only differentiates tiers on models that support it; composer models
  # ignore it with a warning, so passing it is harmless.
  case "$TIER" in
    medium|high) DRIVER_ARGS+=(--reasoning-effort "$TIER") ;;
  esac
  # grok takes a single working directory (--cwd), not repeatable add-dirs.
  local d first=""
  for d in "${ADD_DIRS[@]:-}"; do
    [ -n "$d" ] || continue
    if [ -z "$first" ]; then first="$d"; else
      echo "agy-delegate: note: grok supports one working dir (--cwd); ignoring extra --dir '$d'" >&2
    fi
  done
  [ -n "$first" ]       && DRIVER_ARGS+=(--cwd "$first")
  [ "$YOLO" -eq 1 ]     && DRIVER_ARGS+=(--always-approve)
  [ "$SANDBOX" -eq 1 ]  && DRIVER_ARGS+=(--sandbox "${GROK_SANDBOX_PROFILE:-readonly}")
  [ "$CONTINUE" -eq 1 ] && DRIVER_ARGS+=(--continue)
  [ -n "$CONV_ID" ]     && DRIVER_ARGS+=(--resume "$CONV_ID")
  # shellcheck disable=SC2034
  DRIVER_PROMPT_ARGS=(-p "$PROMPT")
  return 0
}

driver_classify_error() {
  local blob="$1" status=""
  shopt -s nocasematch
  case "$blob" in
    *quota*|*"rate limit"*|*"out of credits"*|*"resource exhausted"*)
      status=QUOTA_EXHAUSTED ;;
    *"not authenticated"*|*"auth credentials"*|*unauthorized*|*"grok login"*)
      status=AUTH_REQUIRED ;;
    *"timed out"*|*"deadline exceeded"*)
      status=TIMEOUT ;;
  esac
  shopt -u nocasematch
  [ -n "$status" ] && echo "$status"
  return 0
}

driver_auth_hint() { echo "grok not authenticated — run \`grok login\` (or set XAI_API_KEY)"; }

driver_prompt_notes() {
  # Without --yolo, headless grok runs in ask-mode with nobody to approve —
  # write/shell tool calls stall or get denied. Best-effort heuristic; warn only.
  if [ "$YOLO" -eq 0 ] && [ "$PRINT_CMD" -ne 1 ]; then
    shopt -s nocasematch
    case "$PROMPT" in
      *implement*|*scaffold*|*migrate*|*refactor*|*"write the file"*|*"create the file"*|*"edit the file"*)
        echo "agy-delegate: note: this looks like a write task but --yolo is not set — headless grok has nobody to approve tool calls, so writes will stall or be denied. Add --yolo (and run on a branch) to actually write files." >&2 ;;
    esac
    shopt -u nocasematch
  fi
  return 0
}

driver_no_guard_warning() {
  echo "agy-delegate: WARNING — no GNU \`timeout\`/\`gtimeout\` on PATH." >&2
  echo "agy-delegate:   unauthenticated headless \`grok -p\` hangs instead of failing; without a" >&2
  echo "agy-delegate:   wall-clock guard this call may never return. Install coreutils \`timeout\`." >&2
  return 0
}

driver_hang_hint() {
  echo "agy-delegate:   grok hangs headless when not authenticated — run \`grok login\` (or set XAI_API_KEY) and retry." >&2
  return 0
}
