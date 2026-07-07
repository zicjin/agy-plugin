---
name: agy-jobs
description: Manage background Antigravity (agy) delegation jobs — list them, check status, fetch a finished job's result, or cancel one. Use in interactive sessions when a long delegation was started with agy-job.
---

Manage background agy delegation jobs with the `agy-job` wrapper (from PATH, or
`<plugin-root>/scripts/agy-job.sh`; plugin root = two directories above this
SKILL.md).

- **List / status**: `agy-job list` for jobs started from this directory, or
  `agy-job status <id>` for one job. Report each job's id, state
  (running / done / failed), and task.
- **Result**: `agy-job result <id>`.
  - If it reports "still running", tell the user and stop.
  - If finished: treat the output as a delegated result under the **Verification
    gates** of the plugin's delegation policy — do NOT trust it blindly. Verify
    (run/inspect) before using, ingest only the digest into your context, and
    report your verification.
- **Cancel**: `agy-job cancel <id>`. Confirm to the user whether it was cancelled
  or had already finished.

Failed jobs surface the delegate's structured signals (quota / auth / timeout) in
their status output — react to the code, e.g. retry a quota failure later.
