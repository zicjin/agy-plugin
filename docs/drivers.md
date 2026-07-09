# Subagent CLI drivers (plugin packaging)

This repo is a **marketplace** (`subvibe`) that ships **two installable plugins**:

| plugin | executor | install (Claude) | install (Codex) |
| --- | --- | --- | --- |
| `agy-plugin` | Antigravity CLI (`agy` / Gemini Flash) | `/plugin install agy-plugin@subvibe` | install **agy-plugin** from the subvibe marketplace |
| `grok-plugin` | Grok Build (`grok`) | `/plugin install grok-plugin@subvibe` | install **grok-plugin** from the subvibe marketplace |

Each plugin is **single-driver**: the executor is fixed at package time. There is **no**
`SUBVIBE_DRIVER` env var and **no** `--driver` flag. Users pick a driver by installing
the matching plugin. If both plugins are installed, the **conductor agent** routes per
task (see each plugin's `docs/AGENTS-snippet.md`).

## Layout

```
plugins/
  agy-plugin/          # self-contained install unit
    scripts/
      agy-delegate.sh  # core + DRIVER=agy
      agy-job.sh
      doctor.sh
      drivers/agy.sh
    skills/ hooks/ docs/
  grok-plugin/         # self-contained install unit
    scripts/
      grok-delegate.sh # core + DRIVER=grok
      ...
scripts/               # source templates for the generator (not installed)
  subvibe-delegate.sh
  subvibe-job.sh
  drivers/{agy,grok}.sh
  _gen_plugins.py      # regenerates plugins/* from templates
```

Regenerate after editing templates:

```bash
python scripts/_gen_plugins.py
```

## Core vs driver (inside each plugin)

| Layer | Owns |
| --- | --- |
| core (`*-delegate.sh`) | arg parsing · tier resolution · `--digest` · hang guard · digest-size guard · structured exit codes · `SUBVIBE_SIGNAL` |
| driver (`drivers/<name>.sh`) | binary name · tier → model names · flag mapping · stderr classification · CLI quirks |

The background-job layer (`*-job.sh`) sits on the core and is driver-agnostic except for
which delegate binary it launches.

## Driver interface

A driver is a bash file **sourced** by the core. It must define:

| Symbol | Contract |
| --- | --- |
| `DRIVER_BIN` | binary name on PATH (missing → exit 13 + `CLI_MISSING`) |
| `DRIVER_INSTALL_HINT` | one-line install hint |
| `driver_model_for_tier <low\|medium\|high>` | echo model name; return 1 if unknown |
| `driver_build_args` | fill `DRIVER_ARGS` + `DRIVER_PROMPT_ARGS` |
| `driver_classify_error <stderr>` | `QUOTA_EXHAUSTED` \| `AUTH_REQUIRED` \| `TIMEOUT` \| empty |
| `driver_auth_hint` | re-auth one-liner |
| `driver_prompt_notes` | advisory stderr (never fail) |
| `driver_no_guard_warning` | warning when no wall-clock guard |
| `driver_hang_hint` | extra hint after hang-guard kill |

Normalized inputs (read-only): `MODEL` `TIER` `TIMEOUT` `ADD_DIRS[]` `YOLO`
`SANDBOX` `CONTINUE` `CONV_ID` `PROMPT` `PRINT_CMD`. Helpers: `on_wsl`,
`on_windows_native`.

## Adding another executor

1. Add `scripts/drivers/<name>.sh` and a new `plugins/<name>-plugin/` (or extend
   `_gen_plugins.py`).
2. Register it in both marketplace files.
3. Keep the plugin self-contained — installs copy only the plugin directory.
