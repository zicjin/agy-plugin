#!/usr/bin/env python3
"""Generate plugins/agy-plugin and plugins/grok-plugin from root scripts/ templates."""
from __future__ import annotations

import json
import re
import textwrap
from pathlib import Path

root = Path(__file__).resolve().parent.parent

delegate_src = (root / "scripts" / "subvibe-delegate.sh").read_text(encoding="utf-8")
job_src = (root / "scripts" / "subvibe-job.sh").read_text(encoding="utf-8")
agy_driver = (root / "scripts" / "drivers" / "agy.sh").read_text(encoding="utf-8")
grok_driver = (root / "scripts" / "drivers" / "grok.sh").read_text(encoding="utf-8")

VERSION = "0.4.0"


def make_delegate(driver: str, script_name: str) -> str:
    s = delegate_src
    s = s.replace(
        "subvibe-delegate.sh — robust headless delegation wrapper for subagent CLIs.",
        f"{script_name}.sh — headless delegation wrapper for the {driver} executor (subvibe marketplace).",
    )
    s = re.sub(
        r"Purpose:.*?bulk work\.\n",
        (
            f"Purpose: let the conductor agent hand a well-scoped subtask to the\n"
            f"# **{driver}** executor CLI and get clean text back on stdout.\n"
            f"# This plugin is single-driver — the executor is fixed to `{driver}` (no --driver /\n"
            f"# SUBVIBE_DRIVER switch).\n"
        ),
        s,
        count=1,
        flags=re.S,
    )
    s = s.replace(
        "# Architecture: a CLI-agnostic core (this file) + one driver per subagent CLI\n"
        "# (scripts/drivers/<name>.sh). The core owns arg parsing, tier resolution, the\n"
        "# digest contract, the wall-clock hang guard, structured exit codes, and the\n"
        "# machine-readable failure signal. The driver owns flag mapping, tier->model\n"
        "# names, error classification, and CLI-specific quirks. See docs/drivers.md.\n",
        "# Architecture: CLI-agnostic core (this file) + this plugin's driver\n"
        f"# (scripts/drivers/{driver}.sh). Core owns arg parsing, tier resolution, digest\n"
        "# contract, hang guard, structured exit codes, and SUBVIBE_SIGNAL. Driver owns\n"
        "# flag mapping, tier->model, error classification, and CLI quirks.\n",
    )
    s = s.replace("subvibe-delegate.sh", f"{script_name}.sh")
    s = s.replace("subvibe-job.sh", f"{driver}-job.sh")
    s = s.replace(
        "#       --driver <name>              Subagent CLI driver (default: grok; env SUBVIBE_DRIVER)\n",
        "",
    )
    s = s.replace(
        "# Tiers map to driver-specific model names (e.g. agy: Gemini Flash thinking\n"
        "# levels; grok: model + reasoning effort), remappable per tier. Defaults via\n"
        "# env: SUBVIBE_DRIVER, SUBVIBE_DEFAULT_TIER, SUBVIBE_TIMEOUT, SUBVIBE_DEFAULT_MODEL\n"
        "# (exact name). Per-driver tier remaps: GROK_TIER_* / AGY_TIER_*. Explicit\n"
        "# --model/--tier win.\n",
        f"# Tiers map to {driver}-specific model names, remappable per tier. Defaults via\n"
        f"# env: SUBVIBE_DEFAULT_TIER, SUBVIBE_TIMEOUT, SUBVIBE_DEFAULT_MODEL (exact name).\n"
        f"# Per-tier remaps: {'AGY_TIER_*' if driver == 'agy' else 'GROK_TIER_*'}. Explicit --model/--tier win.\n",
    )
    s = s.replace(
        'DRIVER="${SUBVIBE_DRIVER:-grok}"',
        f'DRIVER="{driver}"  # fixed for this plugin; no env override',
    )
    s = s.replace(
        '    -m|--model)     need "$#" "$1"; MODEL="$2"; shift 2 ;;\n'
        '    --driver)       need "$#" "$1"; DRIVER="$2"; shift 2 ;;\n'
        "    --print-command) PRINT_CMD=1; shift ;;          # dry run: show the resolved command\n",
        '    -m|--model)     need "$#" "$1"; MODEL="$2"; shift 2 ;;\n'
        "    --print-command) PRINT_CMD=1; shift ;;          # dry run: show the resolved command\n",
    )
    s = s.replace(
        '[ -f "$DRIVER_FILE" ] || die "unknown driver \'$DRIVER\' (no $DRIVER_FILE; available: $(ls "$HERE/drivers" 2>/dev/null | sed \'s/\\.sh$//\' | tr \'\\n\' \' \'))"',
        '[ -f "$DRIVER_FILE" ] || die "driver file missing: $DRIVER_FILE"',
    )
    s = s.replace("subvibe-delegate:", f"{script_name}:")
    s = s.replace("subvibe-delegate.XXXXXX", f"{script_name}.XXXXXX")
    s = s.replace("# shellcheck source=drivers/agy.sh", f"# shellcheck source=drivers/{driver}.sh")
    return s


