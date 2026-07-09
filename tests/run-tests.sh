#!/usr/bin/env bash
#
# run-tests.sh — dependency-free tests (no bats). Stubs `agy` on PATH and asserts
# agy-delegate.sh, agy-job.sh, and plugin packaging behavior.
#
#   bash tests/run-tests.sh
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DELEGATE="$ROOT/scripts/agy-delegate.sh"
JOB="$ROOT/scripts/agy-job.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# --- stub `agy` on PATH; behavior controlled by $STUB_MODE -------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/agy" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
case "${STUB_MODE:-text}" in
  empty)   exit 0 ;;                  # no stdout -> wrapper should exit 3
  fail)    echo "boom" >&2; exit 7 ;; # nonzero  -> wrapper should exit 2
  args)    printf '%s\n' "$*" ;;      # echo args for assertions
  quota)   echo "Error: quota exceeded for this model" >&2; exit 1 ;;     # -> wrapper exit 10
  auth)    echo "Error: request is unauthenticated; please sign in" >&2; exit 1 ;; # -> exit 11
  auth2)   echo "You are not authenticated." >&2; exit 1 ;;                        # grok-style -> exit 11
  timeout) echo "Error: deadline exceeded (the request timed out)" >&2; exit 1 ;;  # -> exit 12
  big)     printf 'x%.0s' $(seq 1 20000); echo ;;    # dump-sized reply -> digest guard warns
  *)       echo "STUB_OK" ;;
esac
STUB
chmod +x "$TMP/bin/agy"
export PATH="$TMP/bin:$PATH"

check() { # desc  expected_rc  actual_rc  [substr]  [actual_out]
  local desc="$1" erc="$2" arc="$3" sub="${4:-}" out="${5:-}"
  if [ "$arc" != "$erc" ]; then echo "FAIL: $desc (rc want $erc got $arc)"; FAIL=$((FAIL+1)); return; fi
  if [ -n "$sub" ] && ! printf '%s' "$out" | grep -qF -- "$sub"; then
    echo "FAIL: $desc (missing '$sub' in output)"; FAIL=$((FAIL+1)); return; fi
  echo "ok: $desc"; PASS=$((PASS+1))
}

echo "== agy-delegate.sh =="

out=$(STUB_MODE=text "$DELEGATE" "hello" 2>/dev/null); rc=$?
check "normal text passes through" 0 "$rc" "STUB_OK" "$out"

out=$(STUB_MODE=empty "$DELEGATE" "hello" 2>/dev/null); rc=$?
check "empty agy output -> exit 3" 3 "$rc"

out=$(STUB_MODE=fail "$DELEGATE" "hello" 2>/dev/null); rc=$?
check "agy failure -> exit 2" 2 "$rc"

out=$("$DELEGATE" 2>/dev/null); rc=$?
check "no prompt -> exit 1" 1 "$rc"

out=$("$DELEGATE" --bogus "hi" 2>/dev/null); rc=$?
check "unknown option -> exit 1" 1 "$rc"

out=$("$DELEGATE" --tier 2>/dev/null); rc=$?
check "option without value -> exit 1 (friendly)" 1 "$rc"

