---
name: grok-delegate
description: Delegate a well-scoped subtask to Grok Build (grok) as a subagent, under cost discipline, then verify. Prefer when the task needs stronger reasoning than Gemini Flash. Use when offloaded volume exceeds spec + verification overhead.
---

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