def make_job(driver: str) -> str:
    script = f"{driver}-job"
    dele = f"{driver}-delegate"
    env_prefix = driver.upper()
    s = job_src
    s = s.replace("subvibe-job.sh", f"{script}.sh")
    s = s.replace("subvibe-delegate.sh", f"{dele}.sh")
    s = s.replace("subvibe-job:", f"{script}:")
    s = s.replace("subvibe-delegate options", f"{dele} options")
    s = s.replace(
        'DELEGATE="${SUBVIBE_DELEGATE:-$HERE/subvibe-delegate.sh}"\n'
        'REG="${SUBVIBE_JOBS:-$HOME/.subvibe-jobs}"',
        f'DELEGATE="${{{env_prefix}_DELEGATE:-$HERE/{dele}.sh}}"\n'
        f'REG="${{{env_prefix}_JOBS:-$HOME/.{driver}-jobs}}"',
    )
    s = s.replace(
        "# Jobs live under ${SUBVIBE_JOBS:-~/.subvibe-jobs}/<id>/ (out, err, rc, meta).",
        f"# Jobs live under ${{{env_prefix}_JOBS:-~/.{driver}-jobs}}/<id>/ (out, err, rc, meta).",
    )
    return s


def make_doctor_agy() -> str:
    return textwrap.dedent(
        r"""
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
        """
    ).lstrip("\n")


def make_doctor_grok() -> str:
    return textwrap.dedent(
        r"""
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
        """
    ).lstrip("\n")


def fix_driver_comments(text: str, script: str) -> str:
    text = text.replace("agy-delegate.sh", f"{script}.sh")
    text = text.replace("subvibe-delegate.sh", f"{script}.sh")
    text = text.replace("agy-delegate:", f"{script}:")
    text = text.replace("subvibe-delegate:", f"{script}:")
    return text


