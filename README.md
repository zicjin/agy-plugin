<div align="center">

# 🛰️ Antigravity for Codex (`agy-plugin-codex`)

**Run the Antigravity CLI (Gemini) as a collaborating sub-agent, right inside OpenAI Codex.**

Codex conducts the judgement; Gemini does the heavy lifting — intelligent model routing across the SDLC.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity%20CLI-agy-4285F4?logo=googlegemini&logoColor=white)](https://antigravity.google/docs/cli-using)

</div>

A Codex port of [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code): the same robust `agy` delegation wrapper, background jobs, and routing/cost discipline — packaged as an official [Codex plugin](https://developers.openai.com/codex/plugins) (skills + a SessionStart policy hook).

## 💡 Why

| | Codex (conductor) | Gemini / `agy` (executor) |
|---|---|---|
| **Owns** | requirements · architecture · the hard 20% · **verification** · review | scaffold · implementation · test generation · search |
| **Strength** | judgement | cheap, fast throughput |

```
you → Codex (conduct: design / verify / review)
         └── agy → Gemini (execute: implement / test / search)
```

> *Generation is solved; verification, judgement, and direction are the craft.*

## ✨ What it does

- **Routes work across the SDLC** — Codex keeps the judgement calls; Antigravity handles scaffolding, test generation, first-pass review, and migrations under a shared `AGENTS.md`.
- **Adds tools Codex may lack** — live Google/web search, Vertex AI Search over your internal data, deep research. Codex reviews and re-checks the results.
- **Cross-model verification** — an independent, different-model opinion on your code (`git diff | agy-delegate --tier pro -`).
- **Background jobs** — fire a long delegation with `agy-job`, keep working, collect later.
- **Built-in cost discipline** — `--digest` output contracts, dump-size warnings, break-even guidance baked into the skills and the policy snippet.
- **Policy injected automatically** — the plugin's SessionStart hook injects `docs/AGENTS-snippet.md` (routing policy + verification gates) into every session; no per-repo `AGENTS.md` editing. Since `agy` reads `AGENTS.md` natively, you can additionally paste the snippet into a repo to share the same harness with agy itself.

## 🚀 Install

```bash
codex plugin marketplace add zicjin/agy-plugin-codex
```

Then inside Codex run `/plugins`, pick the **Antigravity for Codex** marketplace, and install **agy-plugin-codex**. This gives you:

- **Skills** — `$agy-delegate`, `$agy-review`, `$agy-research`, `$agy-jobs`, `$agy-setup` (type `$` or run `/skills`; Codex can also pick them implicitly when a task matches).
- **SessionStart hook** — injects the routing policy + verification gates (`docs/AGENTS-snippet.md`) as developer context in every session, so Codex delegates **proactively** without you editing each repo's `AGENTS.md`. Plugin hooks aren't trusted automatically — Codex asks you to review and trust the hook once.

The skills call the bundled `scripts/*.sh` by path — no PATH setup needed. Verify with `$agy-setup` inside Codex (or run the plugin's `scripts/doctor.sh` directly).

**Prerequisites:** the [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy`) installed & authenticated (`agy models` lists Gemini models), and [Codex CLI](https://github.com/openai/codex).

**Platform support:** macOS, Linux, and WSL. Native Windows (Git Bash/MSYS) is not recommended — headless `agy -p` can hang without a real console (ConPTY); the wrapper bounds this with a wall-clock guard (GNU `timeout`/`gtimeout`) and `agy-doctor` distinguishes a hang from an auth failure.

**Codex sandbox note:** in Codex's default sandbox, `agy` needs network access, so the delegation command may require approval. Approve it when prompted, or run Codex with a policy that allows it (e.g. `--sandbox danger-full-access` in a trusted environment, or add an approval rule for `agy-delegate`).

## 🧩 Skills

| skill | what it does |
|---|---|
| `$agy-setup` | health check — `agy` installed + authenticated, wiring OK |
| `$agy-delegate` | delegate a subtask to agy under cost discipline, then verify |
| `$agy-review` | independent cross-model review of the current diff (`--adversarial` style on request); Codex reconciles |
| `$agy-research` | Codex-orchestrated deep research — agy does grounded web legwork, Codex verifies citations across ≥2 sources |
| `$agy-jobs` | manage background delegation jobs (list / status / result / cancel) |
| `$agy-prompting` | internal: how to compose operator-style prompt contracts for agy (XML blocks, output contracts, `--continue` delta follow-ups) |

Reviews are **review-only**: findings are reported and never auto-fixed — Codex asks which findings you want addressed. Adversarial reviews use a ready-made prompt contract (`docs/adversarial-review-prompt.md`, adapted from OpenAI's [codex-plugin-cc](https://github.com/openai/codex-plugin-cc)) that pressure-tests design choices, failure modes, and assumptions, and returns a `VERDICT:` line with severity-ordered, confidence-scored findings.

> Background jobs are for **interactive** sessions (fire-and-collect). In headless `codex exec` (one-shot), delegate **synchronously** — there's no later turn to collect a result.

## 🛠️ Direct script usage & tiers

```bash
# one-shot delegation (plain text on stdout)
agy-delegate --tier flash "Summarize this changelog in 3 bullets: ..."

# give Antigravity a workspace for multi-file agentic work
agy-delegate --tier pro --dir ./src "List every TODO with file:line"

# bulk read -> digest-only reply (the biggest cost lever; wrapper warns on dump-sized replies)
agy-delegate --digest --dir . "Map the auth flow end to end"

# live web / Google search (tools need --yolo in headless mode)
agy-delegate --tier pro --yolo "Web-search <X>. Give URLs + dates."

# cross-model review / stdin / background job
git diff | agy-delegate --tier pro -
ID=$(agy-job start --tier pro --dir . "big task"); agy-job result "$ID"
```

| tier | model | use for |
|------|-------|---------|
| `flash` (default) | Gemini 3.5 Flash (High) | most bulk work |
| `flash-lo` | Gemini 3.5 Flash (Low) | cheapest, trivial tasks |
| `pro` | Gemini 3.1 Pro (High) | harder reasoning / cross-checks |

**agy is multi-model.** Tiers default to Gemini, but you can use any model `agy models` lists: pass `--model "<exact name>"`, or set it persistently via environment variables — `AGY_CODEX_DEFAULT_MODEL`, or per-tier `AGY_CODEX_TIER_FLASH` / `AGY_CODEX_TIER_FLASH_LO` / `AGY_CODEX_TIER_PRO`. Other knobs: `AGY_CODEX_DEFAULT_TIER`, `AGY_CODEX_TIMEOUT`, `AGY_CODEX_DIGEST_WARN_CHARS`. Keep the executor a *different, cheaper* model than the Codex conductor — that's what gives both the cost saving and the cross-model verification.

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
.agents/plugins/marketplace.json repo marketplace (codex plugin marketplace add zicjin/agy-plugin-codex)
skills/                          plugin skills: agy-delegate, agy-review, agy-research, agy-jobs, agy-setup, agy-prompting
hooks/hooks.json                 SessionStart hook — injects the delegation policy as session context
scripts/                         agy-delegate.sh · agy-job.sh · doctor.sh
docs/AGENTS-snippet.md           the routing policy + verification gates (injected by the hook)
docs/adversarial-review-prompt.md  XML prompt contract for adversarial reviews (prepend to a diff)
tests/                           dependency-free tests (stub agy); bash tests/run-tests.sh
```

**Tests** (no dependencies; stubs `agy`):
```bash
bash tests/run-tests.sh
```

## Differences from the Claude Code plugin

Codex now has its own plugin system, so most mechanisms map directly; the rest fall back to Codex-native equivalents:

| Claude Code plugin | this project |
|---|---|
| `/plugin install` + marketplace manifest | `codex plugin marketplace add zicjin/agy-plugin-codex` (`.codex-plugin/plugin.json` + `.agents/plugins/marketplace.json`) |
| slash commands (`commands/*.md`) | plugin skills (`skills/*/SKILL.md`, invoked with `$`) |
| skill (`skills/antigravity/SKILL.md`) + SessionStart policy hook | plugin SessionStart hook injecting `docs/AGENTS-snippet.md` |
| `antigravity-delegate` subagent | `$agy-delegate` skill + delegation policy (Codex has no subagent files) |
| plugin `userConfig` (`CLAUDE_PLUGIN_OPTION_*` env) | plain env vars (`AGY_CODEX_*`) |
| plugin `bin/` auto on PATH | skills invoke the bundled `scripts/*.sh` by path |

## ⚠️ Disclaimer

Community project. **Not affiliated with, endorsed by, or supported by Google, OpenAI, or Anthropic.** "Antigravity", "Gemini", and "Codex" are trademarks of their respective owners. This project orchestrates the third-party `agy` CLI; you are responsible for your own API/cloud costs, credentials, and data-sharing choices. MIT licensed — see [LICENSE](LICENSE). Derived from [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code) (MIT).
