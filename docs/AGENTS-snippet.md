<!--
Paste this section into the AGENTS.md of any repo where Codex should use
Antigravity (agy) as a subagent. Codex reads AGENTS.md automatically, so this
is the Codex equivalent of the Claude Code plugin's skill + SessionStart policy
injection. agy also reads the same AGENTS.md — one shared harness for both AIs.
-->

## Antigravity delegation (agy as subagent)

You (Codex) can delegate work to the **Antigravity CLI (`agy`, Gemini)** — a full
terminal agent (file edits, terminal, subagents, web/Vertex AI Search) — via the
`agy-delegate` wrapper (from agy-plugin-codex; `agy-job` for background jobs,
`agy-doctor` for health checks). The organizing idea is **intelligent model routing
across the SDLC**: you keep judgement-heavy work (requirements, architecture, the hard
20%, verification, review); route deterministic, high-volume work (scaffolding,
boilerplate, test generation, first-pass review, migrations, bulk reads, web search)
to the cheaper, faster executor.

### How to call it

```bash
agy-delegate [--tier flash|flash-lo|pro] [--dir <path>] [--timeout 10m] \
             [--yolo] [--sandbox] [--digest] "the task prompt"
echo "long prompt" | agy-delegate -        # prompt from stdin
ID=$(agy-job start --tier pro --dir . "big task"); agy-job result "$ID"   # background
```

- Tiers: `flash` (default, bulk) · `flash-lo` (cheapest, trivial) · `pro` (harder
  reasoning / reviews / cross-checks). Remap via env `AGY_CODEX_TIER_*`,
  `AGY_CODEX_DEFAULT_MODEL`, or pass `--model "<exact name from agy models>"` — keep
  the executor a *different, cheaper* model than you.
- **Always pass `--dir <repo-root>` for repo work** so agy loads AGENTS.md and the real
  code instead of you pasting files into the prompt.
- **Write tasks MUST pass `--yolo`** — without it, headless agy only *describes* edits
  and returns a confident "done" **while writing nothing**. Run writes on a dedicated
  branch, prefer `--sandbox`, and review the diff before merging. Codex's own sandbox
  may require approval to run the command with network/write access.
- Structured failures: exit `10` quota · `11` auth · `12` timeout · `13` agy missing
  (plus `2` failed / `3` empty), with an `AGY_SIGNAL {...}` line on stderr — react to
  the code (e.g. retry quota with `--continue`) instead of scraping prose.
- **Headless (`codex exec`)?** Delegate **synchronously** — never background a
  delegation expecting a later turn to collect it.

### Cost discipline (where the savings come from)

1. **Delegate above the break-even only** — bulk / parallel / repetitive work
   (migrations, exhaustive tests, fan-out research, long reads that return a small
   digest). Tiny or judgement-heavy tasks are cheaper to do yourself.
2. **Keep your context lean (biggest lever)** — do NOT re-read files agy already
   handled; ingest a **digest**, never a raw dump. Use `--digest` for any bulk
   read/analysis; the wrapper warns on stderr when a reply comes back dump-sized.
3. **Batch, don't chatter** — one large, fully-specified delegation beats many
   round-trips.
4. **Review the diff, not the whole tree.**
5. **Hold state on the cheap side** — for multi-step jobs keep an agy session with
   `--continue` / `--conversation <id>` and pass deltas.

### Verification gates (non-negotiable)

You own correctness. For anything that ships:
1. Define the contract first (you write/own the tests and evals).
2. Actually **run** the output — reading the diff is not sufficient.
3. Trajectory check — have agy summarize its own steps in its reply.
4. Review every shipping line — hallucinated deps, error handling, edge cases.
5. **Never trust agy's "GREEN"** — it may alter the environment to make a check pass;
   re-run gates yourself in a clean state.
If wrong: retry on `--tier pro`, sharpen the spec, or do that piece yourself.

### When to reach for it

Proactively consider delegation when a request looks like bulk work above the
break-even: mass edits/migrations, exhaustive test generation, fan-out web research,
long-context reads that reduce to a short digest, or an independent cross-model review
(`git diff | agy-delegate --tier pro -`). It's advisory — the break-even judgment is
yours per task.
