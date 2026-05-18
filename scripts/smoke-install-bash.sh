#!/usr/bin/env bash
# smoke-install-bash.sh — install agent-toolkit into a scratch dir and assert
# the expected tree, then re-run for idempotence and --update semantics.
#
# Used by tests-linux.yml and tests-mac.yml. Invoked from repo root:
#   bash scripts/smoke-install-bash.sh
#
# Exits non-zero on first failed assertion with a diagnostic.

set -euo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# Pre-push hook needs the scratch to be a git repo
git -C "$SCRATCH" init -q -b main

echo "==> fresh install into $SCRATCH"
bash "$TOOLKIT_ROOT/install.sh" "$SCRATCH" > "$SCRATCH/.install.log"

# ── expected files (every supported_host × every shipped primitive) ─────────
expected=(
  # Bundle: example-bundle → example-skill across 2 hosts (claude-code + antigravity).
  # gemini-cli host removed in v0.9.0 (ROADMAP #15) — .agents/skills/* no longer
  # populated.
  .claude/skills/example-skill/SKILL.md
  .agent/skills/example-skill/SKILL.md
  # Standalone skill: pii-scrubber across 2 hosts
  .claude/skills/pii-scrubber/SKILL.md
  .agent/skills/pii-scrubber/SKILL.md
  # Standalone skill: design (scaffold only in v0.7.0+; bodies in tasks 2-4 of plan #6).
  # Skill dir includes templates/design-doc.md which ships alongside SKILL.md.
  .claude/skills/design/SKILL.md
  .claude/skills/design/templates/design-doc.md
  .agent/skills/design/SKILL.md
  .agent/skills/design/templates/design-doc.md
  # Standalone skill: memory (plan #7a part 1 task 1 ships scaffold;
  # task 2 of part 1 ships /memory save body + scripts/save.py;
  # task 3 of part 1 ships /memory evolve body + scripts/evolve.py;
  # task 4 of part 1 ships embedding + sqlite-vec integration via
  # scripts/embed.py + scripts/vec_index.py — both wired into the async
  # path from save.py + evolve.py via embedding-queue.jsonl).
  .claude/skills/memory/SKILL.md
  .claude/skills/memory/scripts/save.py
  .claude/skills/memory/scripts/evolve.py
  .claude/skills/memory/scripts/embed.py
  .claude/skills/memory/scripts/vec_index.py
  .agent/skills/memory/SKILL.md
  .agent/skills/memory/scripts/save.py
  .agent/skills/memory/scripts/evolve.py
  .agent/skills/memory/scripts/embed.py
  .agent/skills/memory/scripts/vec_index.py
  # Standalone agent: evaluator — claude-code is single-file destination;
  # antigravity wraps the agent as a skill. (gemini-cli destination
  # .gemini/agents/evaluator.md removed in v0.9.0.)
  .claude/agents/evaluator.md
  .agent/skills/evaluator/SKILL.md
  # Standalone hooks — claude-code only (v0.7.0).
  .claude/hooks/kill-switch.sh
  .claude/hooks/steer.sh
  .claude/hooks/commit-on-stop.sh
  .claude/settings.json
  # Pre-push hook
  .git/hooks/pre-push
)

fail=0
for p in "${expected[@]}"; do
  if [[ ! -e "$SCRATCH/$p" ]]; then
    echo "MISSING: $p" >&2
    fail=1
  fi
done

# ── negative-existence assertions (v0.9.0+ — gemini-cli removed) ───────────
# These paths MUST NOT exist after install. Catches regressions if the
# gemini-cli dispatch arms ever come back to install.sh / install.ps1.
not_expected=(
  .agents
  .gemini
)
for p in "${not_expected[@]}"; do
  if [[ -e "$SCRATCH/$p" ]]; then
    echo "UNEXPECTED (v0.9.0+ removed gemini-cli): $p exists at $SCRATCH/$p" >&2
    fail=1
  fi
done

