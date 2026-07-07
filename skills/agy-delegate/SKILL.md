---
name: agy-delegate
description: Delegate a well-scoped subtask (scaffolding, test generation, migrations, bulk reads, boilerplate) to the Antigravity CLI (agy / Gemini) as a cheap subagent, under cost discipline, then verify the result. Use when the offloaded volume clearly exceeds the spec + verification overhead.
---

Delegate the task to Antigravity (`agy` / Gemini) via the `agy-delegate` wrapper,
following the **Cost discipline** and **Verification gates** in the plugin's
delegation policy (injected at session start; also at `docs/AGENTS-snippet.md` in
the plugin root, two directories above this SKILL.md).

The wrapper lives at `<plugin-root>/scripts/agy-delegate.sh` (plugin root = two
directories above this SKILL.md; `agy-delegate` below means that script).

Do this:
1. Pick a thinking level (`medium` default; `low` for trivial; `high` for harder reasoning).
   If the task needs the repo, add `--dir <repo-root>` so agy reads the real files
   (don't paste them into context).
   **If the task WRITES files or uses tools** (implement / scaffold / test-gen /
   migrate / fix, or web / Vertex AI Search) **add `--yolo`** — without it, agy only
   *describes* the edits and returns a confident "done" **while writing nothing**.
   Run write tasks on a dedicated branch (+ `--sandbox`). Codex's sandbox may block
   the command — if the shell call is denied, request approval / escalated
   permissions for `agy-delegate`.
2. Run **synchronously** (you may be headless `codex exec` — do not
   background-and-wait):
   `agy-delegate --tier <tier> [--dir .] [--yolo] [--digest] "<task>"`
   For read/analysis tasks, add `--digest` — it appends a digest-only output
   contract so agy returns compact bullets instead of raw content.
   Compose the task text per the `agy-prompting` skill: operator-style,
   XML-block prompt with an explicit output contract and follow-through defaults.
   For a follow-up on the same thread, use `--continue` and send only the delta
   instruction — don't restate the whole prompt.
3. Ingest only the **result/digest** — do NOT re-read the files agy already handled
   (keeps your context lean; that's where the cost savings come from). If the
   wrapper prints a *"looks like a raw dump"* note on stderr, do NOT ingest the raw
   output — re-run with `--digest` or ask agy to summarize it first.
4. Structured failures: exit `10` quota · `11` auth · `12` timeout · `13` agy
   missing (plus `2` failed / `3` empty), with an `AGY_SIGNAL {...}` line on
   stderr — react to the code instead of scraping prose.
5. **Verify**: actually run/check the output; never trust a self-reported "done".
   Report what you delegated and how you verified it. If the agy run failed or
   returned nothing, report the failure (with the most actionable stderr lines) —
   don't silently substitute your own answer for the delegated one; tell the user
   before doing the work yourself.

Remember the break-even: only delegate if the offloaded volume clearly exceeds the
spec + round-trip + verification overhead. Tiny tasks are cheaper to just do
yourself.

**Long task, interactive session?** A long sync delegation can hit the shell-tool
time limit — start it in the background and keep working:
`ID=$(agy-job start --tier high --dir . "<task>")`
then check with `agy-job status "$ID"` and collect with `agy-job result "$ID"`
(see the `agy-jobs` skill). Don't do this when YOU are headless `codex exec` —
one-shot, no later turn to collect; delegate synchronously there.
