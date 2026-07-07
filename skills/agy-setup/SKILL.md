---
name: agy-setup
description: Verify the Antigravity (agy) CLI is installed and authenticated and the agy-plugin-codex tooling is ready to use. Use when setting up, or when agy delegations fail with auth/missing errors.
---

Run the plugin's doctor and report status.

Run: `<plugin-root>/scripts/doctor.sh` (plugin root = two directories above this
SKILL.md).

Then summarize for the user:
- Is `agy` installed, and can it list models (i.e. authenticated)?
- Are the plugin scripts executable?
- What GCP project / region / default model is `agy` configured for?

If anything is missing or failing, give the **exact** command to fix it (install
agy, authenticate, `chmod +x` the scripts, etc.). Keep it short and actionable.