SKILLS = {
    "delegate": {
        "agy": {
            "name": "agy-delegate",
            "desc": (
                "Delegate a well-scoped subtask to Antigravity (agy / Gemini Flash) as a cheap "
                "subagent, under cost discipline, then verify. Prefer for lower-intelligence bulk "
                "work (scaffold, boilerplate, bulk reads). Use when offloaded volume exceeds "
                "spec + verification overhead."
            ),
            "body": """
Delegate via `agy-delegate` (Antigravity / Gemini), following **Cost discipline**
and **Verification gates** in the plugin policy (`docs/AGENTS-snippet.md` two levels
above this SKILL.md).

Wrapper: `<plugin-root>/scripts/agy-delegate.sh`.

**Routing note:** Gemini Flash models are smaller-parameter than Grok. Prefer
`agy-delegate` for lower-intelligence / high-volume work. If `grok-plugin` is also
installed, route harder reasoning to `grok-delegate` instead.

Do this:
1. Pick a tier (`medium` default; `low` trivial; `high` harder reasoning).
   Add `--dir <repo-root>` for repo work. **Write/tool tasks need `--yolo`**.
2. Run **synchronously** when headless (`codex exec` / `claude -p`):
   `agy-delegate --tier <tier> [--dir .] [--yolo] [--digest] "<task>"`
   Use `--digest` for bulk reads. Compose prompts per `agy-prompting`.
3. Ingest only the **digest** — not raw dumps.
4. Structured failures: exit `10` quota · `11` auth · `12` timeout · `13` CLI missing
   (plus `2`/`3`), with `SUBVIBE_SIGNAL {...}` on stderr.
5. **Verify** the output yourself; never trust self-reported "done".

Long interactive task: `ID=$(agy-job start --tier high --dir . "<task>")` then
`agy-job status/result` (see `agy-jobs`). Headless: always sync.
""",
        },
        "grok": {
            "name": "grok-delegate",
            "desc": (
                "Delegate a well-scoped subtask to Grok Build (grok) as a subagent, under cost "
                "discipline, then verify. Prefer when the task needs stronger reasoning than "
                "Gemini Flash. Use when offloaded volume exceeds spec + verification overhead."
            ),
            "body": """
Delegate via `grok-delegate` (Grok Build), following **Cost discipline**
and **Verification gates** in the plugin policy (`docs/AGENTS-snippet.md` two levels
above this SKILL.md).

Wrapper: `<plugin-root>/scripts/grok-delegate.sh`.

**Routing note:** Prefer `grok-delegate` for higher-intelligence bulk work. If
`agy-plugin` is also installed, prefer `agy-delegate` (Gemini Flash) for cheaper,
lower-intelligence / high-volume tasks.

Do this:
1. Pick a tier (`medium` default; `low` trivial; `high` harder reasoning).
   Add `--dir <repo-root>` for repo work. **Write/tool tasks need `--yolo`**.
2. Run **synchronously** when headless (`codex exec` / `claude -p`):
   `grok-delegate --tier <tier> [--dir .] [--yolo] [--digest] "<task>"`
   Use `--digest` for bulk reads. Compose prompts per `grok-prompting`.
3. Ingest only the **digest** — not raw dumps.
4. Structured failures: exit `10` quota · `11` auth · `12` timeout · `13` CLI missing
   (plus `2`/`3`), with `SUBVIBE_SIGNAL {...}` on stderr.
5. **Verify** the output yourself; never trust self-reported "done".

Long interactive task: `ID=$(grok-job start --tier high --dir . "<task>")` then
`grok-job status/result` (see `grok-jobs`). Headless: always sync.
""",
        },
    },
    "jobs": {
        "agy": {
            "name": "agy-jobs",
            "desc": "Manage background agy-plugin delegation jobs (list/status/result/cancel). Interactive sessions only.",
            "body": """
Manage background jobs with `<plugin-root>/scripts/agy-job.sh` (`agy-job` below).

- **List / status**: `agy-job list` or `agy-job status <id>`
- **Result**: `agy-job result <id>` — verify under Verification gates; ingest digest only
- **Cancel**: `agy-job cancel <id>`

Failed jobs surface structured signals (quota/auth/timeout) — react to the code.
""",
        },
        "grok": {
            "name": "grok-jobs",
            "desc": "Manage background grok-plugin delegation jobs (list/status/result/cancel). Interactive sessions only.",
            "body": """
Manage background jobs with `<plugin-root>/scripts/grok-job.sh` (`grok-job` below).

- **List / status**: `grok-job list` or `grok-job status <id>`
- **Result**: `grok-job result <id>` — verify under Verification gates; ingest digest only
- **Cancel**: `grok-job cancel <id>`

Failed jobs surface structured signals (quota/auth/timeout) — react to the code.
""",
        },
    },
    "prompting": {
        "agy": {
            "name": "agy-prompting",
            "desc": "Internal guidance for composing prompts sent to agy (Gemini) delegations.",
            "body": """
Prompt agy like an **operator, not a collaborator**: compact XML-block prompts.
State the task, output contract, follow-through defaults, and only needed constraints.

- One clear task per delegation.
- Tell agy what **done** looks like.
- Prefer a tighter output contract over a higher tier.
- Use `<compact_output_contract>` (pairs with `--digest`).
- Follow-ups: `agy-delegate --continue` with only the delta instruction.
""",
        },
        "grok": {
            "name": "grok-prompting",
            "desc": "Internal guidance for composing prompts sent to grok (Grok Build) delegations.",
            "body": """
Prompt grok like an **operator, not a collaborator**: compact XML-block prompts.
State the task, output contract, follow-through defaults, and only needed constraints.

- One clear task per delegation.
- Tell grok what **done** looks like.
- Prefer a tighter output contract over a higher tier.
- Use `<compact_output_contract>` (pairs with `--digest`).
- Follow-ups: `grok-delegate --continue` with only the delta instruction.
""",
        },
    },
    "research": {
        "agy": {
            "name": "agy-research",
            "desc": "Conductor-orchestrated deep research using agy for grounded web legwork; conductor verifies and synthesizes.",
            "body": """
You own plan / verification / synthesis. agy does cheap grounded fetches.

Use `<plugin-root>/scripts/agy-delegate.sh`.

1. **Plan (you):** 3–6 sub-questions + load-bearing claims.
2. **Fan-out:** `agy-delegate --tier medium --yolo "Web-search <q>. Return 5–8 bullets with URL + date. ONLY findings."`
3. **Deepen:** `agy-delegate --tier high --yolo "Open <URL> and quote sentences supporting: '<claim>'. Or NOT SUPPORTED."`
4. **Verify (you):** ≥2 independent domains; mark unverified.
5. **Synthesize (you):** cited report from verified findings only.

Ingest digests only. Interactive long fetches: `agy-job`. Headless: sync.
""",
        },
        "grok": {
            "name": "grok-research",
            "desc": "Conductor-orchestrated deep research using grok for grounded web legwork; conductor verifies and synthesizes.",
            "body": """
You own plan / verification / synthesis. grok does grounded fetches.

Use `<plugin-root>/scripts/grok-delegate.sh`.

1. **Plan (you):** 3–6 sub-questions + load-bearing claims.
2. **Fan-out:** `grok-delegate --tier medium --yolo "Web-search <q>. Return 5–8 bullets with URL + date. ONLY findings."`
3. **Deepen:** `grok-delegate --tier high --yolo "Open <URL> and quote sentences supporting: '<claim>'. Or NOT SUPPORTED."`
4. **Verify (you):** ≥2 independent domains; mark unverified.
5. **Synthesize (you):** cited report from verified findings only.

Ingest digests only. Interactive long fetches: `grok-job`. Headless: sync.
""",
        },
    },
    "setup": {
        "agy": {
            "name": "agy-setup",
            "desc": "Verify the Antigravity (agy) CLI and agy-plugin tooling are ready.",
            "body": """
Run `<plugin-root>/scripts/doctor.sh` and report:
- Is `agy` installed and authenticated (`agy models`)?
- Are plugin scripts executable?
- GCP project / remaps (`AGY_TIER_*`, `SUBVIBE_DEFAULT_MODEL`)?

Give exact fix commands. Keep it short.
""",
        },
        "grok": {
            "name": "grok-setup",
            "desc": "Verify Grok Build (grok) and grok-plugin tooling are ready.",
            "body": """
Run `<plugin-root>/scripts/doctor.sh` and report:
- Is `grok` installed and authenticated (`grok login` / `XAI_API_KEY`)?
- Are plugin scripts executable?
- Remaps (`GROK_TIER_*`, `SUBVIBE_DEFAULT_MODEL`)?

Give exact fix commands. Keep it short.
""",
        },
    },
}


