---
name: agy-prompting
description: Internal guidance for composing prompts sent to Antigravity (agy / Gemini) delegations — output contracts, follow-through defaults, grounding rules. Use when building the task text for agy-delegate or agy-job.
---

Prompt agy like an **operator, not a collaborator**: compact, block-structured
prompts with XML tags. State the task, the output contract, the follow-through
defaults, and only the constraints that matter.

Core rules:
- One clear task per delegation. Split unrelated asks into separate runs.
- Tell agy what **done** looks like — it will not infer the desired end state.
- Prefer a tighter output contract over a higher tier or longer prose.
- agy has no structured-output mode: enforce shape with a `<compact_output_contract>`
  (exact first line, per-item format, "no preamble / no recap").

Default recipe:
- `<task>`: the concrete job plus the minimum repo/failure context.
- `<compact_output_contract>`: exact shape, ordering, brevity (pairs with `--digest`).
- `<default_follow_through_policy>`: what agy should do by default instead of asking
  routine questions back (headless runs cannot answer them).
- `<verification_loop>`: for write/fix tasks — run the checks, report pass/fail.
- `<grounding_rules>` / `<citation_rules>`: for review or research — claims must be
  defensible from files read or sources fetched; no invented paths/URLs.
- `<action_safety>`: for `--yolo` write tasks — stay narrow, no unrelated refactors.

Follow-ups on the same thread: use `agy-delegate --continue` (or
`--conversation <id>`) and send **only the delta instruction** — do not restate the
whole prompt unless the direction changed materially. This keeps working state on
the cheap (Gemini) side.

Ready-made contract: `docs/adversarial-review-prompt.md` in the plugin root is a
complete adversarial-review prompt — prepend it to a diff on stdin.