# ── installer-boundary: toolkit's own test infra must NOT propagate ─────────
leaks=(
  scripts/smoke-install-bash.sh
  scripts/smoke-install-pwsh.ps1
  scripts/check-integrity-bash.sh
  scripts/check-integrity-pwsh.ps1
  scripts/check-syntax.sh
  scripts/check-syntax.ps1
  scripts/check-lib-parity.sh
  scripts/check-no-pii.sh
  scripts/manifest-info.py
  scripts/validate-manifests.py
  lib/install/bash/primitives.sh
  lib/install/pwsh/primitives.ps1
  lib/install/CONTRACT.md
  .github/workflows/tests-linux.yml
  .github/workflows/tests-mac.yml
  .github/workflows/tests-windows.yml
  CONTRIBUTING.md
  CHANGELOG.md
  .gitleaks.toml
)
for p in "${leaks[@]}"; do
  if [[ -e "$SCRATCH/$p" ]]; then
    echo "LEAK: $p should not be in scratch install (installer boundary)" >&2
    fail=1
  fi
done

# ── pre-push hook is executable + byte-matches the template ─────────────────
if [[ -e "$SCRATCH/.git/hooks/pre-push" ]]; then
  if [[ ! -x "$SCRATCH/.git/hooks/pre-push" ]]; then
    echo "FAIL: .git/hooks/pre-push is not executable" >&2
    fail=1
  fi
  if ! cmp -s "$TOOLKIT_ROOT/templates/hooks/pre-push" "$SCRATCH/.git/hooks/pre-push"; then
    echo "FAIL: .git/hooks/pre-push does not match templates/hooks/pre-push" >&2
    fail=1
  fi
fi

if [[ $fail -ne 0 ]]; then
  echo "FAIL: expected-files or installer-boundary assertions failed" >&2
  exit 1
fi

# ── idempotent re-run: no "created" for previously-created paths ────────────
echo "==> idempotent re-run"
bash "$TOOLKIT_ROOT/install.sh" "$SCRATCH" > "$SCRATCH/.rerun.log"
if grep -qE "created .claude/skills/(example-skill|pii-scrubber)" "$SCRATCH/.rerun.log"; then
  echo "FAIL: re-run recreated a skill that already existed (should be 'kept')" >&2
  exit 1
fi
if grep -qE "created .claude/agents/evaluator" "$SCRATCH/.rerun.log"; then
  echo "FAIL: re-run recreated an agent that already existed (should be 'kept')" >&2
  exit 1
fi
# Same for hooks: re-run should not "create" scripts that already exist.
if grep -qE "created .claude/hooks/(kill-switch|steer|commit-on-stop)" "$SCRATCH/.rerun.log"; then
  echo "FAIL: re-run recreated a hook script that already existed (should be 'kept')" >&2
  exit 1
fi
if ! grep -qE "kept    .claude/skills/(example-skill|pii-scrubber)" "$SCRATCH/.rerun.log"; then
  echo "FAIL: re-run did not emit 'kept' messages for existing skills" >&2
  exit 1
fi
if ! grep -qE "kept    .claude/agents/evaluator" "$SCRATCH/.rerun.log"; then
  echo "FAIL: re-run did not emit 'kept' message for the evaluator agent" >&2
  exit 1
fi
# Hook idempotence: re-running the merge helper should report "kept" not "merged".
if grep -qE "merged  .claude/settings.json" "$SCRATCH/.rerun.log"; then
  echo "FAIL: re-run re-merged settings.json (should report 'kept' — entries already present)" >&2
  exit 1
fi
if ! grep -qE "kept    .claude/settings.json \(fragment entries already present\)" "$SCRATCH/.rerun.log"; then
  echo "FAIL: re-run did not emit 'kept' message for .claude/settings.json" >&2
  exit 1
fi

# ── --update: wipe + recreate semantics ─────────────────────────────────────
echo "==> --update wipe + recreate"
bash "$TOOLKIT_ROOT/install.sh" --update "$SCRATCH" > "$SCRATCH/.update.log"
if ! grep -qE "removed .claude/skills/" "$SCRATCH/.update.log"; then
  echo "FAIL: --update did not run the sync wipe block" >&2
  exit 1
