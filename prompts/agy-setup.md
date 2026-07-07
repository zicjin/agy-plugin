---
description: Verify the Antigravity (agy) CLI is installed and authenticated and agy-plugin-codex is ready to use.
---

Run the plugin's doctor and report status.

Run: `agy-doctor`
(If `agy-doctor` is not on PATH, run `install.sh` from the agy-plugin-codex checkout,
or call `scripts/doctor.sh` there directly.)

Then summarize for the user:
- Is `agy` installed, and can it list models (i.e. authenticated)?
- Are the plugin scripts executable, bin/ on PATH, and the prompts installed?
- What GCP project / region / default model is `agy` configured for?

If anything is missing or failing, give the **exact** command to fix it (install agy,
authenticate, `chmod +x` the scripts, re-run `install.sh`, etc.). Keep it short and
actionable.
