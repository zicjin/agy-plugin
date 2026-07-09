# Subagent CLI drivers

`scripts/agy-delegate.sh` is split into a **CLI-agnostic core** and one
**driver** per subagent CLI (`scripts/drivers/<name>.sh`). The core owns
everything a conductor relies on regardless of which CLI executes the work;
the driver owns everything specific to that CLI.

| Layer | Owns |
| --- | --- |
| core (`agy-delegate.sh`) | arg parsing · tier resolution & precedence · `--digest` output contract · stdin detach · wall-clock hang guard · empty-output check · digest-size guard · structured exit codes · `AGY_SIGNAL` machine-readable failures |
| driver (`drivers/<name>.sh`) | binary name · tier → model names (+ env remaps) · flag mapping · stderr → error classification · CLI-specific quirks & warnings |

The background-job layer (`agy-job.sh`) sits on top of the core and is
driver-agnostic for free — it only consumes the core's exit codes and signals.

## Selecting a driver

```bash
agy-delegate.sh --driver agy "task"     # per call
export AGY_DRIVER=agy                    # default for all calls
```

Available drivers:

| driver | CLI | tier mapping |
| --- | --- | --- |
| `agy` (default) | Antigravity CLI | tier → Gemini Flash thinking-level model names (`AGY_TIER_*`) |
| `grok` | Grok Build (x.ai/cli) | low → `grok-composer-2.5-fast`; medium/high → `grok-4.5` + `--reasoning-effort` (`GROK_TIER_*`) |

## Driver interface

A driver is a bash file that is **sourced** (not executed) by the core. It must
define:

| Symbol | Contract |
| --- | --- |
| `DRIVER_BIN` | binary name looked up on PATH (missing → exit 13 + `AGY_MISSING` signal) |
| `DRIVER_INSTALL_HINT` | one-line install hint shown when the binary is missing |
| `driver_model_for_tier <low\|medium\|high>` | echo the exact model name; return 1 on an unknown tier |
| `driver_build_args` | fill `DRIVER_ARGS` (flags) and `DRIVER_PROMPT_ARGS` (prompt args, appended last) from the normalized inputs |
| `driver_classify_error <stderr-blob>` | echo `QUOTA_EXHAUSTED` \| `AUTH_REQUIRED` \| `TIMEOUT`, or nothing (→ generic failure, exit 2) |
| `driver_auth_hint` | echo a one-line re-auth hint for `AUTH_REQUIRED` |
| `driver_prompt_notes` | advisory stderr notes before running (never fail) |
| `driver_no_guard_warning` | warning when no `timeout`/`gtimeout` guard is available |
| `driver_hang_hint` | extra stderr hint when the wall-clock guard killed the CLI |

Normalized inputs the core sets before calling driver functions (read-only):
`MODEL` `TIER` `TIMEOUT` `ADD_DIRS[]` `YOLO` `SANDBOX` `CONTINUE` `CONV_ID`
`PROMPT` `PRINT_CMD`. Helpers available: `on_wsl`, `on_windows_native`.

The invocation the core runs is:

```
$DRIVER_BIN "${DRIVER_ARGS[@]}" "${DRIVER_PROMPT_ARGS[@]}" < /dev/null
```

wrapped in a wall-clock `timeout` guard when available.

## Adding a new driver (e.g. devin)

1. Copy `drivers/agy.sh` or `drivers/grok.sh` to `drivers/<name>.sh` and map
   the flags. Devin CLI is the same shape (local headless coding CLI: prompt
   in, stdout out): `-p` single-turn, `--continue` / `--resume <id>`,
   `--permission-mode bypass` for yolo, `--sandbox`.
2. Verify the CLI's headless behavior empirically before shipping: exact
   `--model`-style flag, whether stdout survives a non-TTY caller, and what
   its quota / auth / timeout stderr messages look like (for
   `driver_classify_error`).
3. Keep quirk handling in the driver — the core must stay CLI-agnostic.
4. Add stub-based tests in `tests/run-tests.sh` mirroring the agy ones.
