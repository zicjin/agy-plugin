#!/usr/bin/env bash
#
# run-tests.sh — dependency-free tests (no bats). Stubs executor CLIs on PATH
# and asserts both marketplace plugins (agy-plugin + grok-plugin) and packaging.
#
#   bash tests/run-tests.sh
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
AGY_DELEGATE="$ROOT/plugins/agy-plugin/scripts/agy-delegate.sh"
AGY_JOB="$ROOT/plugins/agy-plugin/scripts/agy-job.sh"
GROK_DELEGATE="$ROOT/plugins/grok-plugin/scripts/grok-delegate.sh"
GROK_JOB="$ROOT/plugins/grok-plugin/scripts/grok-job.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

mkdir -p "$TMP/bin"
cat > "$TMP/bin/agy" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
case "${STUB_MODE:-text}" in
  empty)   exit 0 ;;
  fail)    echo "boom" >&2; exit 7 ;;
  args)    printf '%s\n' "$*" ;;
  quota)   echo "Error: quota exceeded for this model" >&2; exit 1 ;;
  auth)    echo "Error: request is unauthenticated; please sign in" >&2; exit 1 ;;
  auth2)   echo "You are not authenticated." >&2; exit 1 ;;
  timeout) echo "Error: deadline exceeded (the request timed out)" >&2; exit 1 ;;
  big)     printf 'x%.0s' $(seq 1 20000); echo ;;
  *)       echo "STUB_OK" ;;
esac
STUB
chmod +x "$TMP/bin/agy"
cp "$TMP/bin/agy" "$TMP/bin/grok"; chmod +x "$TMP/bin/grok"
export PATH="$TMP/bin:$PATH"

check() {
  local desc="$1" erc="$2" arc="$3" sub="${4:-}" out="${5:-}"
  if [ "$arc" != "$erc" ]; then echo "FAIL: $desc (rc want $erc got $arc)"; FAIL=$((FAIL+1)); return; fi
  if [ -n "$sub" ] && ! printf '%s' "$out" | grep -qF -- "$sub"; then
    echo "FAIL: $desc (missing '$sub' in output)"; FAIL=$((FAIL+1)); return; fi
  echo "ok: $desc"; PASS=$((PASS+1))
}

echo "== agy-plugin / agy-delegate.sh =="
DELEGATE="$AGY_DELEGATE"
JOB="$AGY_JOB"

out=$(STUB_MODE=text "$DELEGATE" "hello" 2>/dev/null); rc=$?
check "agy: normal text passes through" 0 "$rc" "STUB_OK" "$out"

out=$(STUB_MODE=empty "$DELEGATE" "hello" 2>/dev/null); rc=$?
check "agy: empty output -> exit 3" 3 "$rc"

out=$(STUB_MODE=fail "$DELEGATE" "hello" 2>/dev/null); rc=$?
check "agy: failure -> exit 2" 2 "$rc"

out=$("$DELEGATE" 2>/dev/null); rc=$?
check "agy: no prompt -> exit 1" 1 "$rc"

out=$("$DELEGATE" --bogus "hi" 2>/dev/null); rc=$?
check "agy: unknown option -> exit 1" 1 "$rc"

out=$("$DELEGATE" --driver agy "hi" 2>&1); rc=$?
check "agy: --driver rejected (no multi-driver switch)" 1 "$rc" "unknown option" "$out"

