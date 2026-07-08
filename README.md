<div align="center">

# 🛰️ Antigravity delegation plugin (`agy-plugin`)

**Run the Antigravity CLI (Gemini) as a collaborating sub-agent, right inside OpenAI Codex or Claude Code.**

Your agent conducts the judgement; Antigravity does the heavy lifting — intelligent model routing across the SDLC.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity%20CLI-agy-4285F4?logo=googlegemini&logoColor=white)](https://antigravity.google/docs/cli-using)

</div>

Grown out of [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code): the robust `agy` delegation wrapper, background jobs, and routing/cost discipline — packaged as a dual-platform plugin: an official [Codex plugin](https://developers.openai.com/codex/plugins) **and** a [Claude Code plugin](https://code.claude.com/docs/en/plugins) from the same repo (shared skills, scripts, and a SessionStart policy hook per platform).

## 💡 Why

| | Codex / Claude (conductor) | `agy` (executor) |
|---|---|---|
| **Owns** | requirements · architecture · the hard 20% · **verification** · review | scaffold · implementation · test generation · search |
| **Strength** | judgement | cheap, fast throughput |

```
you → Codex / Claude Code (conduct: design / verify / review)
         └── agy → Gemini (execute: implement / test / search)
```

> *Generation is solved; verification, judgement, and direction are the craft.*

## ✨ What it does

- **Routes work across the SDLC** — the conductor keeps the judgement calls (including all code review); Antigravity handles scaffolding, test generation, and migrations under a shared `AGENTS.md`.
- **Adds tools your agent may lack** — live Google/web search, Vertex AI Search over your internal data, deep research. The conductor reviews and re-checks the results.
- **Background jobs** — fire a long delegation with `agy-job`, keep working, collect later.
- **Built-in cost discipline** — `--digest` output contracts, dump-size warnings, break-even guidance baked into the skills and the policy snippet.
- **Policy injected automatically** — the plugin's SessionStart hook injects `docs/AGENTS-snippet.md` (routing policy + verification gates) into every session; no per-repo `AGENTS.md` editing. Since `agy` reads `AGENTS.md` natively, you can additionally paste the snippet into a repo to share the same harness with agy itself.

## 🚀 Install

### Codex

```bash
codex plugin marketplace add zicjin/agy-plugin
```

Then inside Codex run `/plugins`, pick the **Antigravity (agy) delegation** marketplace, and install **agy-plugin**.

### Claude Code

```
/plugin marketplace add zicjin/agy-plugin
/plugin install agy-plugin@agy-plugin
```

Both give you:

- **Skills** — `agy-delegate`, `agy-research`, `agy-jobs`, `agy-setup` (Codex: type `$` or run `/skills`; Claude Code: picked automatically or via `/skill`; both can also pick them implicitly when a task matches).
- **SessionStart hook** — injects the routing policy + verification gates (`docs/AGENTS-snippet.md`) as session context in every session, so your agent delegates **proactively** without you editing each repo's `AGENTS.md`. Plugin hooks aren't trusted automatically — you review and trust the hook once on install.

The skills call the bundled `scripts/*.sh` by path — no PATH setup needed. Verify with the `agy-setup` skill (or run the plugin's `scripts/doctor.sh` directly).

**Prerequisites:** the [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy`) installed & authenticated (`agy models` lists models), and [Codex CLI](https://github.com/openai/codex) or [Claude Code](https://code.claude.com/docs).

**Platform support:** macOS, Linux, and WSL. Native Windows (Git Bash/MSYS) is not recommended — headless `agy -p` can hang without a real console (ConPTY); the wrapper bounds this with a wall-clock guard (GNU `timeout`/`gtimeout`) and the doctor script distinguishes a hang from an auth failure.

**Sandbox note:** in the agent's default sandbox, `agy` needs network access, so the delegation command may require approval. Approve it when prompted, or run with a policy that allows it (e.g. Codex `--sandbox danger-full-access` in a trusted environment, or an allow rule for the delegation command).

## 🧩 Skills

| skill | what it does |
|---|---|
| `agy-setup` | health check — `agy` installed + authenticated, wiring OK |
| `agy-delegate` | delegate a subtask to agy under cost discipline, then verify |
| `agy-research` | conductor-orchestrated deep research — agy does grounded web legwork, the conductor verifies citations across ≥2 sources |
| `agy-jobs` | manage background delegation jobs (list / status / result / cancel) |
| `agy-prompting` | internal: how to compose operator-style prompt contracts for agy (XML blocks, output contracts, `--continue` delta follow-ups) |

Code review is deliberately **not** delegated: it is judgement-heavy work the conductor owns (see [Why](#-why)), and Gemini Flash is not the right model for it.

> Background jobs are for **interactive** sessions (fire-and-collect). In headless one-shot runs (`codex exec` / `claude -p`), delegate **synchronously** — there's no later turn to collect a result.

## 🛠️ Direct script usage & tiers

```bash
# one-shot delegation (plain text on stdout)
agy-delegate "Summarize this changelog in 3 bullets: ..."

# give Antigravity a workspace for multi-file agentic work
agy-delegate --tier high --dir ./src "List every TODO with file:line"

# bulk read -> digest-only reply (the biggest cost lever; wrapper warns on dump-sized replies)
agy-delegate --digest --dir . "Map the auth flow end to end"

# live web / Google search (tools need --yolo in headless mode)
agy-delegate --yolo "Web-search <X>. Give URLs + dates."

# stdin prompt / background job
echo "long prompt" | agy-delegate -
ID=$(agy-job start --tier high --dir . "big task"); agy-job result "$ID"
```

| tier | model | use for |
|------|-------|---------|
| `low` | Gemini 3.5 Flash (Low) | cheapest, trivial tasks |
| `medium` (default) | Gemini 3.5 Flash (Medium) | most bulk work |
| `high` | Gemini 3.5 Flash (High) | harder reasoning / verification retries |

**agy is multi-model.** Tiers default to Gemini Flash thinking levels, but you can use any model `agy models` lists: pass `--model "<exact name>"`, or set it persistently via environment variables — `AGY_DEFAULT_MODEL`, or per-tier `AGY_TIER_LOW` / `AGY_TIER_MEDIUM` / `AGY_TIER_HIGH`. Other knobs: `AGY_DEFAULT_TIER`, `AGY_TIMEOUT`, `AGY_DIGEST_WARN_CHARS`. Keep the executor a *different, cheaper* model than the conductor — that's what gives the cost saving.

## 🚧 Guardrails & known limits

**Guardrails**
- Always **verify** agy's output (it can be wrong, and may even alter its environment to make a check pass — re-run gates yourself in a clean state).
- `--yolo` auto-approves every agy tool call — use with `--sandbox` or in a throwaway dir.
- Write tasks: run on a dedicated branch/worktree, review the diff before merging.

**Known limits (agy v1.0.x)**
- `-p`/`--print` **takes the prompt as its value** and must come last — the wrapper handles this.
- No `--output-format json` (plain text); `--print` drops stdout on a non-TTY unless stdin is detached (handled via `< /dev/null`).
- **Writes need `--yolo`:** without it, headless agy only *describes* edits and returns a confident success **without writing any files**. Long write tasks can exceed the shell-tool time limit → use a background job (`agy-job`).
- **Native Windows (no ConPTY):** headless `agy -p` / `agy models` can hard-hang with a 0-byte log when stdio is redirected. The wrapper wraps agy in a wall-clock `timeout`/`gtimeout` guard so it returns a structured TIMEOUT (exit 12) instead of hanging. Use WSL/macOS/Linux for headless delegation.
- **WSL:** running agy with `--add-dir` on a Windows mount (`/mnt/c/...`) is very slow (9p bridge). Keep the repo on the WSL Linux filesystem (`~`). The wrapper and `agy-doctor` warn about this.

## 📦 What's inside · tests

```
.codex-plugin/plugin.json        Codex plugin manifest
.agents/plugins/marketplace.json Codex repo marketplace (codex plugin marketplace add zicjin/agy-plugin)
.claude-plugin/plugin.json       Claude Code plugin manifest
.claude-plugin/marketplace.json  Claude Code marketplace (/plugin marketplace add zicjin/agy-plugin)
skills/                          shared plugin skills: agy-delegate, agy-research, agy-jobs, agy-setup, agy-prompting
hooks/hooks.json                 Codex SessionStart hook — injects the delegation policy as session context
hooks/claude-hooks.json          Claude Code SessionStart hook (startup + compact) — same policy injection
scripts/                         agy-delegate.sh · agy-job.sh · doctor.sh
docs/AGENTS-snippet.md           the routing policy + verification gates (injected by the hook)
tests/                           dependency-free tests (stub agy); bash tests/run-tests.sh
```

**Tests** (no dependencies; stubs `agy`):
```bash
bash tests/run-tests.sh
```

## How the two platforms share one repo

The core is platform-neutral — pure-bash scripts, open-format `SKILL.md` skills, and a plain-text policy snippet. Each platform gets a thin packaging shell:

| | Codex | Claude Code |
|---|---|---|
| manifest | `.codex-plugin/plugin.json` | `.claude-plugin/plugin.json` |
| marketplace | `.agents/plugins/marketplace.json` | `.claude-plugin/marketplace.json` |
| policy hook | `hooks/hooks.json` (SessionStart) | `hooks/claude-hooks.json` (SessionStart: startup + compact) |
| skills | `skills/` (shared) | `skills/` (shared) |
| scripts | `scripts/` (shared, invoked by path) | `scripts/` (shared, invoked by path) |

Configuration is plain env vars (`AGY_*`) on both platforms.
