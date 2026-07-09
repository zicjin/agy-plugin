---
name: agy-jobs
description: Manage background agy-plugin delegation jobs (list/status/result/cancel). Interactive sessions only.
---

Manage background jobs with `<plugin-root>/scripts/agy-job.sh` (`agy-job` below).

- **List / status**: `agy-job list` or `agy-job status <id>`
- **Result**: `agy-job result <id>` — verify under Verification gates; ingest digest only
- **Cancel**: `agy-job cancel <id>`

Failed jobs surface structured signals (quota/auth/timeout) — react to the code.