def skill_md(meta: dict) -> str:
    return f"---\nname: {meta['name']}\ndescription: {meta['desc']}\n---\n\n{meta['body'].strip()}\n"


AGENTS_AGY = textwrap.dedent(
    """\
    <!--
    Injected as session context by agy-plugin's SessionStart hook (Codex / Claude Code).
    Paste into a repo AGENTS.md if you want the same policy for the executor side.
    -->

    ## Subagent delegation (agy-plugin)

    You can delegate work to the **Antigravity CLI (`agy` / Gemini)** via `agy-delegate`
    (`agy-job` for background jobs; scripts under the installed plugin's `scripts/`,
    invoked by path).

    **Model fit:** Gemini Flash models have a **smaller parameter footprint than Grok**.
    Prefer this plugin for **lower-intelligence / high-volume** work (scaffolding,
    boilerplate, bulk reads, simple migrations, fan-out search). If **grok-plugin** is
    also installed, route harder reasoning, tricky verification retries, and judgement-
    adjacent bulk work to `grok-delegate` instead — you choose per task; there is no
    shared `SUBVIBE_DRIVER` switch.

    You keep judgement-heavy work (requirements, architecture, the hard 20%,
    verification, review).

    ### How to call it

    ```bash
    agy-delegate [--tier low|medium|high] [--dir <path>] [--timeout 10m] \\
                 [--yolo] [--sandbox] [--digest] "the task prompt"
    echo "long prompt" | agy-delegate -
    ID=$(agy-job start --tier high --dir . "big task"); agy-job result "$ID"
    ```

    - Tiers map to Gemini Flash thinking levels (`AGY_TIER_*`, `SUBVIBE_DEFAULT_MODEL`).
    - **Always pass `--dir <repo-root>` for repo work.**
    - **Write tasks MUST pass `--yolo`.**
    - Structured failures: exit `10` quota · `11` auth · `12` timeout · `13` CLI missing
      (plus `2`/`3`), with `SUBVIBE_SIGNAL {...}` on stderr.
    - **Headless?** Delegate **synchronously** — never background expecting a later turn.

    ### Cost discipline

    1. Delegate above the break-even only.
    2. Keep your context lean — ingest digests (`--digest`), never raw dumps.
    3. Batch, don't chatter.
    4. Review the diff, not the whole tree.
    5. Hold state on the cheap side (`--continue` / `--conversation`).

    ### Verification gates

    You own correctness: define contracts, run outputs, trajectory-check, review shipping
    lines, never trust the executor's "GREEN". If wrong: `--tier high`, sharpen the spec,
    or do it yourself.

    ### When to reach for it

    Bulk work above break-even. Code review stays with you.
    """
)

