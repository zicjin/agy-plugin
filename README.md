<div align="center">

# 🛰️ subvibe — subagent delegation marketplace

**Run a cheaper coding CLI (Grok Build or Antigravity/Gemini) as a collaborating sub-agent, right inside OpenAI Codex or Claude Code.**

Your agent conducts the judgement; the executor CLI does the heavy lifting — intelligent model routing across the SDLC.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Grok Build](https://img.shields.io/badge/Grok%20Build-grok-plugin-000000?logo=x&logoColor=white)](https://x.ai/cli)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity%20CLI-agy--plugin-4285F4?logo=googlegemini&logoColor=white)](https://antigravity.google/docs/cli-using)

</div>

Grown out of [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code): a robust delegation wrapper, background jobs, and routing/cost discipline — packaged as a **marketplace** with **two plugins** (pick your executor at install time) for both [Codex](https://developers.openai.com/codex/plugins) and [Claude Code](https://code.claude.com/docs/en/plugins).

## 💡 Why

|              | Codex / Claude (conductor)                                             | subagent CLI (executor)                              |
| ------------ | ---------------------------------------------------------------------- | ---------------------------------------------------- |
| **Owns**     | requirements · architecture · the hard 20% · **verification** · review | scaffold · implementation · test generation · search |
| **Strength** | judgement                                                              | cheap, fast throughput                               |

```
you → Codex / Claude Code (conduct: design / verify / review)
         ├── agy-plugin  → agy  (Gemini Flash — lower-intelligence / high-volume)
         └── grok-plugin → grok (Grok Build — stronger reasoning bulk work)
```

> _Generation is solved; verification, judgement, and direction are the craft._

## ✨ What it does

- **Two plugins, one marketplace** — install only the executor you use, or both and let the conductor route.
- **Routes work across the SDLC** — the conductor keeps the judgement calls (including all code review); the executor handles scaffolding, test generation, and migrations.
- **Background jobs** — fire a long delegation with `agy-job` / `grok-job`, keep working, collect later.
- **Built-in cost discipline** — `--digest` output contracts, dump-size warnings, break-even guidance.
- **Policy injected automatically** — each plugin's SessionStart hook injects its `docs/AGENTS-snippet.md` (routing policy + verification gates).

### Which plugin?

| plugin | executor | best for |
| ------ | -------- | -------- |
| **agy-plugin** | [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy` / Gemini Flash) | **Lower-intelligence / high-volume** work — Flash has a **smaller parameter footprint** than Grok (cheaper bulk: scaffold, boilerplate, bulk reads, simple migrations, fan-out search) |
| **grok-plugin** | [Grok Build](https://x.ai/cli) (`grok`) | **Stronger-reasoning** bulk work — tests that need harder synthesis, trickier migrations, verification retries |

If both are installed there is **no** `SUBVIBE_DRIVER` switch — the **agent chooses** which skill/wrapper to call per task.

## 🚀 Install

### 1. Add the marketplace

**Codex**

```bash
codex plugin marketplace add zicjin/subvibe
```

Then inside Codex run `/plugins`, pick the **subvibe** marketplace.

**Claude Code**

```
/plugin marketplace add zicjin/subvibe
```

### 2. Install one or both plugins

**Codex** — from the subvibe marketplace install **agy-plugin** and/or **grok-plugin**.

**Claude Code**

```
/plugin install agy-plugin@subvibe
/plugin install grok-plugin@subvibe
```

Each plugin gives you:

- **Skills** — e.g. `agy-delegate` / `grok-delegate`, research, jobs, setup, prompting
- **SessionStart hook** — injects that plugin's routing policy
- **Scripts** — `scripts/*-delegate.sh`, `*-job.sh`, `doctor.sh` (invoked by path; no PATH setup)

**Prerequisites:** the matching executor CLI authenticated — `agy` and/or `grok` — plus [Codex CLI](https://github.com/openai/codex) or [Claude Code](https://code.claude.com/docs).

**Platform support:** macOS, Linux, and WSL. Native Windows is not recommended for headless executor CLIs (ConPTY / unauth hangs); wrappers use a wall-clock `timeout`/`gtimeout` guard.

## 🧩 Skills

| skill (agy-plugin) | skill (grok-plugin) | what it does |
| ------------------ | ------------------- | ------------ |
| `agy-setup` | `grok-setup` | health check for that executor |
| `agy-delegate` | `grok-delegate` | delegate a subtask under cost discipline, then verify |
| `agy-research` | `grok-research` | conductor-orchestrated deep research |
| `agy-jobs` | `grok-jobs` | background jobs (list / status / result / cancel) |
| `agy-prompting` | `grok-prompting` | internal prompt-contract guidance |

Code review is **not** delegated.

> Background jobs are for **interactive** sessions. In headless one-shot runs, delegate **synchronously**.

## 🛠️ Direct script usage & tiers

```bash
# agy-plugin
agy-delegate --tier medium --dir . --digest "Map the auth flow"
ID=$(agy-job start --tier high --dir . "big task"); agy-job result "$ID"

# grok-plugin
grok-delegate --tier high --dir . --yolo "Implement the parser module"
```

| tier | grok-plugin | agy-plugin | use for |
| ---- | ----------- | ---------- | ------- |
| `low` | grok-composer-2.5-fast | Gemini 3.5 Flash (Low) | cheapest, trivial |
| `medium` (default) | grok-4.5 (effort medium) | Gemini 3.5 Flash (Medium) | most bulk work |
| `high` | grok-4.5 (effort high) | Gemini 3.5 Flash (High) | harder reasoning / retries |

Remap with `GROK_TIER_*` / `AGY_TIER_*`, or `SUBVIBE_DEFAULT_MODEL` / `--model`. Other knobs: `SUBVIBE_DEFAULT_TIER`, `SUBVIBE_TIMEOUT`, `SUBVIBE_DIGEST_WARN_CHARS`.

## 🚧 Guardrails & known limits

**Guardrails**

- Always **verify** the executor's output.
- `--yolo` auto-approves tool calls — use with `--sandbox` or a throwaway dir.
- Write tasks: dedicated branch/worktree; review the diff.

**Known limits**

- Writes need `--yolo` (headless executors may only describe edits otherwise).
- Native Windows: headless `agy` / unauthenticated `grok` can hang — wall-clock guard returns TIMEOUT (12). Prefer WSL/macOS/Linux.
- WSL: agy `--add-dir` on `/mnt/c/...` is slow (9p); keep repos on the Linux FS.

## 📦 What's inside · tests

```
.agents/plugins/marketplace.json   Codex marketplace (agy-plugin + grok-plugin)
.claude-plugin/marketplace.json    Claude Code marketplace (same two plugins)
plugins/agy-plugin/                installable unit: Antigravity/Gemini
plugins/grok-plugin/               installable unit: Grok Build
scripts/                           core templates + _gen_plugins.py (dev only)
docs/drivers.md                    packaging + how to add another executor
tests/                             bash tests/run-tests.sh
```

```bash
bash tests/run-tests.sh
# after editing scripts/ templates:
python scripts/_gen_plugins.py
```

## How the two platforms share one repo

|             | Codex | Claude Code |
| ----------- | ----- | ----------- |
| marketplace | `.agents/plugins/marketplace.json` | `.claude-plugin/marketplace.json` |
| each plugin | `plugins/*/.codex-plugin/plugin.json` + `hooks/hooks.json` | `plugins/*/.claude-plugin/plugin.json` + `hooks/claude-hooks.json` |
| skills/scripts | per-plugin, self-contained | per-plugin, self-contained |
