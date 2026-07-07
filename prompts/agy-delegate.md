---
description: Delegate a well-scoped subtask to Antigravity (agy/Gemini) under cost discipline, then verify.
argument-hint: "[--tier flash|pro] <task>"
---

Delegate the following task to Antigravity (`agy` / Gemini) via the `agy-delegate`
wrapper, following the **Cost discipline** and **Verification gates** in this repo's
AGENTS.md antigravity section (or `docs/AGENTS-snippet.md` of agy-plugin-codex).

Task: $ARGUMENTS

Do this:
1. Pick a tier (`flash` default; `pro` for hard reasoning). If the task needs the repo,
   add `--dir <repo-root>` so agy reads the real files (don't paste them into context).
   **If the task WRITES files or uses tools** (implement / scaffold / test-gen / migrate /
   fix, or web / Vertex AI Search) **add `--yolo`** — without it, agy only *describes* the
   edits and returns a confident "done" **while writing nothing**. Run write tasks on a
   dedicated branch (+ `--sandbox`). Note: Codex's sandbox may block the command — if the
   shell call is denied, request approval / escalated permissions for `agy-delegate`.
2. Run **synchronously** (you may be headless `codex exec` — do not background-and-wait):
   `agy-delegate --tier <tier> [--dir .] [--yolo] [--digest] "<task>"`
   For read/analysis tasks, add `--digest` — it appends a digest-only output contract so
   agy returns compact bullets instead of raw content.
3. Ingest only the **result/digest** — do NOT re-read the files agy already handled
   (keeps your context lean; that's where the cost savings come from). If the wrapper
   prints a *"looks like a raw dump"* note on stderr, do NOT ingest the raw output —
   re-run with `--digest` or ask agy to summarize it first.
4. **Verify**: actually run/check the output; never trust a self-reported "done".
   Report what you delegated and how you verified it.

Remember the break-even: only delegate if the offloaded volume clearly exceeds the
spec + round-trip + verification overhead. Tiny tasks are cheaper to just do yourself.

**Long task, interactive session?** A long sync delegation can hit the shell-tool time
limit — start it in the background and keep working:
`ID=$(agy-job start --tier pro --dir . "<task>")`
then check `/agy-status` and collect with `/agy-result <id>`.
(Don't do this when YOU are headless `codex exec` — one-shot, no later turn to collect;
delegate synchronously there.)
