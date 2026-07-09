---
name: agy-delegate
description: Delegate a well-scoped subtask to Antigravity (agy / Gemini Flash) as a cheap subagent, under cost discipline, then verify. Prefer for lower-intelligence bulk work (scaffold, boilerplate, bulk reads). Use when offloaded volume exceeds spec + verification overhead.
---

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
