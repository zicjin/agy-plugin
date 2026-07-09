---
name: agy-research
description: Conductor-orchestrated deep research using agy for grounded web legwork; conductor verifies and synthesizes.
---

You own plan / verification / synthesis. agy does cheap grounded fetches.

Use `<plugin-root>/scripts/agy-delegate.sh`.

1. **Plan (you):** 3–6 sub-questions + load-bearing claims.
2. **Fan-out:** `agy-delegate --tier medium --yolo "Web-search <q>. Return 5–8 bullets with URL + date. ONLY findings."`
3. **Deepen:** `agy-delegate --tier high --yolo "Open <URL> and quote sentences supporting: '<claim>'. Or NOT SUPPORTED."`
4. **Verify (you):** ≥2 independent domains; mark unverified.
5. **Synthesize (you):** cited report from verified findings only.

Ingest digests only. Interactive long fetches: `agy-job`. Headless: sync.
