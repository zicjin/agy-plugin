<div align="center">

# 🛰️ subvibe — subagent delegation plugin

**Run a cheaper coding CLI (Grok Build, Antigravity/Gemini, …) as a collaborating sub-agent, right inside OpenAI Codex or Claude Code.**

Your agent conducts the judgement; the executor CLI does the heavy lifting — intelligent model routing across the SDLC.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Grok Build](https://img.shields.io/badge/Grok%20Build-grok-000000?logo=x&logoColor=white)](https://x.ai/cli)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity%20CLI-agy-4285F4?logo=googlegemini&logoColor=white)](https://antigravity.google/docs/cli-using)

</div>

Grown out of [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code): a robust, CLI-agnostic delegation wrapper (driver per executor CLI — `grok` by default, `agy`, …), background jobs, and routing/cost discipline — packaged as a dual-platform plugin: an official [Codex plugin](https://developers.openai.com/codex/plugins) **and** a [Claude Code plugin](https://code.claude.com/docs/en/plugins) from the same repo (shared skills, scripts, and a SessionStart policy hook per platform).

## 💡 Why

|              | Codex / Claude (conductor)                                             | subagent CLI (executor)                              |
| ------------ | ---------------------------------------------------------------------- | ---------------------------------------------------- |
| **Owns**     | requirements · architecture · the hard 20% · **verification** · review | scaffold · implementation · test generation · search |
| **Strength** | judgement                                                              | cheap, fast throughput                               |

```
you → Codex / Claude Code (conduct: design / verify / review)
         └── subvibe-delegate → grok / agy / … (execute: implement / test / search)
```

> _Generation is solved; verification, judgement, and direction are the craft._

## ✨ What it does

- **Routes work across the SDLC** — the conductor keeps the judgement calls (including all code review); the executor handles scaffolding, test generation, and migrations under a shared `AGENTS.md`.
- **Adds tools your agent may lack** — live Google/web search, Vertex AI Search over your internal data, deep research. The conductor reviews and re-checks the results.
- **Background jobs** — fire a long delegation with `subvibe-job`, keep working, collect later.
- **Built-in cost discipline** — `--digest` output contracts, dump-size warnings, break-even guidance baked into the skills and the policy snippet.
- **Policy injected automatically** — the plugin's SessionStart hook injects `docs/AGENTS-snippet.md` (routing policy + verification gates) into every session; no per-repo `AGENTS.md` editing. Since the executor CLIs read `AGENTS.md` natively, you can additionally paste the snippet into a repo to share the same harness with them.
- **Pluggable executors** — a driver per subagent CLI ([Grok Build](https://x.ai/cli) is the default, [Antigravity CLI](https://antigravity.google/docs/cli-using) included); switch per call with `--driver` or globally with `SUBVIBE_DRIVER`.

## 🚀 Install

### Codex

```bash
codex plugin marketplace add zicjin/subvibe
```

Then inside Codex run `/plugins`, pick the **subvibe** marketplace, and install **subvibe**.

### Claude Code

```
/plugin marketplace add zicjin/subvibe
/plugin install subvibe@subvibe
```

Both give you:

- **Skills** — `subvibe-delegate`, `subvibe-research`, `subvibe-jobs`, `subvibe-setup` (Codex: type `$` or run `/skills`; Claude Code: picked automatically or via `/skill`; both can also pick them implicitly when a task matches).
- **SessionStart hook** — injects the routing policy + verification gates (`docs/AGENTS-snippet.md`) as session context in every session, so your agent delegates **proactively** without you editing each repo's `AGENTS.md`. Plugin hooks aren't trusted automatically — you review and trust the hook once on install.

The skills call the bundled `scripts/*.sh` by path — no PATH setup needed. Verify with the `subvibe-setup` skill (or run the plugin's `scripts/doctor.sh` directly).

**Prerequisites:** at least one executor CLI installed & authenticated — [Grok Build](https://x.ai/cli) (`grok`, the default; `grok login`) and/or the [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy`; `agy models` lists models) — plus [Codex CLI](https://github.com/openai/codex) or [Claude Code](https://code.claude.com/docs).

**Platform support:** macOS, Linux, and WSL. Native Windows (Git Bash/MSYS) is not recommended — headless `agy -p` can hang without a real console (ConPTY); the wrapper bounds this with a wall-clock guard (GNU `timeout`/`gtimeout`) and the doctor script distinguishes a hang from an auth failure.

**Sandbox note:** in the agent's default sandbox, the executor CLI needs network access, so the delegation command may require approval. Approve it when prompted, or run with a policy that allows it (e.g. Codex `--sandbox danger-full-access` in a trusted environment, or an allow rule for the delegation command).

## 🧩 Skills

| skill | what it does |
| ----- | ------------ |

| `subvibe-setup` | health check — executor CLI installed + authenticated, wiring OK |
| `subvibe-delegate` | delegate a subtask to the executor under cost discipline, then verify |
| `subvibe-research` | conductor-orchestrated deep research — the executor does grounded web legwork, the conductor verifies citations across ≥2 sources |
| `subvibe-jobs` | manage background delegation jobs (list / status / result / cancel) |
| `subvibe-prompting` | internal: how to compose operator-style prompt contracts for the executor (XML blocks, output contracts, `--continue` delta follow-ups) |

Code review is deliberately **not** delegated: it is judgement-heavy work the conductor owns (see [Why](#-why)), and cheap executor models are not the right fit for it.

> Background jobs are for **interactive** sessions (fire-and-collect). In headless one-shot runs (`codex exec` / `claude -p`), delegate **synchronously** — there's no later turn to collect a result.

## 🛠️ Direct script usage & tiers

```bash
# one-shot delegation (plain text on stdout)
subvibe-delegate "Summarize this changelog in 3 bullets: ..."

# give the executor a workspace for multi-file agentic work
subvibe-delegate --tier high --dir ./src "List every TODO with file:line"

# bulk read -> digest-only reply (the biggest cost lever; wrapper warns on dump-sized replies)
subvibe-delegate --digest --dir . "Map the auth flow end to end"

# live web / Google search (tools need --yolo in headless mode)
subvibe-delegate --yolo "Web-search <X>. Give URLs + dates."

# stdin prompt / background job
echo "long prompt" | subvibe-delegate -
ID=$(subvibe-job start --tier high --dir . "big task"); subvibe-job result "$ID"
```

| tier               | grok (default driver)    | agy                       | use for                                 |
| ------------------ | ------------------------ | ------------------------- | --------------------------------------- |
| `low`              | grok-composer-2.5-fast   | Gemini 3.5 Flash (Low)    | cheapest, trivial tasks                 |
| `medium` (default) | grok-4.5 (effort medium) | Gemini 3.5 Flash (Medium) | most bulk work                          |
| `high`             | grok-4.5 (effort high)   | Gemini 3.5 Flash (High)   | harder reasoning / verification retries |

**Any listed model works.** Pass `--model "<exact name>"`, or set it persistently via environment variables — `SUBVIBE_DEFAULT_MODEL`, or per-tier `GROK_TIER_*` / `AGY_TIER_*`. Other knobs: `SUBVIBE_DEFAULT_TIER`, `SUBVIBE_TIMEOUT`, `SUBVIBE_DIGEST_WARN_CHARS`. Keep the executor a _different, cheaper_ model than the conductor — that's what gives the cost saving.

## 🚧 Guardrails & known limits

**Guardrails**

- Always **verify** the executor's output (it can be wrong, and may even alter its environment to make a check pass — re-run gates yourself in a clean state).
- `--yolo` auto-approves every executor tool call — use with `--sandbox` or in a throwaway dir.
- Write tasks: run on a dedicated branch/worktree, review the diff before merging.

**Known limits**

- `-p`/`--print` **takes the prompt as its value** and must come last — the wrapper handles this.
- No `--output-format json` (plain text); `--print` drops stdout on a non-TTY unless stdin is detached (handled via `< /dev/null`).
- **Writes need `--yolo`:** without it, headless agy only _describes_ edits and returns a confident success **without writing any files**. Long write tasks can exceed the shell-tool time limit → use a background job (`subvibe-job`).
- **Native Windows (no ConPTY):** headless `agy -p` / `agy models` can hard-hang with a 0-byte log when stdio is redirected. The wrapper wraps agy in a wall-clock `timeout`/`gtimeout` guard so it returns a structured TIMEOUT (exit 12) instead of hanging. Use WSL/macOS/Linux for headless delegation.
- **WSL:** running agy with `--add-dir` on a Windows mount (`/mnt/c/...`) is very slow (9p bridge). Keep the repo on the WSL Linux filesystem (`~`). The wrapper and `doctor.sh` warn about this.

## 📦 What's inside · tests

```
.codex-plugin/plugin.json        Codex plugin manifest
.agents/plugins/marketplace.json Codex repo marketplace (codex plugin marketplace add zicjin/subvibe)
.claude-plugin/plugin.json       Claude Code plugin manifest
.claude-plugin/marketplace.json  Claude Code marketplace (/plugin marketplace add zicjin/subvibe)
skills/                          shared plugin skills: subvibe-delegate, subvibe-research, subvibe-jobs, subvibe-setup, subvibe-prompting
hooks/hooks.json                 Codex SessionStart hook — injects the delegation policy as session context
hooks/claude-hooks.json          Claude Code SessionStart hook (startup + compact) — same policy injection
scripts/                         subvibe-delegate.sh (CLI-agnostic core) · drivers/ (per-CLI drivers) · subvibe-job.sh · doctor.sh
docs/drivers.md                  the driver interface — how to add another subagent CLI
tests/                           dependency-free tests (stub CLIs); bash tests/run-tests.sh
```

**Tests** (no dependencies; stubs the executor CLIs):

```bash
bash tests/run-tests.sh
```

## How the two platforms share one repo

The core is platform-neutral — pure-bash scripts, open-format `SKILL.md` skills, and a plain-text policy snippet. Each platform gets a thin packaging shell:

|             | Codex                                | Claude Code                                                 |
| ----------- | ------------------------------------ | ----------------------------------------------------------- |
| manifest    | `.codex-plugin/plugin.json`          | `.claude-plugin/plugin.json`                                |
| marketplace | `.agents/plugins/marketplace.json`   | `.claude-plugin/marketplace.json`                           |
| policy hook | `hooks/hooks.json` (SessionStart)    | `hooks/claude-hooks.json` (SessionStart: startup + compact) |
| skills      | `skills/` (shared)                   | `skills/` (shared)                                          |
| scripts     | `scripts/` (shared, invoked by path) | `scripts/` (shared, invoked by path)                        |

Configuration is plain env vars on both platforms: `SUBVIBE_*` for the core (driver, tier, timeout, …) plus per-driver remaps (`GROK_TIER_*`, `AGY_TIER_*`).

## Driver architecture

`scripts/subvibe-delegate.sh` is a CLI-agnostic core; everything specific to one subagent CLI lives in a driver (`scripts/drivers/<name>.sh`). The core owns cost discipline, the hang guard, structured exit codes, and the `SUBVIBE_SIGNAL` failure contract; the driver owns flag mapping, tier→model names, and error classification. Select with `--driver` or `SUBVIBE_DRIVER`. Adding another local headless coding CLI (Devin CLI, …) means writing one driver file: see [docs/drivers.md](docs/drivers.md).

| driver           | executor                                                     | tiers map to                                                                                       | notes                                                                                                                                                                                                                         |
| ---------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `agy`            | [Antigravity CLI](https://antigravity.google/docs/cli-using) | Gemini Flash thinking levels (`AGY_TIER_*` remaps)                                                 | see Known limits above                                                                                                                                                                                                        |
| `grok` (default) | [Grok Build](https://x.ai/cli) (`grok`)                      | low→`grok-composer-2.5-fast`, medium/high→`grok-4.5` + `--reasoning-effort` (`GROK_TIER_*` remaps) | `--dir`→`--cwd` (one dir) · `--yolo`→`--always-approve` · `--sandbox` uses profile `GROK_SANDBOX_PROFILE` (default `readonly`) · unauthenticated headless `grok -p` hangs — the wall-clock guard catches it; run `grok login` |

```bash
SUBVIBE_DRIVER=agy subvibe-delegate --tier high "task"   # or: subvibe-delegate --driver agy ...
```

The built-in default is `grok` — one line in `scripts/subvibe-delegate.sh` (`DRIVER="${SUBVIBE_DRIVER:-grok}"`); override per call with `--driver` or persistently by exporting `SUBVIBE_DRIVER` (e.g. in your shell profile).