out=$(STUB_MODE=args "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "default tier -> Flash Medium" 0 "$rc" "Gemini 3.5 Flash (Medium)" "$out"

out=$(STUB_MODE=args "$DELEGATE" --tier low "hi" 2>/dev/null); rc=$?
check "low tier -> correct model string" 0 "$rc" "Gemini 3.5 Flash (Low)" "$out"

out=$(STUB_MODE=args "$DELEGATE" --tier high "hi" 2>/dev/null); rc=$?
check "high tier -> correct model string" 0 "$rc" "Gemini 3.5 Flash (High)" "$out"

out=$(printf 'piped prompt' | STUB_MODE=args "$DELEGATE" - 2>/dev/null); rc=$?
check "stdin prompt (-) read" 0 "$rc" "-p" "$out"

# structured exit codes + machine-readable signal (stderr merged into capture)
out=$(STUB_MODE=quota "$DELEGATE" "hi" 2>&1); rc=$?
check "agy quota -> exit 10 + signal" 10 "$rc" "QUOTA_EXHAUSTED" "$out"

out=$(STUB_MODE=auth "$DELEGATE" "hi" 2>&1); rc=$?
check "agy auth -> exit 11 + signal" 11 "$rc" "AUTH_REQUIRED" "$out"

out=$(STUB_MODE=timeout "$DELEGATE" "hi" 2>&1); rc=$?
check "agy timeout -> exit 12 + signal" 12 "$rc" "TIMEOUT" "$out"

# wall-clock guard: a HANGING agy (sleeps far past the timeout) must be killed and
# mapped to TIMEOUT (exit 12), not hang the wrapper forever. Requires a real
# `timeout`/`gtimeout`; skip cleanly if neither is on PATH.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  # outer guard for --timeout 1s = 1 + min-pad(10) = 11s; sleep well past it.
  out=$(STUB_MODE=text STUB_SLEEP=20 "$DELEGATE" --timeout 1s "hi" 2>&1); rc=$?
  check "hanging agy -> wall-clock guard kills it -> exit 12" 12 "$rc" "TIMEOUT" "$out"
else
  echo "ok: (skipped) hang-guard test — no timeout/gtimeout on PATH"; PASS=$((PASS+1))
fi

# env default tier; explicit --tier still wins
out=$(STUB_MODE=args AGY_DEFAULT_TIER=high "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "AGY_DEFAULT_TIER=high -> Flash High" 0 "$rc" "Gemini 3.5 Flash (High)" "$out"

out=$(STUB_MODE=args AGY_DEFAULT_TIER=high "$DELEGATE" --tier low "hi" 2>/dev/null); rc=$?
check "explicit --tier overrides env default" 0 "$rc" "Gemini 3.5 Flash (Low)" "$out"

# multi-model: default_model + per-tier remap (agy supports Claude/GPT on some plans)
out=$(STUB_MODE=args AGY_DEFAULT_MODEL="Claude Sonnet 4.5" "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "AGY_DEFAULT_MODEL -> used as-is" 0 "$rc" "Claude Sonnet 4.5" "$out"
out=$(STUB_MODE=args AGY_DEFAULT_MODEL="Claude Sonnet 4.5" "$DELEGATE" --tier high "hi" 2>/dev/null); rc=$?
check "explicit --tier beats default model" 0 "$rc" "Gemini 3.5 Flash (High)" "$out"
out=$(STUB_MODE=args AGY_DEFAULT_MODEL="Claude Sonnet 4.5" "$DELEGATE" -m "GPT-X" "hi" 2>/dev/null); rc=$?
check "explicit --model beats default model" 0 "$rc" "GPT-X" "$out"
out=$(STUB_MODE=args AGY_TIER_MEDIUM="Claude Sonnet 4.5" "$DELEGATE" --tier medium "hi" 2>/dev/null); rc=$?
check "AGY_TIER_MEDIUM remap -> medium uses remapped model" 0 "$rc" "Claude Sonnet 4.5" "$out"

# default + env timeout, with explicit flag winning
out=$(STUB_MODE=args "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "default timeout -> --print-timeout 5m" 0 "$rc" "--print-timeout 5m" "$out"
out=$(STUB_MODE=args AGY_TIMEOUT=9m "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "AGY_TIMEOUT=9m -> --print-timeout 9m" 0 "$rc" "--print-timeout 9m" "$out"
out=$(STUB_MODE=args AGY_TIMEOUT=9m "$DELEGATE" --timeout 3m "hi" 2>/dev/null); rc=$?
check "explicit --timeout overrides env" 0 "$rc" "--print-timeout 3m" "$out"

# invalid default tier from env falls back to medium; explicit --tier typo still errors
out=$(STUB_MODE=args AGY_DEFAULT_TIER=bogus "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "invalid env tier -> falls back to medium" 0 "$rc" "Gemini 3.5 Flash (Medium)" "$out"
out=$("$DELEGATE" --tier bogus "hi" 2>/dev/null); rc=$?
check "explicit --tier bogus -> exit 1" 1 "$rc"

# driver selection: agy is the default; unknown drivers fail with usage error
out=$(STUB_MODE=args "$DELEGATE" --driver agy "hi" 2>/dev/null); rc=$?
check "--driver agy -> same as default" 0 "$rc" "Gemini 3.5 Flash (Medium)" "$out"
out=$("$DELEGATE" --driver bogus "hi" 2>&1); rc=$?
check "--driver bogus -> exit 1 + lists available" 1 "$rc" "unknown driver" "$out"
out=$(AGY_DRIVER=bogus "$DELEGATE" "hi" 2>&1); rc=$?
check "AGY_DRIVER=bogus -> exit 1" 1 "$rc" "unknown driver" "$out"
out=$(STUB_MODE=args AGY_DRIVER=agy "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "AGY_DRIVER=agy -> works" 0 "$rc" "-p" "$out"

echo "== grok driver =="
# stub `grok` too (same STUB_MODE contract as the agy stub)
cp "$TMP/bin/agy" "$TMP/bin/grok"; chmod +x "$TMP/bin/grok"

out=$(STUB_MODE=args "$DELEGATE" --driver grok "hi" 2>/dev/null); rc=$?
check "grok: default -> grok-4.5 + medium effort" 0 "$rc" "--model grok-4.5 --reasoning-effort medium" "$out"
out=$(STUB_MODE=args "$DELEGATE" --driver grok --tier high "hi" 2>/dev/null); rc=$?
check "grok: --tier high -> --reasoning-effort high" 0 "$rc" "--reasoning-effort high" "$out"
out=$(STUB_MODE=args "$DELEGATE" --driver grok --tier low "hi" 2>/dev/null); rc=$?
check "grok: --tier low -> composer model, no effort flag" 0 "$rc" "--model grok-composer-2.5-fast -p" "$out"
out=$(STUB_MODE=args GROK_TIER_HIGH="my-model" "$DELEGATE" --driver grok --tier high "hi" 2>/dev/null); rc=$?
check "grok: GROK_TIER_HIGH remap respected" 0 "$rc" "--model my-model" "$out"
out=$(STUB_MODE=args "$DELEGATE" --driver grok --yolo --sandbox -c --conversation abc123 --dir /tmp/w "hi" 2>/dev/null); rc=$?
check "grok: yolo -> --always-approve" 0 "$rc" "--always-approve" "$out"
check "grok: sandbox -> readonly profile" 0 "$rc" "--sandbox readonly" "$out"
check "grok: continue + conversation -> --continue --resume" 0 "$rc" "--continue --resume abc123" "$out"
check "grok: --dir -> --cwd" 0 "$rc" "--cwd /tmp/w" "$out"
out=$(STUB_MODE=args "$DELEGATE" --driver grok --dir /a --dir /b --print-command "hi" 2>&1); rc=$?
check "grok: second --dir warned + ignored" 0 "$rc" "ignoring extra --dir" "$out"
out=$(STUB_MODE=auth2 "$DELEGATE" --driver grok "hi" 2>&1); rc=$?
check "grok: auth stderr -> exit 11 + signal" 11 "$rc" "AUTH_REQUIRED" "$out"
out=$(PATH="/usr/bin:/bin" "$DELEGATE" --driver grok "hi" 2>&1); rc=$?
check "grok: missing binary -> exit 13 + install hint" 13 "$rc" "x.ai/cli/install.sh" "$out"

# agy missing on PATH -> exit 13 + AGY_MISSING signal (PATH without the stub or real agy)
out=$(PATH="/usr/bin:/bin" "$DELEGATE" "hi" 2>&1); rc=$?
check "agy missing -> exit 13 + AGY_MISSING signal" 13 "$rc" "AGY_MISSING" "$out"

# --print-command: dry run prints the resolved agy invocation and exits 0 (agy not run)
out=$("$DELEGATE" --tier high --print-command "hi" 2>/dev/null); rc=$?
check "--print-command -> exit 0 + resolved flags" 0 "$rc" "--print-timeout 5m" "$out"
check "--print-command shows the tier model" 0 "$rc" "High" "$out"
out=$(PATH="/usr/bin:/bin" "$DELEGATE" --print-command "hi" 2>/dev/null); rc=$?
check "--print-command works without agy on PATH" 0 "$rc" "--print-timeout" "$out"

# write-task without --yolo -> warn (agy would only describe, not write)
out=$(STUB_MODE=args "$DELEGATE" "implement the parser module" 2>&1); rc=$?
check "write prompt w/o --yolo -> warns" 0 "$rc" "DESCRIBES" "$out"
out=$(STUB_MODE=args "$DELEGATE" --yolo "implement the parser module" 2>&1); rc=$?
if printf '%s' "$out" | grep -q "DESCRIBES"; then echo "FAIL: warned even with --yolo"; FAIL=$((FAIL+1));
else echo "ok: no write-warning when --yolo is set"; PASS=$((PASS+1)); fi
out=$(STUB_MODE=args "$DELEGATE" "summarize the changelog in 3 bullets" 2>&1); rc=$?
if printf '%s' "$out" | grep -q "DESCRIBES"; then echo "FAIL: warned for a non-write prompt"; FAIL=$((FAIL+1));
else echo "ok: no write-warning for a read/summary prompt"; PASS=$((PASS+1)); fi

# --digest appends the digest-only output contract to the prompt
out=$(STUB_MODE=args "$DELEGATE" --digest "hi" 2>/dev/null); rc=$?
check "--digest appends the output contract" 0 "$rc" "OUTPUT CONTRACT (digest)" "$out"
out=$("$DELEGATE" --help); rc=$?
check "usage documents --digest" 0 "$rc" "--digest" "$out"

# digest-size guard: dump-sized reply -> stderr note; small reply -> silent; 0 disables
out=$(STUB_MODE=big "$DELEGATE" "hi" 2>&1 >/dev/null); rc=$?
check "dump-sized output -> raw-dump note on stderr" 0 "$rc" "raw dump" "$out"
out=$(STUB_MODE=text "$DELEGATE" "hi" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q "raw dump"; then echo "FAIL: digest guard fired on a small reply"; FAIL=$((FAIL+1));
else echo "ok: digest guard silent on a small reply"; PASS=$((PASS+1)); fi
out=$(STUB_MODE=big AGY_DIGEST_WARN_CHARS=0 "$DELEGATE" "hi" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q "raw dump"; then echo "FAIL: digest guard fired with AGY_DIGEST_WARN_CHARS=0"; FAIL=$((FAIL+1));
else echo "ok: AGY_DIGEST_WARN_CHARS=0 disables the guard"; PASS=$((PASS+1)); fi
out=$(STUB_MODE=text AGY_DIGEST_WARN_CHARS=5 "$DELEGATE" "hi" 2>&1 >/dev/null); rc=$?
check "custom AGY_DIGEST_WARN_CHARS threshold respected" 0 "$rc" "raw dump" "$out"

# WSL slow-mount note: fires only under WSL AND when --add-dir is on /mnt/*
out=$(WSL_DISTRO_NAME=Ubuntu "$DELEGATE" --dir /mnt/c/proj --print-command "hi" 2>&1); rc=$?
check "WSL + /mnt --dir -> slow-mount note" 0 "$rc" "9p bridge" "$out"
out=$(WSL_DISTRO_NAME=Ubuntu "$DELEGATE" --dir /home/u/proj --print-command "hi" 2>&1); rc=$?
if printf '%s' "$out" | grep -q "9p bridge"; then echo "FAIL: slow-mount note fired for a Linux-FS --dir"; FAIL=$((FAIL+1));
else echo "ok: no slow-mount note for a Linux-FS --dir"; PASS=$((PASS+1)); fi

echo "== agy-job.sh =="
export ANTIGRAVITY_JOBS="$TMP/jobs"

id=$(STUB_MODE=text "$JOB" start "hello job" 2>/dev/null); rc=$?
check "job start returns an id" 0 "$rc"
for _ in $(seq 1 50); do st=$("$JOB" status "$id" 2>/dev/null | grep -o 'state=[a-z]*'); [ "$st" = "state=done" ] && break; sleep 0.2; done
out=$("$JOB" status "$id" 2>&1); rc=$?
check "job status -> done (rc=0)" 0 "$rc" "state=done" "$out"
out=$("$JOB" result "$id" 2>/dev/null); rc=$?
check "job result prints delegate stdout" 0 "$rc" "STUB_OK" "$out"
out=$("$JOB" list 2>/dev/null); rc=$?
check "job list shows the job" 0 "$rc" "$id" "$out"
out=$("$JOB" status nope 2>&1); rc=$?
check "unknown job id -> error" 1 "$rc" "no such job" "$out"

# failed delegation surfaces the structured signal in status
id=$(STUB_MODE=quota "$JOB" start "hi" 2>/dev/null)
for _ in $(seq 1 50); do st=$("$JOB" status "$id" 2>/dev/null | grep -o 'state=[a-z]*'); [ "$st" = "state=failed" ] && break; sleep 0.2; done
out=$("$JOB" status "$id" 2>&1); rc=$?
check "quota job -> failed + QUOTA signal surfaced" 0 "$rc" "QUOTA_EXHAUSTED" "$out"

echo "== plugin packaging =="
py_ok() { python3 - 2>&1; }
export ROOT
out=$(py_ok <<'PY'
import json, os, sys
root = os.environ["ROOT"]
m = json.load(open(os.path.join(root, ".codex-plugin", "plugin.json")))
assert m["name"] == "subvibe", "manifest name"
assert m["version"], "manifest version"
for f in ("skills", "hooks"):
    p = m[f]
    assert p.startswith("./"), f + " must be ./-prefixed"
    assert os.path.exists(os.path.join(root, p)), f + " path missing: " + p
print("MANIFEST_OK")
PY
); rc=$?
check "plugin.json valid + component paths exist" 0 "$rc" "MANIFEST_OK" "$out"

out=$(py_ok <<'PY'
import json, os
root = os.environ["ROOT"]
m = json.load(open(os.path.join(root, ".agents", "plugins", "marketplace.json")))
e = m["plugins"][0]
assert e["name"] == "subvibe"
p = e["source"]["path"]
assert p.startswith("./")
assert os.path.exists(os.path.join(root, p, ".codex-plugin", "plugin.json")), "source.path has no manifest"
assert e["policy"]["installation"] and e["policy"]["authentication"] and e["category"]
print("MARKETPLACE_OK")
PY
); rc=$?
check "marketplace.json valid + points at the plugin" 0 "$rc" "MARKETPLACE_OK" "$out"

out=$(py_ok <<'PY'
import json, os
root = os.environ["ROOT"]
h = json.load(open(os.path.join(root, "hooks", "hooks.json")))
cmd = h["hooks"]["SessionStart"][0]["hooks"][0]["command"]
assert "AGENTS-snippet.md" in cmd and "${PLUGIN_ROOT}" in cmd
print("HOOKS_OK")
PY
); rc=$?
check "hooks.json valid SessionStart hook" 0 "$rc" "HOOKS_OK" "$out"

out=$(py_ok <<'PY'
import json, os
root = os.environ["ROOT"]
m = json.load(open(os.path.join(root, ".claude-plugin", "plugin.json")))
assert m["name"] == "subvibe", "claude manifest name"
assert m["version"], "claude manifest version"
hp = m["hooks"]
assert hp.startswith("./") and os.path.exists(os.path.join(root, hp)), "claude hooks path"
h = json.load(open(os.path.join(root, hp)))
matchers = [g["matcher"] for g in h["hooks"]["SessionStart"]]
assert "startup" in matchers and "compact" in matchers, "startup+compact matchers"
for g in h["hooks"]["SessionStart"]:
    cmd = g["hooks"][0]["command"]
    assert "AGENTS-snippet.md" in cmd and "${CLAUDE_PLUGIN_ROOT}" in cmd
mk = json.load(open(os.path.join(root, ".claude-plugin", "marketplace.json")))
e = mk["plugins"][0]
assert e["name"] == "subvibe" and e["source"] == "./"
print("CLAUDE_OK")
PY
); rc=$?
check "claude plugin manifest + hooks + marketplace valid" 0 "$rc" "CLAUDE_OK" "$out"

for skill in agy-delegate agy-research agy-jobs agy-setup agy-prompting; do
  f="$ROOT/skills/$skill/SKILL.md"
  if [ -f "$f" ] && head -1 "$f" | grep -q '^---$' \
     && grep -q "^name: $skill$" "$f" && grep -q '^description: .' "$f"; then
    echo "ok: skill $skill has valid frontmatter"; PASS=$((PASS+1))
  else
    echo "FAIL: skill $skill frontmatter invalid or missing"; FAIL=$((FAIL+1))
  fi
done

echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