AGENTS_GROK = textwrap.dedent(
    """\
    <!--
    Injected as session context by grok-plugin's SessionStart hook (Codex / Claude Code).
    Paste into a repo AGENTS.md if you want the same policy for the executor side.
    -->

    ## Subagent delegation (grok-plugin)

    You can delegate work to **Grok Build (`grok`)** via `grok-delegate`
    (`grok-job` for background jobs; scripts under the installed plugin's `scripts/`,
    invoked by path).

    **Model fit:** Prefer this plugin for work that needs **stronger reasoning** than
    Gemini Flash. If **agy-plugin** is also installed, prefer `agy-delegate` for
    **lower-intelligence / high-volume** tasks (Flash has a smaller parameter footprint
    and is the cheaper bulk worker) — you choose per task; there is no shared
    `SUBVIBE_DRIVER` switch.

    You keep judgement-heavy work (requirements, architecture, the hard 20%,
    verification, review).

    ### How to call it

    ```bash
    grok-delegate [--tier low|medium|high] [--dir <path>] [--timeout 10m] \\
                  [--yolo] [--sandbox] [--digest] "the task prompt"
    echo "long prompt" | grok-delegate -
    ID=$(grok-job start --tier high --dir . "big task"); grok-job result "$ID"
    ```

    - Tiers map to grok models / reasoning effort (`GROK_TIER_*`, `SUBVIBE_DEFAULT_MODEL`).
    - **Always pass `--dir <repo-root>` for repo work.**
    - **Write tasks MUST pass `--yolo`.**
    - Structured failures: exit `10` quota · `11` auth · `12` timeout · `13` CLI missing
      (plus `2`/`3`), with `SUBVIBE_SIGNAL {...}` on stderr.
    - **Headless?** Delegate **synchronously** — never background expecting a later turn.

    ### Cost discipline

    1. Delegate above the break-even only.
    2. Keep your context lean — ingest digests (`--digest`), never raw dumps.
    3. Batch, don't chatter.
    4. Review the diff, not the whole tree.
    5. Hold state on the cheap side (`--continue` / `--conversation`).

    ### Verification gates

    You own correctness: define contracts, run outputs, trajectory-check, review shipping
    lines, never trust the executor's "GREEN". If wrong: `--tier high`, sharpen the spec,
    or do it yourself.

    ### When to reach for it

    Bulk work above break-even that benefits from stronger reasoning. Code review stays with you.
    """
)


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")
    if path.suffix == ".sh":
        try:
            path.chmod(path.stat().st_mode | 0o111)
        except OSError:
            pass