fi
if ! grep -qE "wiped [0-9]+ managed dir\(s\); rebuilding from source" "$SCRATCH/.update.log"; then
  echo "FAIL: --update did not emit summary line" >&2
  exit 1
fi
# After --update, all expected files must exist again
for p in "${expected[@]}"; do
  if [[ ! -e "$SCRATCH/$p" ]]; then
    echo "FAIL: --update did not recreate $p" >&2
    exit 1
  fi
done

# ── --no-pre-push-hook: skips hook installation cleanly ─────────────────────
echo "==> --no-pre-push-hook"
NOHOOK="$(mktemp -d)"
git -C "$NOHOOK" init -q -b main
bash "$TOOLKIT_ROOT/install.sh" --no-pre-push-hook "$NOHOOK" > "$NOHOOK/.install.log"
if [[ -e "$NOHOOK/.git/hooks/pre-push" ]]; then
  echo "FAIL: --no-pre-push-hook installed the hook anyway" >&2
  rm -rf "$NOHOOK"
  exit 1
fi
if ! grep -qF "skipping pre-push hook (--no-pre-push-hook)" "$NOHOOK/.install.log"; then
  echo "FAIL: --no-pre-push-hook did not log skip message" >&2
  rm -rf "$NOHOOK"
  exit 1
fi
rm -rf "$NOHOOK"

# ── --no-legacy-cleanup: suppresses the v0.9.0 legacy-cleanup prompt ────────
# v0.9.0 removed gemini-cli host; the installer detects pre-existing
# .agents/skills/<name>/ from a prior install and offers backup+remove with
# operator confirmation. The --no-legacy-cleanup flag suppresses the prompt
# entirely for CI / scripted installs. Test: seed .agents/skills/<known>/,
# run installer with --no-legacy-cleanup, confirm prompt suppressed +
# legacy dir left as-is.
echo "==> --no-legacy-cleanup (v0.9.0)"
LEGACY="$(mktemp -d)"
git -C "$LEGACY" init -q -b main
mkdir -p "$LEGACY/.agents/skills/design"
echo "fake legacy skill" > "$LEGACY/.agents/skills/design/SKILL.md"
bash "$TOOLKIT_ROOT/install.sh" --no-legacy-cleanup "$LEGACY" > "$LEGACY/.install.log"
if grep -qF "legacy gemini-cli cleanup" "$LEGACY/.install.log"; then
  echo "FAIL: --no-legacy-cleanup did not suppress the cleanup prompt" >&2
  rm -rf "$LEGACY"
  exit 1
fi
if [[ ! -e "$LEGACY/.agents/skills/design/SKILL.md" ]]; then
  echo "FAIL: --no-legacy-cleanup deleted/moved legacy .agents/skills/design/ (should leave untouched)" >&2
  rm -rf "$LEGACY"
  exit 1
fi
rm -rf "$LEGACY"

# ── /memory save end-to-end test (plan #7a part 1 task 2) ──────────────────
# Exercise scripts/save.py via its CLI to verify the canonical Python save
# primitive works post-install. Tests: positive save with frontmatter +
# --always-load routing + collision detection + slug validation. Uses the
# scratch dir as a mock vault root.
echo "==> /memory save end-to-end test (plan #7a part 1 task 2)"
MSAVE="$(mktemp -d)"
SAVE_PY="$SCRATCH/.claude/skills/memory/scripts/save.py"
if [[ ! -f "$SAVE_PY" ]]; then
  echo "FAIL: save.py not installed at $SAVE_PY (smoke install expected-files should have caught this earlier)" >&2
  rm -rf "$MSAVE"
  exit 1
fi
# Positive: basic save with tags
SAVE_OUT="$(echo "Test entry body." | python3 "$SAVE_PY" preferences smoke-test-positive --vault-path "$MSAVE" --tags "smoke,test" 2>/dev/null)"
EXPECTED="$MSAVE/personal-private/preferences/smoke-test-positive.md"
if [[ "$SAVE_OUT" != "$EXPECTED" ]]; then
  echo "FAIL: save.py CLI returned $SAVE_OUT, expected $EXPECTED" >&2
  rm -rf "$MSAVE"
  exit 1
