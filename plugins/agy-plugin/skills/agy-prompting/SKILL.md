---
name: agy-prompting
description: Internal guidance for composing prompts sent to agy (Gemini) delegations.
---

Prompt agy like an **operator, not a collaborator**: compact XML-block prompts.
State the task, output contract, follow-through defaults, and only needed constraints.

- One clear task per delegation.
- Tell agy what **done** looks like.
- Prefer a tighter output contract over a higher tier.
- Use `<compact_output_contract>` (pairs with `--digest`).
- Follow-ups: `agy-delegate --continue` with only the delta instruction.
