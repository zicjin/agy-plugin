---
name: agy-review
description: Get an independent cross-model review of the current diff from Antigravity (agy / Gemini), then reconcile the findings as the final judge. Use for a second-opinion or adversarial code review before merging.
---

Use Antigravity (`agy` / Gemini) as an **independent, different-model reviewer** of
the current changes, then reconcile the findings yourself (you are the final judge).

Use the wrapper at `<plugin-root>/scripts/agy-delegate.sh` (plugin
root = two directories above this SKILL.md).

**This skill is review-only.** Do not fix issues or apply patches as part of it.
After presenting the reconciled findings, STOP and ask the user which findings, if
any, they want fixed — even when a fix looks obvious.

Do this:
1. Capture the diff: `git diff` (or the range/paths the user scoped; default to
   uncommitted + last commit if unspecified; `git diff <base>...HEAD` for branch
   review).
2. **Size it** with `git diff --shortstat` (count untracked files too). Clearly tiny
   (~1–2 files) → review synchronously. Bigger or unclear, in an interactive
   session → run it as a background job and keep working (redirect the diff from a
   file, not a pipe — the job detaches):
   `git diff > /tmp/review.diff && ID=$(agy-job start --tier high - < /tmp/review.diff)`
   then collect via `agy-job result "$ID"`. Headless `codex exec` → always
   synchronous.
3. Delegate the review to agy (high tier) — pipe the diff in on stdin:
   - Normal review: `git diff | agy-delegate --tier high -` with an instruction to
     find correctness/security/performance bugs, be skeptical, and list each as
     `file:line — issue`, most severe first.
   - **Adversarial review** (user asked to challenge the approach, or wants a
     pre-ship pressure test): prepend the ready-made contract —
     `cat "<plugin-root>/docs/adversarial-review-prompt.md" <(git diff) | agy-delegate --tier pro -`
     It makes agy attack design choices, tradeoffs, and failure modes (auth, data
     loss, rollback, races, empty-state) and return a `VERDICT:` line plus
     severity-ordered findings with confidence scores. Append any user focus area
     inside the `<task>` block.
4. **Reconcile**: corroborate each finding against the actual code. Drop false
   positives; keep what's real; preserve agy's severity ordering and its stated
   confidence/inference caveats. Agreement across two model families is a stronger
   signal; disagreement is a prompt to look closer.
5. Report the reconciled findings (most severe first) and your verdict. If there
   are no real findings, say so explicitly with a brief residual-risk note. If the
   agy run failed (nonzero exit / AGY_SIGNAL), report the failure — do not
   substitute your own single-model review for the cross-model one without saying
   so.
