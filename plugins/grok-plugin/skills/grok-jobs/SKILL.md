---
name: grok-jobs
description: Manage background grok-plugin delegation jobs (list/status/result/cancel). Interactive sessions only.
---

Manage background jobs with `<plugin-root>/scripts/grok-job.sh` (`grok-job` below).

- **List / status**: `grok-job list` or `grok-job status <id>`
- **Result**: `grok-job result <id>` — verify under Verification gates; ingest digest only
- **Cancel**: `grok-job cancel <id>`

Failed jobs surface structured signals (quota/auth/timeout) — react to the code.