out=$(STUB_MODE=args "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "agy: default tier -> Flash Medium" 0 "$rc" "Gemini 3.5 Flash (Medium)" "$out"

out=$(STUB_MODE=args "$DELEGATE" --tier low "hi" 2>/dev/null); rc=$?
check "agy: low tier" 0 "$rc" "Gemini 3.5 Flash (Low)" "$out"

out=$(STUB_MODE=args "$DELEGATE" --tier high "hi" 2>/dev/null); rc=$?
check "agy: high tier" 0 "$rc" "Gemini 3.5 Flash (High)" "$out"

out=$(printf 'piped prompt' | STUB_MODE=args "$DELEGATE" - 2>/dev/null); rc=$?
check "agy: stdin prompt" 0 "$rc" "-p" "$out"

out=$(STUB_MODE=quota "$DELEGATE" "hi" 2>&1); rc=$?
check "agy: quota -> exit 10 + signal" 10 "$rc" "QUOTA_EXHAUSTED" "$out"

out=$(STUB_MODE=auth "$DELEGATE" "hi" 2>&1); rc=$?
check "agy: auth -> exit 11 + signal" 11 "$rc" "AUTH_REQUIRED" "$out"

out=$(STUB_MODE=timeout "$DELEGATE" "hi" 2>&1); rc=$?
check "agy: timeout -> exit 12 + signal" 12 "$rc" "TIMEOUT" "$out"

if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  out=$(STUB_MODE=text STUB_SLEEP=20 "$DELEGATE" --timeout 1s "hi" 2>&1); rc=$?
  check "agy: hang guard -> exit 12" 12 "$rc" "TIMEOUT" "$out"
else
  echo "ok: (skipped) hang-guard test — no timeout/gtimeout on PATH"; PASS=$((PASS+1))
fi

out=$(STUB_MODE=args SUBVIBE_DEFAULT_TIER=high "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "agy: SUBVIBE_DEFAULT_TIER=high" 0 "$rc" "Gemini 3.5 Flash (High)" "$out"

out=$(STUB_MODE=args SUBVIBE_DEFAULT_MODEL="Claude Sonnet 4.5" "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "agy: SUBVIBE_DEFAULT_MODEL" 0 "$rc" "Claude Sonnet 4.5" "$out"

out=$(STUB_MODE=args AGY_TIER_MEDIUM="Claude Sonnet 4.5" "$DELEGATE" --tier medium "hi" 2>/dev/null); rc=$?
check "agy: AGY_TIER_MEDIUM remap" 0 "$rc" "Claude Sonnet 4.5" "$out"

out=$(STUB_MODE=args SUBVIBE_TIMEOUT=9m "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "agy: SUBVIBE_TIMEOUT=9m" 0 "$rc" "--print-timeout 9m" "$out"

out=$(PATH="/usr/bin:/bin" "$DELEGATE" "hi" 2>&1); rc=$?
check "agy: missing binary -> exit 13 + CLI_MISSING" 13 "$rc" "CLI_MISSING" "$out"

# SUBVIBE_DRIVER must not affect fixed-driver plugins
out=$(STUB_MODE=args SUBVIBE_DRIVER=grok "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "agy: SUBVIBE_DRIVER ignored (still agy models)" 0 "$rc" "Gemini 3.5 Flash (Medium)" "$out"

out=$(STUB_MODE=args "$DELEGATE" --digest "hi" 2>/dev/null); rc=$?
check "agy: --digest contract" 0 "$rc" "OUTPUT CONTRACT (digest)" "$out"

out=$(STUB_MODE=big "$DELEGATE" "hi" 2>&1 >/dev/null); rc=$?
check "agy: dump-sized -> raw-dump note" 0 "$rc" "raw dump" "$out"

out=$(STUB_MODE=args "$DELEGATE" "implement the parser module" 2>&1); rc=$?
check "agy: write prompt w/o --yolo warns" 0 "$rc" "DESCRIBES" "$out"

out=$(WSL_DISTRO_NAME=Ubuntu "$DELEGATE" --dir /mnt/c/proj --print-command "hi" 2>&1); rc=$?
check "agy: WSL + /mnt slow-mount note" 0 "$rc" "9p bridge" "$out"

echo "== agy-plugin / agy-job.sh =="
export AGY_JOBS="$TMP/agy-jobs"
id=$(STUB_MODE=text "$JOB" start "hello job" 2>/dev/null); rc=$?
check "agy-job: start returns id" 0 "$rc"
for _ in $(seq 1 50); do st=$("$JOB" status "$id" 2>/dev/null | grep -o 'state=[a-z]*'); [ "$st" = "state=done" ] && break; sleep 0.2; done
out=$("$JOB" status "$id" 2>&1); rc=$?
check "agy-job: status done" 0 "$rc" "state=done" "$out"
out=$("$JOB" result "$id" 2>/dev/null); rc=$?
check "agy-job: result stdout" 0 "$rc" "STUB_OK" "$out"
id=$(STUB_MODE=quota "$JOB" start "hi" 2>/dev/null)
for _ in $(seq 1 50); do st=$("$JOB" status "$id" 2>/dev/null | grep -o 'state=[a-z]*'); [ "$st" = "state=failed" ] && break; sleep 0.2; done
out=$("$JOB" status "$id" 2>&1); rc=$?
check "agy-job: quota signal surfaced" 0 "$rc" "QUOTA_EXHAUSTED" "$out"

echo "== grok-plugin / grok-delegate.sh =="
DELEGATE="$GROK_DELEGATE"
JOB="$GROK_JOB"

out=$(STUB_MODE=args "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "grok: default -> grok-4.5 + medium effort" 0 "$rc" "--model grok-4.5 --reasoning-effort medium" "$out"

out=$(STUB_MODE=args "$DELEGATE" --tier high "hi" 2>/dev/null); rc=$?
check "grok: --tier high" 0 "$rc" "--reasoning-effort high" "$out"

out=$(STUB_MODE=args "$DELEGATE" --tier low "hi" 2>/dev/null); rc=$?
check "grok: --tier low -> composer" 0 "$rc" "--model grok-composer-2.5-fast -p" "$out"

out=$(STUB_MODE=args GROK_TIER_HIGH="my-model" "$DELEGATE" --tier high "hi" 2>/dev/null); rc=$?
check "grok: GROK_TIER_HIGH remap" 0 "$rc" "--model my-model" "$out"

out=$(STUB_MODE=args "$DELEGATE" --yolo --sandbox -c --conversation abc123 --dir /tmp/w "hi" 2>/dev/null); rc=$?
check "grok: yolo -> --always-approve" 0 "$rc" "--always-approve" "$out"
check "grok: sandbox -> readonly" 0 "$rc" "--sandbox readonly" "$out"
check "grok: continue + resume" 0 "$rc" "--continue --resume abc123" "$out"
check "grok: --dir -> --cwd" 0 "$rc" "--cwd /tmp/w" "$out"

out=$(STUB_MODE=auth2 "$DELEGATE" "hi" 2>&1); rc=$?
check "grok: auth -> exit 11" 11 "$rc" "AUTH_REQUIRED" "$out"

out=$(PATH="/usr/bin:/bin" "$DELEGATE" "hi" 2>&1); rc=$?
check "grok: missing binary -> install hint" 13 "$rc" "x.ai/cli/install.sh" "$out"

out=$(STUB_MODE=args SUBVIBE_DRIVER=agy "$DELEGATE" "hi" 2>/dev/null); rc=$?
check "grok: SUBVIBE_DRIVER ignored (still grok)" 0 "$rc" "--model grok-4.5" "$out"

out=$("$DELEGATE" --driver grok "hi" 2>&1); rc=$?
check "grok: --driver rejected" 1 "$rc" "unknown option" "$out"

echo "== grok-plugin / grok-job.sh =="
export GROK_JOBS="$TMP/grok-jobs"
id=$(STUB_MODE=text "$JOB" start "hello job" 2>/dev/null); rc=$?
check "grok-job: start returns id" 0 "$rc"
for _ in $(seq 1 50); do st=$("$JOB" status "$id" 2>/dev/null | grep -o 'state=[a-z]*'); [ "$st" = "state=done" ] && break; sleep 0.2; done
out=$("$JOB" result "$id" 2>/dev/null); rc=$?
check "grok-job: result stdout" 0 "$rc" "STUB_OK" "$out"

echo "== marketplace packaging =="
export ROOT
out=$(python3 - 2>&1 <<'PY'
import json, os
root = os.environ["ROOT"]

# Codex marketplace: two plugins under plugins/
m = json.load(open(os.path.join(root, ".agents", "plugins", "marketplace.json")))
assert m["name"] == "subvibe"
names = {e["name"] for e in m["plugins"]}
assert names == {"agy-plugin", "grok-plugin"}, names
for e in m["plugins"]:
    p = e["source"]["path"]
    assert p.startswith("./plugins/")
    assert os.path.exists(os.path.join(root, p, ".codex-plugin", "plugin.json")), p
    assert e["policy"]["installation"] and e["policy"]["authentication"] and e["category"]

# Claude marketplace
cm = json.load(open(os.path.join(root, ".claude-plugin", "marketplace.json")))
assert cm["name"] == "subvibe"
cnames = {e["name"] for e in cm["plugins"]}
assert cnames == {"agy-plugin", "grok-plugin"}, cnames
for e in cm["plugins"]:
    assert e["source"].startswith("./plugins/")
    assert os.path.exists(os.path.join(root, e["source"], ".claude-plugin", "plugin.json"))

# No root single-plugin manifests
assert not os.path.exists(os.path.join(root, ".codex-plugin", "plugin.json"))
assert not os.path.exists(os.path.join(root, ".claude-plugin", "plugin.json"))

# Per-plugin hooks + snippet
for plug in ("agy-plugin", "grok-plugin"):
    base = os.path.join(root, "plugins", plug)
    default_hook = os.path.join(base, "hooks", "hooks.json")
    assert not os.path.exists(default_hook), f"Claude auto-discovers Codex hook: {default_hook}"

    codex = json.load(open(os.path.join(base, ".codex-plugin", "plugin.json")))
    assert codex["hooks"] == "./hooks/codex-hooks.json"
    h = json.load(open(os.path.join(base, codex["hooks"][2:])))
    cmd = h["hooks"]["SessionStart"][0]["hooks"][0]["command"]
    assert "AGENTS-snippet.md" in cmd and "${PLUGIN_ROOT}" in cmd
    assert os.path.exists(os.path.join(base, "docs", "AGENTS-snippet.md"))

    ch = json.load(open(os.path.join(base, "hooks", "claude-hooks.json")))
    matchers = [g["matcher"] for g in ch["hooks"]["SessionStart"]]
    assert "startup" in matchers and "compact" in matchers
    commands = [hook["command"] for group in ch["hooks"]["SessionStart"] for hook in group["hooks"]]
    assert all("${CLAUDE_PLUGIN_ROOT}" in command for command in commands)
    # fixed driver constants present
    dscript = "agy-delegate.sh" if plug.startswith("agy") else "grok-delegate.sh"
    body = open(os.path.join(base, "scripts", dscript), encoding="utf-8").read()
    fixed = 'DRIVER="agy"' if plug.startswith("agy") else 'DRIVER="grok"'
    assert fixed in body
    assert "SUBVIBE_DRIVER" not in body or "no env override" in body or "no --driver" in body
    assert "--driver)" not in body  # parse branch removed

print("MARKETPLACE_OK")
PY
); rc=$?
check "marketplace lists agy-plugin + grok-plugin with valid paths" 0 "$rc" "MARKETPLACE_OK" "$out"

for plug_skill in \
  agy-plugin:agy-delegate agy-plugin:agy-research agy-plugin:agy-jobs agy-plugin:agy-setup agy-plugin:agy-prompting \
  grok-plugin:grok-delegate grok-plugin:grok-research grok-plugin:grok-jobs grok-plugin:grok-setup grok-plugin:grok-prompting
do
  plug="${plug_skill%%:*}"; skill="${plug_skill##*:}"
  f="$ROOT/plugins/$plug/skills/$skill/SKILL.md"
  if [ -f "$f" ] && head -1 "$f" | grep -q '^---$' \
     && grep -q "^name: $skill$" "$f" && grep -q '^description: .' "$f"; then
    echo "ok: skill $plug/$skill frontmatter"; PASS=$((PASS+1))
  else
    echo "FAIL: skill $plug/$skill frontmatter invalid or missing"; FAIL=$((FAIL+1))
  fi
done

# AGENTS-snippet routing notes
if grep -qi 'smaller parameter' "$ROOT/plugins/agy-plugin/docs/AGENTS-snippet.md"; then
  echo "ok: agy snippet notes smaller parameter footprint"; PASS=$((PASS+1))
else
  echo "FAIL: agy snippet missing parameter-size routing note"; FAIL=$((FAIL+1))
fi
if grep -qi 'stronger reasoning' "$ROOT/plugins/grok-plugin/docs/AGENTS-snippet.md"; then
  echo "ok: grok snippet notes stronger reasoning fit"; PASS=$((PASS+1))
else
  echo "FAIL: grok snippet missing reasoning routing note"; FAIL=$((FAIL+1))
fi

echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
