<!--
Injected as session context by the plugin's SessionStart hook (Codex and Claude
Code). Can also be pasted into a repo's AGENTS.md / CLAUDE.md directly — the
subagent CLIs read the same AGENTS.md, one shared harness for all the AIs involved.
-->

## Subagent delegation (subvibe)

You (the conductor agent) can delegate work to a **cheaper subagent CLI** — a full
terminal agent (file edits, terminal, web search) — via the `subvibe-delegate`
wrapper (`subvibe-job` for background jobs; these are `scripts/subvibe-delegate.sh`
and `scripts/subvibe-job.sh` in the installed plugin, invoked by path). The default
executor is **Grok Build (`grok`)**; the **Antigravity CLI (`agy`, Gemini)** is
available with `--driver agy` or `SUBVIBE_DRIVER=agy` (`scripts/doctor.sh` health-checks
the agy side). The organizing idea is **intelligent model routing
across the SDLC**: you keep judgement-heavy work (requirements, architecture, the hard
20%, verification, review); route deterministic, high-volume work (scaffolding,
boilerplate, test generation, migrations, bulk reads, web search)
to the cheaper, faster executor.

### How to call it

```bash
subvibe-delegate [--tier low|medium|high] [--dir <path>] [--timeout 10m] \
             [--yolo] [--sandbox] [--digest] "the task prompt"
echo "long prompt" | subvibe-delegate -        # prompt from stdin
ID=$(subvibe-job start --tier high --dir . "big task"); subvibe-job result "$ID"   # background
```

- Tiers are driver-mapped model/effort levels: `medium` (default, bulk) · `low`
  (cheapest, trivial) · `high` (harder reasoning / verification retries). Remap via env
  (`GROK_TIER_*` / `AGY_TIER_*`, `SUBVIBE_DEFAULT_MODEL`) or pass `--model "<exact name>"`
  — keep the executor a _different, cheaper_ model than you.
- **Always pass `--dir <repo-root>` for repo work** so the executor loads AGENTS.md and
  the real code instead of you pasting files into the prompt.
- **Write tasks MUST pass `--yolo`** — without it, a headless executor may only _describe_ edits
  and returns a confident "done" **while writing nothing**. Run writes on a dedicated
  branch, prefer `--sandbox`, and review the diff before merging. Your own sandbox
  may require approval to run the command with network/write access.
- Structured failures: exit `10` quota · `11` auth · `12` timeout · `13` CLI missing
  (plus `2` failed / `3` empty), with an `SUBVIBE_SIGNAL {...}` line on stderr — react to
  the code (e.g. retry quota with `--continue`) instead of scraping prose.
- **Headless (`codex exec` / `claude -p`)?** Delegate **synchronously** — never background a
  delegation expecting a later turn to collect it.

### Cost discipline (where the savings come from)

1. **Delegate above the break-even only** — bulk / parallel / repetitive work
   (migrations, exhaustive tests, fan-out research, long reads that return a small
   digest). Tiny or judgement-heavy tasks are cheaper to do yourself.
2. **Keep your context lean (biggest lever)** — do NOT re-read files the executor already
   handled; ingest a **digest**, never a raw dump. Use `--digest` for any bulk
   read/analysis; the wrapper warns on stderr when a reply comes back dump-sized.
3. **Batch, don't chatter** — one large, fully-specified delegation beats many
   round-trips.
4. **Review the diff, not the whole tree.**
5. **Hold state on the cheap side** — for multi-step jobs keep an executor session with
   `--continue` / `--conversation <id>` and pass deltas.

### Verification gates (non-negotiable)

You own correctness. For anything that ships:

1. Define the contract first (you write/own the tests and evals).
2. Actually **run** the output — reading the diff is not sufficient.
3. Trajectory check — have the executor summarize its own steps in its reply.
4. Review every shipping line — hallucinated deps, error handling, edge cases.
5. **Never trust the executor's "GREEN"** — it may alter the environment to make a check pass;
   re-run gates yourself in a clean state.
   If wrong: retry on `--tier high`, sharpen the spec, or do that piece yourself.

### When to reach for it

Proactively consider delegation when a request looks like bulk work above the
break-even: mass edits/migrations, exhaustive test generation, fan-out web research,
or long-context reads that reduce to a short digest. Code review stays with you —
don't delegate it. It's advisory — the break-even judgment is yours per task.
