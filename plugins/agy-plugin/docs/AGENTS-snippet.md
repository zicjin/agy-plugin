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
agy-delegate [--tier low|medium|high] [--dir <path>] [--timeout 10m] \
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