fi
if [[ ! -f "$EXPECTED" ]]; then
  echo "FAIL: save.py did not create $EXPECTED" >&2
  rm -rf "$MSAVE"
  exit 1
fi
if ! grep -qE "^kind: preferences$" "$EXPECTED"; then
  echo "FAIL: save.py output missing 'kind: preferences' frontmatter" >&2
  rm -rf "$MSAVE"
  exit 1
fi
if ! grep -qE "^always_load: false$" "$EXPECTED"; then
  echo "FAIL: save.py output missing 'always_load: false' frontmatter" >&2
  rm -rf "$MSAVE"
  exit 1
fi
# Positive: --always-load routes to _always-load/
echo "Always-load body." | python3 "$SAVE_PY" preferences smoke-test-al --vault-path "$MSAVE" --always-load >/dev/null 2>&1
AL_PATH="$MSAVE/personal-private/_always-load/smoke-test-al.md"
if [[ ! -f "$AL_PATH" ]]; then
  echo "FAIL: --always-load did not route to _always-load/ (expected $AL_PATH)" >&2
  rm -rf "$MSAVE"
  exit 1
fi
if ! grep -qE "^always_load: true$" "$AL_PATH"; then
  echo "FAIL: --always-load entry missing 'always_load: true' frontmatter" >&2
  rm -rf "$MSAVE"
  exit 1
fi
# Negative: collision should error non-zero
if echo "x" | python3 "$SAVE_PY" preferences smoke-test-positive --vault-path "$MSAVE" >/dev/null 2>&1; then
  echo "FAIL: save.py allowed overwriting an existing entry (collision check broken)" >&2
  rm -rf "$MSAVE"
  exit 1
fi
# Negative: invalid slug should error non-zero
if echo "x" | python3 "$SAVE_PY" preferences "Bad_Slug" --vault-path "$MSAVE" >/dev/null 2>&1; then
  echo "FAIL: save.py allowed non-kebab-case slug (validator broken)" >&2
  rm -rf "$MSAVE"
  exit 1
fi
rm -rf "$MSAVE"

# ── /memory evolve end-to-end test (plan #7a part 1 task 3) ────────────────
# Exercise scripts/evolve.py via its CLI to verify atomic archive-and-replace.
# Tests: in-place evolve + rename evolve + missing-entry negative +
# already-superseded negative + empty-reason negative.
echo "==> /memory evolve end-to-end test (plan #7a part 1 task 3)"
MEVOL="$(mktemp -d)"
SAVE_PY="$SCRATCH/.claude/skills/memory/scripts/save.py"
EVOLVE_PY="$SCRATCH/.claude/skills/memory/scripts/evolve.py"
if [[ ! -f "$EVOLVE_PY" ]]; then
  echo "FAIL: evolve.py not installed at $EVOLVE_PY" >&2
  rm -rf "$MEVOL"
  exit 1
fi
# Setup: save an entry to evolve
echo "Original body for in-place evolve." | python3 "$SAVE_PY" preferences smoke-evolve-ip --vault-path "$MEVOL" 2>/dev/null > /dev/null
# Test 1: in-place evolve
EVOL_OUT="$(echo "Evolved body." | python3 "$EVOLVE_PY" personal-private/preferences/smoke-evolve-ip.md "test in-place evolve" --vault-path "$MEVOL" 2>/dev/null)"
# Output is tab-separated <new-path>\t<archive-path>
NEW_PATH="$(echo "$EVOL_OUT" | cut -f1)"
ARCH_PATH="$(echo "$EVOL_OUT" | cut -f2)"
if [[ ! -f "$NEW_PATH" ]]; then
  echo "FAIL: evolve.py did not create new entry at $NEW_PATH" >&2
  rm -rf "$MEVOL"
  exit 1
fi
if [[ ! -f "$ARCH_PATH" ]]; then
  echo "FAIL: evolve.py did not create archive at $ARCH_PATH" >&2
  rm -rf "$MEVOL"
  exit 1