def write_plugin(driver: str) -> None:
    name = f"{driver}-plugin"
    base = root / "plugins" / name
    script = f"{driver}-delegate"
    job = f"{driver}-job"

    write_text(base / "scripts" / f"{script}.sh", make_delegate(driver, script))
    write_text(base / "scripts" / f"{job}.sh", make_job(driver))
    write_text(
        base / "scripts" / "doctor.sh",
        make_doctor_agy() if driver == "agy" else make_doctor_grok(),
    )
    drv = agy_driver if driver == "agy" else grok_driver
    write_text(base / "scripts" / "drivers" / f"{driver}.sh", fix_driver_comments(drv, script))

    for _key, variants in SKILLS.items():
        meta = variants[driver]
        write_text(base / "skills" / meta["name"] / "SKILL.md", skill_md(meta))

    write_text(
        base / "docs" / "AGENTS-snippet.md",
        AGENTS_AGY if driver == "agy" else AGENTS_GROK,
    )

    if driver == "agy":
        status = "Loading agy-plugin (Gemini) delegation policy"
        short = "agy (Gemini) as a cheap subagent for lower-intelligence bulk work"
        longd = (
            "Routes high-volume work to Antigravity/Gemini Flash via a hardened wrapper "
            "with tiers, background jobs, structured failure codes, digest guards, and "
            "verification gates. Prefer for lower-intelligence bulk work; install "
            "grok-plugin for stronger reasoning."
        )
        kw = ["agy", "antigravity", "gemini", "subagent", "delegation"]
        default_prompts = [
            "Use agy-delegate to scaffold boilerplate for this module.",
            "Use agy-research for a cheap multi-source web legwork pass.",
        ]
    else:
        status = "Loading grok-plugin (Grok Build) delegation policy"
        short = "grok as a subagent for higher-intelligence bulk work"
        longd = (
            "Routes high-volume work to Grok Build via a hardened wrapper with tiers, "
            "background jobs, structured failure codes, digest guards, and verification "
            "gates. Prefer when the task needs stronger reasoning than Gemini Flash; "
            "install agy-plugin for cheaper lower-intelligence bulk work."
        )
        kw = ["grok", "xai", "subagent", "delegation"]
        default_prompts = [
            "Use grok-delegate to generate exhaustive unit tests for this module.",
            "Use grok-research to run a cited multi-source research pass on this topic.",
        ]

    write_text(
        base / "hooks" / "hooks.json",
        json.dumps(
            {
                "hooks": {
                    "SessionStart": [
                        {
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": 'cat "${PLUGIN_ROOT}/docs/AGENTS-snippet.md"',
                                    "statusMessage": status,
                                }
                            ]
                        }
                    ]
                }
            },
            indent=2,
        )
        + "\n",
    )
    write_text(
        base / "hooks" / "claude-hooks.json",
        json.dumps(
            {
                "hooks": {
                    "SessionStart": [
                        {
                            "matcher": "startup",
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": 'cat "${CLAUDE_PLUGIN_ROOT}/docs/AGENTS-snippet.md"',
                                }
                            ],
                        },
                        {
                            "matcher": "compact",
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": 'cat "${CLAUDE_PLUGIN_ROOT}/docs/AGENTS-snippet.md"',
                                }
                            ],
                        },
                    ]
                }
            },
            indent=2,
        )
        + "\n",
    )

    codex = {
        "name": name,
        "version": VERSION,
        "description": longd,
        "author": {"name": "zicjin", "url": "https://github.com/zicjin"},
        "homepage": "https://github.com/zicjin/subvibe",
        "repository": "https://github.com/zicjin/subvibe",
        "license": "MIT",
        "keywords": kw,
        "skills": "./skills/",
        "hooks": "./hooks/hooks.json",
        "interface": {
            "displayName": f"{name} — {short}",
            "shortDescription": short,
            "longDescription": longd,
            "developerName": "zicjin",
            "category": "Productivity",
            "capabilities": ["Read", "Write"],
            "websiteURL": "https://github.com/zicjin/subvibe",
            "defaultPrompt": default_prompts,
        },
    }
    write_text(base / ".codex-plugin" / "plugin.json", json.dumps(codex, indent=2, ensure_ascii=False) + "\n")

    claude = {
        "name": name,
        "version": VERSION,
        "description": longd,
        "author": {"name": "zicjin", "url": "https://github.com/zicjin"},
        "homepage": "https://github.com/zicjin/subvibe",
        "repository": "https://github.com/zicjin/subvibe",
        "license": "MIT",
        "keywords": kw,
        "hooks": "./hooks/claude-hooks.json",
    }
    write_text(base / ".claude-plugin" / "plugin.json", json.dumps(claude, indent=2, ensure_ascii=False) + "\n")


def main() -> None:
    write_plugin("agy")
    write_plugin("grok")
    print("generated plugins/agy-plugin and plugins/grok-plugin")


if __name__ == "__main__":
    main()
