#!/usr/bin/env bash
#
# run-tests.sh — dependency-free tests (no bats). Stubs `agy` on PATH and asserts
# agy-delegate.sh, agy-job.sh, and install.sh behavior.
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

out=$(STUB_MODE=args "$DELEGATE" --tier flash "hi" 2>/dev/null); rc=$?
check "flash tier -> correct model string" 0 "$rc" "Gemini 3.5 Flash (High)" "$out"

out=$(STUB_MODE=args "$DELEGATE" --tier pro "hi" 2>/dev/null); rc=$?
check "pro tier -> correct model string" 0 "$rc" "Gemini 3.1 Pro (High)" "$out"

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
out=$(STUB_MODE=args AGY_CODEX_DEFAULT_TIER=pro "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "AGY_CODEX_DEFAULT_TIER=pro -> Pro model" 0 "$rc" "Gemini 3.1 Pro (High)" "$out"

out=$(STUB_MODE=args AGY_CODEX_DEFAULT_TIER=pro "$DELEGATE" --tier flash "hi" 2>/dev/null); rc=$?
check "explicit --tier overrides env default" 0 "$rc" "Gemini 3.5 Flash (High)" "$out"

# multi-model: default_model + per-tier remap (agy supports Claude/GPT on some plans)
out=$(STUB_MODE=args AGY_CODEX_DEFAULT_MODEL="Claude Sonnet 4.5" "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "AGY_CODEX_DEFAULT_MODEL -> used as-is" 0 "$rc" "Claude Sonnet 4.5" "$out"
out=$(STUB_MODE=args AGY_CODEX_DEFAULT_MODEL="Claude Sonnet 4.5" "$DELEGATE" --tier flash "hi" 2>/dev/null); rc=$?
check "explicit --tier beats default model" 0 "$rc" "Gemini 3.5 Flash (High)" "$out"
out=$(STUB_MODE=args AGY_CODEX_DEFAULT_MODEL="Claude Sonnet 4.5" "$DELEGATE" -m "GPT-X" "hi" 2>/dev/null); rc=$?
check "explicit --model beats default model" 0 "$rc" "GPT-X" "$out"
out=$(STUB_MODE=args AGY_CODEX_TIER_FLASH="Claude Sonnet 4.5" "$DELEGATE" --tier flash "hi" 2>/dev/null); rc=$?
check "AGY_CODEX_TIER_FLASH remap -> flash uses remapped model" 0 "$rc" "Claude Sonnet 4.5" "$out"

# default + env timeout, with explicit flag winning
out=$(STUB_MODE=args "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "default timeout -> --print-timeout 5m" 0 "$rc" "--print-timeout 5m" "$out"
out=$(STUB_MODE=args AGY_CODEX_TIMEOUT=9m "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "AGY_CODEX_TIMEOUT=9m -> --print-timeout 9m" 0 "$rc" "--print-timeout 9m" "$out"
out=$(STUB_MODE=args AGY_CODEX_TIMEOUT=9m "$DELEGATE" --timeout 3m "hi" 2>/dev/null); rc=$?
check "explicit --timeout overrides env" 0 "$rc" "--print-timeout 3m" "$out"

# invalid default tier from env falls back to flash; explicit --tier typo still errors
out=$(STUB_MODE=args AGY_CODEX_DEFAULT_TIER=bogus "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "invalid env tier -> falls back to flash" 0 "$rc" "Gemini 3.5 Flash (High)" "$out"
out=$("$DELEGATE" --tier bogus "hi" 2>/dev/null); rc=$?
check "explicit --tier bogus -> exit 1" 1 "$rc"

# agy missing on PATH -> exit 13 + AGY_MISSING signal (PATH without the stub or real agy)
out=$(PATH="/usr/bin:/bin" "$DELEGATE" "hi" 2>&1); rc=$?
check "agy missing -> exit 13 + AGY_MISSING signal" 13 "$rc" "AGY_MISSING" "$out"

# --print-command: dry run prints the resolved agy invocation and exits 0 (agy not run)
out=$("$DELEGATE" --tier pro --print-command "hi" 2>/dev/null); rc=$?
check "--print-command -> exit 0 + resolved flags" 0 "$rc" "--print-timeout 5m" "$out"
check "--print-command shows the tier model" 0 "$rc" "Pro" "$out"
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
out=$(STUB_MODE=big AGY_CODEX_DIGEST_WARN_CHARS=0 "$DELEGATE" "hi" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q "raw dump"; then echo "FAIL: digest guard fired with AGY_CODEX_DIGEST_WARN_CHARS=0"; FAIL=$((FAIL+1));
else echo "ok: AGY_CODEX_DIGEST_WARN_CHARS=0 disables the guard"; PASS=$((PASS+1)); fi
out=$(STUB_MODE=text AGY_CODEX_DIGEST_WARN_CHARS=5 "$DELEGATE" "hi" 2>&1 >/dev/null); rc=$?
check "custom AGY_CODEX_DIGEST_WARN_CHARS threshold respected" 0 "$rc" "raw dump" "$out"

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

echo "== install.sh =="
FAKE_HOME="$TMP/home"; mkdir -p "$FAKE_HOME"; touch "$FAKE_HOME/.bashrc"
out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_HOME/.codex" "$ROOT/install.sh" 2>&1); rc=$?
check "install exits 0" 0 "$rc" "installed prompt: /agy-delegate" "$out"
[ -L "$FAKE_HOME/.codex/prompts/agy-delegate.md" ] \
  && { echo "ok: prompt symlinked into CODEX_HOME/prompts"; PASS=$((PASS+1)); } \
  || { echo "FAIL: prompt not symlinked"; FAIL=$((FAIL+1)); }
grep -qF '# agy-plugin-codex' "$FAKE_HOME/.bashrc" \
  && { echo "ok: PATH line added to .bashrc"; PASS=$((PASS+1)); } \
  || { echo "FAIL: PATH line not added"; FAIL=$((FAIL+1)); }
out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_HOME/.codex" "$ROOT/install.sh" 2>&1); rc=$?
check "install is idempotent" 0 "$rc"
n=$(grep -cF '# agy-plugin-codex' "$FAKE_HOME/.bashrc")
[ "$n" = "1" ] && { echo "ok: PATH line not duplicated"; PASS=$((PASS+1)); } \
  || { echo "FAIL: PATH line duplicated ($n)"; FAIL=$((FAIL+1)); }
out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_HOME/.codex" "$ROOT/install.sh" --uninstall 2>&1); rc=$?
check "uninstall exits 0" 0 "$rc"
[ ! -e "$FAKE_HOME/.codex/prompts/agy-delegate.md" ] \
  && { echo "ok: uninstall removed the prompt symlinks"; PASS=$((PASS+1)); } \
  || { echo "FAIL: prompt symlink still present after uninstall"; FAIL=$((FAIL+1)); }
grep -qF '# agy-plugin-codex' "$FAKE_HOME/.bashrc" \
  && { echo "FAIL: PATH line still present after uninstall"; FAIL=$((FAIL+1)); } \
  || { echo "ok: uninstall removed the PATH line"; PASS=$((PASS+1)); }

echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