fi
# Active entry should have supersedes:
if ! grep -qE "^supersedes: personal-private/_archive/" "$NEW_PATH"; then
  echo "FAIL: active entry missing 'supersedes:' frontmatter pointing at archive" >&2
  rm -rf "$MEVOL"
  exit 1
fi
# Active entry status should be active
if ! grep -qE "^status: active$" "$NEW_PATH"; then
  echo "FAIL: active entry missing 'status: active'" >&2
  rm -rf "$MEVOL"
  exit 1
fi
# Archive should have superseded fields
if ! grep -qE "^status: superseded$" "$ARCH_PATH"; then
  echo "FAIL: archive missing 'status: superseded'" >&2
  rm -rf "$MEVOL"
  exit 1
fi
if ! grep -qE "^superseded_by: personal-private/preferences/smoke-evolve-ip" "$ARCH_PATH"; then
  echo "FAIL: archive missing 'superseded_by:' cross-link" >&2
  rm -rf "$MEVOL"
  exit 1
fi
if ! grep -qE "^superseded_reason:" "$ARCH_PATH"; then
  echo "FAIL: archive missing 'superseded_reason:'" >&2
  rm -rf "$MEVOL"
  exit 1
fi
# Test 2: rename evolve
echo "Original body for rename evolve." | python3 "$SAVE_PY" preferences smoke-evolve-rename --vault-path "$MEVOL" 2>/dev/null > /dev/null
echo "Renamed body." | python3 "$EVOLVE_PY" personal-private/preferences/smoke-evolve-rename.md "test rename" --new-slug smoke-evolve-renamed --vault-path "$MEVOL" 2>/dev/null > /dev/null
if [[ -f "$MEVOL/personal-private/preferences/smoke-evolve-rename.md" ]]; then
  echo "FAIL: rename evolve left old entry at original path (should be unlinked)" >&2
  rm -rf "$MEVOL"
  exit 1
fi
if [[ ! -f "$MEVOL/personal-private/preferences/smoke-evolve-renamed.md" ]]; then
  echo "FAIL: rename evolve did not create new entry at new slug" >&2
  rm -rf "$MEVOL"
  exit 1
fi
# Test 3: negative — missing entry
if echo "x" | python3 "$EVOLVE_PY" personal-private/preferences/nonexistent.md "test" --vault-path "$MEVOL" >/dev/null 2>&1; then
  echo "FAIL: evolve.py allowed missing entry (should error non-zero)" >&2
  rm -rf "$MEVOL"
  exit 1
fi
# Test 4: negative — already-superseded
TODAY_COMPACT="$(date +%Y%m%d)"
SUPERSEDED_PATH="personal-private/_archive/personal-private/preferences/smoke-evolve-ip.md.${TODAY_COMPACT}.md"
if echo "x" | python3 "$EVOLVE_PY" "$SUPERSEDED_PATH" "test" --vault-path "$MEVOL" >/dev/null 2>&1; then
  echo "FAIL: evolve.py allowed evolving already-superseded entry (status check broken)" >&2
  rm -rf "$MEVOL"
  exit 1
fi
# Test 5: negative — empty reason
if echo "x" | python3 "$EVOLVE_PY" personal-private/preferences/smoke-evolve-ip.md "" --vault-path "$MEVOL" >/dev/null 2>&1; then
  echo "FAIL: evolve.py allowed empty reason (reason check broken)" >&2
  rm -rf "$MEVOL"
  exit 1
fi
rm -rf "$MEVOL"

# ── embedding queue + vec-index wiring test (plan #7a part 1 task 4) ───────
# Verify save.py / evolve.py enqueue to <vault>/_meta/embedding-queue.jsonl
# + drain operates gracefully whether sqlite-vec is installed or not. Full
# happy-path (index populated, queue drained to zero) only runs if
# sqlite-vec + enable_load_extension are both available — graceful-skip
# otherwise (catches Apple system Python's missing enable_load_extension).
echo "==> embedding queue + vec-index wiring test (plan #7a part 1 task 4)"
MQUEUE="$(mktemp -d)"
SAVE_PY="$SCRATCH/.claude/skills/memory/scripts/save.py"
EVOLVE_PY="$SCRATCH/.claude/skills/memory/scripts/evolve.py"
EMBED_PY="$SCRATCH/.claude/skills/memory/scripts/embed.py"
VEC_PY="$SCRATCH/.claude/skills/memory/scripts/vec_index.py"
for f in "$EMBED_PY" "$VEC_PY"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL: $f not installed (expected-files should have caught this)" >&2
    rm -rf "$MQUEUE"
    exit 1
  fi
