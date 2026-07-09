---
name: grok-research
description: Conductor-orchestrated deep research using grok for grounded web legwork; conductor verifies and synthesizes.
---

You own plan / verification / synthesis. grok does grounded fetches.

Use `<plugin-root>/scripts/grok-delegate.sh`.

1. **Plan (you):** 3–6 sub-questions + load-bearing claims.
2. **Fan-out:** `grok-delegate --tier medium --yolo "Web-search <q>. Return 5–8 bullets with URL + date. ONLY findings."`
3. **Deepen:** `grok-delegate --tier high --yolo "Open <URL> and quote sentences supporting: '<claim>'. Or NOT SUPPORTED."`
4. **Verify (you):** ≥2 independent domains; mark unverified.
5. **Synthesize (you):** cited report from verified findings only.

Ingest digests only. Interactive long fetches: `grok-job`. Headless: sync.
