<div align="center">

# 🛰️ Antigravity for Codex (`agy-plugin-codex`)

**Run the Antigravity CLI (Gemini) as a collaborating sub-agent, right inside OpenAI Codex.**

Codex conducts the judgement; Gemini does the heavy lifting — intelligent model routing across the SDLC.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity%20CLI-agy-4285F4?logo=googlegemini&logoColor=white)](https://antigravity.google/docs/cli-using)

</div>

A Codex port of [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code): the same robust `agy` delegation wrapper, background jobs, and routing/cost discipline — wired into Codex's native extension points (custom prompts in `~/.codex/prompts/` and `AGENTS.md`) instead of Claude Code's plugin system.

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
- **Built-in cost discipline** — `--digest` output contracts, dump-size warnings, break-even guidance baked into the prompts and the AGENTS.md snippet.
- **Drops in via AGENTS.md** — Codex reads `AGENTS.md` natively, so pasting `docs/AGENTS-snippet.md` into a repo gives Codex the routing policy + verification gates on every session, no hooks needed. `agy` reads the same file — one shared harness for both AIs.

## 🚀 Install

```bash
git clone https://github.com/zicjin/agy-plugin-codex ~/agy-plugin-codex
~/agy-plugin-codex/install.sh
```

`install.sh` (idempotent; `--uninstall` reverses it):
1. symlinks `prompts/*.md` into `~/.codex/prompts/` → slash commands `/agy-delegate`, `/agy-review`, `/agy-research`, `/agy-setup`, `/agy-status`, `/agy-result`, `/agy-cancel`;
2. adds `bin/` to your PATH (in `~/.bashrc` / `~/.zshrc`) so Codex's shell tool can call `agy-delegate`, `agy-job`, `agy-doctor` by bare name;
3. reminds you to paste `docs/AGENTS-snippet.md` into each repo's `AGENTS.md` — that's what makes Codex delegate **proactively** (the Codex equivalent of the Claude plugin's skill + session hook).

Then verify: `agy-doctor` (or `/agy-setup` inside Codex).

**Prerequisites:** the [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy`) installed & authenticated (`agy models` lists Gemini models), and [Codex CLI](https://github.com/openai/codex).

**Platform support:** macOS, Linux, and WSL. Native Windows (Git Bash/MSYS) is not recommended — headless `agy -p` can hang without a real console (ConPTY); the wrapper bounds this with a wall-clock guard (GNU `timeout`/`gtimeout`) and `agy-doctor` distinguishes a hang from an auth failure.

**Codex sandbox note:** in Codex's default sandbox, `agy` needs network access, so the delegation command may require approval. Approve it when prompted, or run Codex with a policy that allows it (e.g. `--sandbox danger-full-access` in a trusted environment, or add an approval rule for `agy-delegate`).

## 🧩 Slash commands (custom prompts)

| command | what it does |
|---|---|
| `/agy-setup` | health check — `agy` installed + authenticated, prompts installed, PATH wired |
| `/agy-delegate [--tier flash\|pro] <task>` | delegate a subtask to agy under cost discipline, then verify |
| `/agy-review [--adversarial]` | independent cross-model review of the current diff; Codex reconciles |
| `/agy-research <topic>` | Codex-orchestrated deep research — agy does grounded web legwork, Codex verifies citations across ≥2 sources |
| `/agy-status [id]` · `/agy-result <id>` · `/agy-cancel <id>` | manage background delegation jobs |

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
prompts/          Codex custom prompts (installed to ~/.codex/prompts): /agy-delegate, /agy-review, ...
scripts/          agy-delegate.sh · agy-job.sh · doctor.sh
bin/              bare-name entrypoints (agy-delegate, agy-job, agy-doctor) — install.sh puts this on PATH
docs/AGENTS-snippet.md   the routing policy + verification gates to paste into a repo's AGENTS.md
install.sh        wires prompts + PATH (idempotent; --uninstall reverses)
tests/            dependency-free tests (stub agy); bash tests/run-tests.sh
```

**Tests** (no dependencies; stubs `agy`):
```bash
bash tests/run-tests.sh
```

## Differences from the Claude Code plugin

Codex has no plugin marketplace, hooks, or subagent files, so this port maps each mechanism to a Codex-native one:

| Claude Code plugin | this project |
|---|---|
| `/plugin install` + marketplace manifest | `git clone` + `install.sh` |
| slash commands (`commands/*.md`) | custom prompts (`prompts/*.md` → `~/.codex/prompts/`) |
| skill (`skills/antigravity/SKILL.md`) + SessionStart policy hook | `docs/AGENTS-snippet.md` pasted into the repo's `AGENTS.md` (Codex reads it natively) |
| `antigravity-delegate` subagent | `/agy-delegate` prompt + AGENTS.md policy (Codex has no subagent files) |
| plugin `userConfig` (`CLAUDE_PLUGIN_OPTION_*` env) | plain env vars (`AGY_CODEX_*`) |
| plugin `bin/` auto on PATH | `install.sh` adds `bin/` to your shell rc |

## ⚠️ Disclaimer

Community project. **Not affiliated with, endorsed by, or supported by Google, OpenAI, or Anthropic.** "Antigravity", "Gemini", and "Codex" are trademarks of their respective owners. This project orchestrates the third-party `agy` CLI; you are responsible for your own API/cloud costs, credentials, and data-sharing choices. MIT licensed — see [LICENSE](LICENSE). Derived from [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code) (MIT).