done
# Verify embed.py stub mode produces deterministic 384-d output.
EMBED_OUT="$(python3 "$EMBED_PY" "smoke test text" --mode stub 2>/dev/null)"
EMBED_LEN="$(echo "$EMBED_OUT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)"
if [[ "$EMBED_LEN" != "384" ]]; then
  echo "FAIL: embed.py stub mode returned $EMBED_LEN-d output, expected 384" >&2
  rm -rf "$MQUEUE"
  exit 1
fi
# Save 3 entries; queue should grow by 3.
for i in 1 2 3; do
  echo "Body $i for queue test." | python3 "$SAVE_PY" preferences "queue-test-$i" --vault-path "$MQUEUE" >/dev/null 2>&1
done
QUEUE_FILE="$MQUEUE/_meta/embedding-queue.jsonl"
if [[ ! -f "$QUEUE_FILE" ]]; then
  echo "FAIL: embedding queue file not created after 3 saves" >&2
  rm -rf "$MQUEUE"
  exit 1
fi
QUEUE_LINES="$(wc -l < "$QUEUE_FILE" | tr -d ' ')"
if [[ "$QUEUE_LINES" != "3" ]]; then
  echo "FAIL: expected 3 queue entries after 3 saves, got $QUEUE_LINES" >&2
  rm -rf "$MQUEUE"
  exit 1
fi
# Each line should be valid JSON with op=upsert.
if ! grep -qE '"op": "upsert"' "$QUEUE_FILE"; then
  echo "FAIL: queue entries missing 'op': 'upsert' field" >&2
  rm -rf "$MQUEUE"
  exit 1
fi
# Drain in stub mode. Outcome depends on sqlite-vec availability:
DRAIN_OUT="$(python3 "$VEC_PY" --vault-path "$MQUEUE" drain --mode stub 2>/dev/null)"
PROCESSED="$(echo "$DRAIN_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['processed'])" 2>/dev/null || echo 0)"
SKIPPED="$(echo "$DRAIN_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['skipped'])" 2>/dev/null || echo 0)"
# Either processed==3 (sqlite-vec available) OR skipped==3 (graceful-skip).
# Both are valid; reject other outcomes (e.g. errors > 0).
ERRORS="$(echo "$DRAIN_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['errors'])" 2>/dev/null || echo 99)"
if [[ "$ERRORS" != "0" ]]; then
  echo "FAIL: drain reported $ERRORS errors; should be 0 even when sqlite-vec absent (graceful-skip)" >&2
  echo "    drain output: $DRAIN_OUT" >&2
  rm -rf "$MQUEUE"
  exit 1
fi
if [[ "$PROCESSED" == "3" ]]; then
  # Full happy path: sqlite-vec available; index should now have 3 entries.
  SIZE_OUT="$(python3 "$VEC_PY" --vault-path "$MQUEUE" size 2>/dev/null)"
  SIZE_N="$(echo "$SIZE_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('size') or 0)" 2>/dev/null || echo 0)"
  if [[ "$SIZE_N" != "3" ]]; then
    echo "FAIL: drain processed 3 but index size is $SIZE_N (expected 3)" >&2
    rm -rf "$MQUEUE"
    exit 1
  fi
  # Queue file should be gone after successful drain.
  if [[ -f "$QUEUE_FILE" ]]; then
    echo "FAIL: queue file still exists after full drain (should be removed when remaining==0)" >&2
    rm -rf "$MQUEUE"
    exit 1
  fi
  echo "    (sqlite-vec available — verified full happy path: 3 saves → 3 indexed → queue empty)"
elif [[ "$SKIPPED" == "3" ]]; then
  # Graceful-skip path: sqlite-vec unavailable; queue stays + index is null.
  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "FAIL: queue file removed despite graceful-skip (should remain pending)" >&2
    rm -rf "$MQUEUE"
    exit 1
  fi
  echo "    (sqlite-vec unavailable — verified graceful-skip: 3 saves queued, drain skipped, queue intact)"
else
  echo "FAIL: drain produced unexpected outcome (processed=$PROCESSED, skipped=$SKIPPED, errors=$ERRORS)" >&2
  echo "    drain output: $DRAIN_OUT" >&2
  rm -rf "$MQUEUE"
  exit 1
fi
# Verify file write is never blocked even with no embedding mode available.
# Save with MEMORY_USE_API_EMBEDDINGS=true but no API key — save still works.
unset ANTHROPIC_API_KEY VOYAGE_API_KEY MEMORY_USE_API_EMBEDDINGS
echo "No-API body." | python3 "$SAVE_PY" preferences no-api-test --vault-path "$MQUEUE" >/dev/null 2>&1
if [[ ! -f "$MQUEUE/personal-private/preferences/no-api-test.md" ]]; then
  echo "FAIL: save failed when no embedding mode available (file write should NEVER be blocked)" >&2
  rm -rf "$MQUEUE"
  exit 1
fi
rm -rf "$MQUEUE"

# ── validate-manifests negative test: gemini-cli should error with v0.9.0 msg ─
# Manifest containing 'gemini-cli' in supported_hosts must error with a clear
# message pointing at the v0.9.0 CHANGELOG. Catches regressions if HOST_ENUM
# ever re-admits gemini-cli or if REMOVED_HOSTS messaging breaks.
echo "==> validate-manifests negative test (gemini-cli rejected)"
VNEG="$(mktemp -d)"
mkdir -p "$VNEG/skills/test-gemini-cli-rejected"
cat > "$VNEG/skills/test-gemini-cli-rejected/SKILL.md" << 'NEG_EOF'
---
name: test-gemini-cli-rejected
description: Negative-test fixture — validate-manifests must reject this manifest because gemini-cli was removed in v0.9.0.
kind: skill
supported_hosts: [claude-code, antigravity, gemini-cli]
version: 0.1.0
install_scope: project
---
NEG_EOF
# Inline-invoke the validator's check function via a small driver script so
# we test in isolation (don't pollute the real validator's exit code).
VNEG_OUTPUT="$(python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('vm', '$TOOLKIT_ROOT/scripts/validate-manifests.py')
vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm)
from pathlib import Path
# Override ROOT so err() can compute relative paths against the fixture dir
vm.ROOT = Path('$VNEG')
p = Path('$VNEG/skills/test-gemini-cli-rejected/SKILL.md')
fm = vm.parse_frontmatter(p)
vm.require_supported_hosts(p, fm)
print('ERRORS:', len(vm.errors))
for issue in vm.errors:
    print('MSG:', issue)
" 2>&1)"
if ! echo "$VNEG_OUTPUT" | grep -qE "removed host 'gemini-cli'"; then
  echo "FAIL: validator did not emit 'removed host gemini-cli' message for fixture with gemini-cli in supported_hosts" >&2
  echo "Output was:" >&2
  echo "$VNEG_OUTPUT" >&2
  rm -rf "$VNEG"
  exit 1
fi
if ! echo "$VNEG_OUTPUT" | grep -qE "v0.9.0"; then
  echo "FAIL: validator's error message does not mention v0.9.0 (no actionable next-step text)" >&2
  echo "Output was:" >&2
  echo "$VNEG_OUTPUT" >&2
  rm -rf "$VNEG"
  exit 1
fi
rm -rf "$VNEG"

# ── post-install integrity ──────────────────────────────────────────────────
echo "==> post-install integrity"
bash "$TOOLKIT_ROOT/scripts/check-integrity-bash.sh" "$SCRATCH"

echo "==> smoke-install-bash: OK"
