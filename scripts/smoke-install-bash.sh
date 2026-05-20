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
bash "$TOOLKIT_ROOT/install.sh" --no-python-deps "$SCRATCH" > "$SCRATCH/.install.log"

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
  .claude/skills/memory/scripts/recall.py
  .claude/skills/memory/scripts/reflect.py
  .claude/skills/memory/scripts/permeable_boundary.py
  .claude/skills/memory/scripts/ideas_surface.py
  .claude/skills/memory/scripts/ideas_incubator.py
  .claude/skills/memory/scripts/ideas_promote.py
  .agent/skills/memory/SKILL.md
  .agent/skills/memory/scripts/save.py
  .agent/skills/memory/scripts/evolve.py
  .agent/skills/memory/scripts/embed.py
  .agent/skills/memory/scripts/vec_index.py
  .agent/skills/memory/scripts/recall.py
  .agent/skills/memory/scripts/reflect.py
  .agent/skills/memory/scripts/permeable_boundary.py
  .agent/skills/memory/scripts/ideas_surface.py
  .agent/skills/memory/scripts/ideas_incubator.py
  .agent/skills/memory/scripts/ideas_promote.py
  # Standalone agent: evaluator — claude-code is single-file destination;
  # antigravity wraps the agent as a skill. (gemini-cli destination
  # .gemini/agents/evaluator.md removed in v0.9.0.) memory-idea-researcher
  # added in plan #7a part 4 task 3 (deep-research worker for idea-incubator).
  .claude/agents/evaluator.md
  .agent/skills/evaluator/SKILL.md
  .claude/agents/memory-idea-researcher.md
  .agent/skills/memory-idea-researcher/SKILL.md
  # Standalone hooks — claude-code only (v0.7.0); memory-recall hooks
  # added in plan #7a part 2; memory-reflect-{stop,idle} added in plan
  # #7a part 3.
  .claude/hooks/kill-switch.sh
  .claude/hooks/steer.sh
  .claude/hooks/commit-on-stop.sh
  .claude/hooks/memory-recall-session-start.sh
  .claude/hooks/memory-recall-prompt-submit.sh
  .claude/hooks/memory-reflect-stop.sh
  .claude/hooks/memory-reflect-idle.sh
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
bash "$TOOLKIT_ROOT/install.sh" --no-python-deps "$SCRATCH" > "$SCRATCH/.rerun.log"
if grep -qE "created .claude/skills/(example-skill|pii-scrubber)" "$SCRATCH/.rerun.log"; then
  echo "FAIL: re-run recreated a skill that already existed (should be 'kept')" >&2
  exit 1
fi
if grep -qE "created .claude/agents/(evaluator|memory-idea-researcher)" "$SCRATCH/.rerun.log"; then
  echo "FAIL: re-run recreated an agent that already existed (should be 'kept')" >&2
  exit 1
fi
# Same for hooks: re-run should not "create" scripts that already exist.
if grep -qE "created .claude/hooks/(kill-switch|steer|commit-on-stop|memory-recall-session-start|memory-recall-prompt-submit|memory-reflect-stop|memory-reflect-idle)" "$SCRATCH/.rerun.log"; then
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
bash "$TOOLKIT_ROOT/install.sh" --update --no-python-deps "$SCRATCH" > "$SCRATCH/.update.log"
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
bash "$TOOLKIT_ROOT/install.sh" --no-pre-push-hook --no-python-deps "$NOHOOK" > "$NOHOOK/.install.log"
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
bash "$TOOLKIT_ROOT/install.sh" --no-legacy-cleanup --no-python-deps "$LEGACY" > "$LEGACY/.install.log"
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
# Verify embed.py stub mode produces deterministic 1024-d output
# (BGE-large native; bumped from 384 in v0.9.2 per plan #18 task 1).
EMBED_OUT="$(python3 "$EMBED_PY" "smoke test text" --mode stub 2>/dev/null)"
EMBED_LEN="$(echo "$EMBED_OUT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)"
if [[ "$EMBED_LEN" != "1024" ]]; then
  echo "FAIL: embed.py stub mode returned $EMBED_LEN-d output, expected 1024" >&2
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

# Rebuild subcommand test (plan #18 task 2): drop + recreate at current
# EMBEDDING_DIM. Outcome again depends on sqlite-vec availability.
# Note: capture exit code via `|| REBUILD_EXIT=$?` form so `set -e` doesn't
# kill the script on the expected exit-2 graceful-skip path.
REBUILD_EXIT=0
REBUILD_OUT="$(python3 "$VEC_PY" --vault-path "$MQUEUE" rebuild 2>/dev/null)" || REBUILD_EXIT=$?
if [[ $REBUILD_EXIT -eq 0 ]]; then
  # Full happy path: rebuild reports old_dim + new_dim=1024.
  NEW_DIM="$(echo "$REBUILD_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('new_dim'))")"
  if [[ "$NEW_DIM" != "1024" ]]; then
    echo "FAIL: rebuild new_dim should be 1024, got '$NEW_DIM'" >&2
    echo "    output: $REBUILD_OUT" >&2
    rm -rf "$MQUEUE"
    exit 1
  fi
  echo "    (rebuild succeeded — new_dim=1024 confirmed)"
elif [[ $REBUILD_EXIT -eq 2 ]]; then
  # Graceful-skip: sqlite-vec unavailable. Output should mention "skipped".
  if ! echo "$REBUILD_OUT" | grep -q '"skipped"'; then
    echo "FAIL: rebuild graceful-skip output missing 'skipped' marker" >&2
    echo "    output: $REBUILD_OUT" >&2
    rm -rf "$MQUEUE"
    exit 1
  fi
  echo "    (rebuild graceful-skip — sqlite-vec unavailable)"
else
  echo "FAIL: rebuild exited $REBUILD_EXIT (expected 0 or 2)" >&2
  echo "    output: $REBUILD_OUT" >&2
  rm -rf "$MQUEUE"
  exit 1
fi

# Dim-mismatch detection test (plan #18 task 2): the _detect_index_dim
# regex parses the CREATE statement; verify it returns the expected
# dim for a synthetic CREATE string. Pure-regex test — no sqlite-vec
# required.
DIM_TEST_OUT="$(python3 -c "
import sys
sys.path.insert(0, '$SCRATCH/.claude/skills/memory/scripts')
from vec_index import _DIM_REGEX
import re
samples = [
    ('CREATE VIRTUAL TABLE entries USING vec0(embedding FLOAT[384])', 384),
    ('CREATE VIRTUAL TABLE entries USING vec0(embedding FLOAT[1024])', 1024),
    ('CREATE TABLE entry_meta (rowid INTEGER PRIMARY KEY)', None),
]
for sql, expected in samples:
    m = _DIM_REGEX.search(sql)
    got = int(m.group(1)) if m else None
    if got != expected:
        print(f'FAIL: expected={expected}, got={got}, sql={sql!r}')
        sys.exit(1)
print('OK')
")"
if [[ "$DIM_TEST_OUT" != "OK" ]]; then
  echo "FAIL: _DIM_REGEX parsing test failed: $DIM_TEST_OUT" >&2
  rm -rf "$MQUEUE"
  exit 1
fi
echo "    (dim-mismatch detection regex verified)"

# Verify file write is never blocked even with no embedding mode available.
# Save with no sentence-transformers installed (local mode unavailable) —
# save still works because the embedding is async + graceful-skip.
echo "No-embed body." | python3 "$SAVE_PY" preferences no-embed-test --vault-path "$MQUEUE" >/dev/null 2>&1
if [[ ! -f "$MQUEUE/personal-private/preferences/no-embed-test.md" ]]; then
  echo "FAIL: save failed when no embedding mode available (file write should NEVER be blocked)" >&2
  rm -rf "$MQUEUE"
  exit 1
fi
rm -rf "$MQUEUE"

# ── SessionStart recall hook end-to-end test (plan #7a part 2 task 1) ──────
# Verify the SessionStart hook lands the script + settings.json registration,
# then exercise recall.py session-start against a scratch vault to confirm
# the read loop works end-to-end.
echo "==> SessionStart recall hook end-to-end test (plan #7a part 2 task 1)"
RECALL_PY="$SCRATCH/.claude/skills/memory/scripts/recall.py"
HOOK_SH="$SCRATCH/.claude/hooks/memory-recall-session-start.sh"
SETTINGS_JSON="$SCRATCH/.claude/settings.json"
if [[ ! -f "$RECALL_PY" ]]; then
  echo "FAIL: recall.py not installed at $RECALL_PY" >&2
  exit 1
fi
if [[ ! -x "$HOOK_SH" ]]; then
  echo "FAIL: hook script $HOOK_SH not executable" >&2
  exit 1
fi
# settings.json must contain a SessionStart hook entry naming our script.
if ! grep -qE '"SessionStart"' "$SETTINGS_JSON"; then
  echo "FAIL: settings.json missing 'SessionStart' key after install" >&2
  cat "$SETTINGS_JSON" >&2
  exit 1
fi
if ! grep -qE 'memory-recall-session-start\.sh' "$SETTINGS_JSON"; then
  echo "FAIL: settings.json SessionStart entry doesn't reference memory-recall-session-start.sh" >&2
  cat "$SETTINGS_JSON" >&2
  exit 1
fi
# End-to-end: seed a scratch vault with 2 always-load entries + 1 superseded;
# run recall.py session-start; verify output + transparency line + superseded filter.
MRECALL="$(mktemp -d)"
mkdir -p "$MRECALL/personal-private/_always-load"
cat > "$MRECALL/personal-private/_always-load/pref-a.md" << 'AL_EOF'
---
kind: preferences
status: active
slug: pref-a
tags: [test]
---
First always-load body.
AL_EOF
cat > "$MRECALL/personal-private/_always-load/pref-b.md" << 'AL_EOF'
---
kind: workflow
status: active
slug: pref-b
tags: [test]
---
Second always-load body.
AL_EOF
cat > "$MRECALL/personal-private/_always-load/superseded-entry.md" << 'AL_EOF'
---
kind: preferences
status: superseded
slug: superseded-entry
---
Should be filtered.
AL_EOF
# Run recall.py session-start; capture stdout + stderr separately.
RECALL_STDOUT="$(python3 "$RECALL_PY" --vault-path "$MRECALL" session-start 2>/tmp/recall-stderr.log)"
RECALL_STDERR="$(cat /tmp/recall-stderr.log)"
rm -f /tmp/recall-stderr.log
# Transparency line on stderr must report 2 entries (superseded filtered).
if ! echo "$RECALL_STDERR" | grep -qE "Loaded 2 MemoryVault always-load entries"; then
  echo "FAIL: stderr transparency line missing or wrong count (expected 2 entries)" >&2
  echo "    stderr was: $RECALL_STDERR" >&2
  rm -rf "$MRECALL"
  exit 1
fi
# Stdout must contain both pref-a and pref-b but NOT superseded-entry.
if ! echo "$RECALL_STDOUT" | grep -qE "pref-a"; then
  echo "FAIL: stdout missing pref-a entry" >&2
  rm -rf "$MRECALL"
  exit 1
fi
if ! echo "$RECALL_STDOUT" | grep -qE "pref-b"; then
  echo "FAIL: stdout missing pref-b entry" >&2
  rm -rf "$MRECALL"
  exit 1
fi
if echo "$RECALL_STDOUT" | grep -qE "superseded-entry"; then
  echo "FAIL: stdout contains superseded entry (should be filtered)" >&2
  rm -rf "$MRECALL"
  exit 1
fi
# Header line should be present.
if ! echo "$RECALL_STDOUT" | grep -qE "^# MemoryVault — always-load entries$"; then
  echo "FAIL: stdout missing header line" >&2
  rm -rf "$MRECALL"
  exit 1
fi
# Graceful-skip: no MEMORY_VAULT_PATH → exit 0, no output.
NOVAULT_STDOUT="$(unset MEMORY_VAULT_PATH; python3 "$RECALL_PY" session-start 2>/dev/null)"
if [[ -n "$NOVAULT_STDOUT" ]]; then
  echo "FAIL: recall.py emitted stdout despite no vault configured (should be silent graceful-skip)" >&2
  echo "    stdout was: $NOVAULT_STDOUT" >&2
  rm -rf "$MRECALL"
  exit 1
fi
# Graceful-skip: vault path doesn't exist → exit 0 with warning on stderr.
BADVAULT_STDOUT="$(python3 "$RECALL_PY" --vault-path "/nonexistent/path/$$" session-start 2>/dev/null)"
BADVAULT_EXIT=$?
if [[ $BADVAULT_EXIT -ne 0 ]]; then
  echo "FAIL: recall.py exited non-zero for nonexistent vault (should be graceful exit 0)" >&2
  rm -rf "$MRECALL"
  exit 1
fi
# Empty _always-load: exit 0, "Loaded 0" transparency line.
MEMPTY="$(mktemp -d)"
EMPTY_STDERR="$(python3 "$RECALL_PY" --vault-path "$MEMPTY" session-start 2>&1 >/dev/null)"
if ! echo "$EMPTY_STDERR" | grep -qE "Loaded 0 MemoryVault always-load entries"; then
  echo "FAIL: empty vault did not emit 'Loaded 0' transparency line" >&2
  echo "    stderr was: $EMPTY_STDERR" >&2
  rm -rf "$MEMPTY" "$MRECALL"
  exit 1
fi
rm -rf "$MEMPTY" "$MRECALL"

# ── UserPromptSubmit recall hook end-to-end test (plan #7a part 2 task 2) ──
# Verify the UserPromptSubmit hook lands the script + settings.json
# registration, then exercise recall.py prompt-submit against a scratch vault
# + JSON payload to confirm the scaffold wiring works end-to-end. The actual
# recall engine lands in task 3; for now we verify the hook contract +
# stdin parsing + dedup-set collection + transparency line emission.
echo "==> UserPromptSubmit recall hook end-to-end test (plan #7a part 2 task 2)"
PS_HOOK_SH="$SCRATCH/.claude/hooks/memory-recall-prompt-submit.sh"
if [[ ! -x "$PS_HOOK_SH" ]]; then
  echo "FAIL: hook script $PS_HOOK_SH not executable" >&2
  exit 1
fi
# settings.json must contain a UserPromptSubmit hook entry naming our script.
if ! grep -qE '"UserPromptSubmit"' "$SETTINGS_JSON"; then
  echo "FAIL: settings.json missing 'UserPromptSubmit' key after install" >&2
  cat "$SETTINGS_JSON" >&2
  exit 1
fi
if ! grep -qE 'memory-recall-prompt-submit\.sh' "$SETTINGS_JSON"; then
  echo "FAIL: settings.json UserPromptSubmit entry doesn't reference memory-recall-prompt-submit.sh" >&2
  cat "$SETTINGS_JSON" >&2
  exit 1
fi
# End-to-end: seed a scratch vault with 1 always-load entry (no other
# entries — keeps the test focused on hook contract + graceful-skip paths;
# the recall engine itself is exercised by the task 3 smoke test below).
# Verify exit 0 + transparency line ("Loaded N relevant entries") emitted.
MPSUBMIT="$(mktemp -d)"
mkdir -p "$MPSUBMIT/personal-private/_always-load"
cat > "$MPSUBMIT/personal-private/_always-load/seeded-pref.md" << 'PS_EOF'
---
kind: preferences
status: active
slug: seeded-pref
---
Seeded body.
PS_EOF
PS_PAYLOAD='{"hookEventName":"UserPromptSubmit","prompt":"how do I evolve a memory entry"}'
PS_STDOUT="$(echo "$PS_PAYLOAD" | python3 "$RECALL_PY" --vault-path "$MPSUBMIT" prompt-submit 2>/tmp/ps-stderr.log)"
PS_STDERR="$(cat /tmp/ps-stderr.log)"
PS_EXIT=$?
rm -f /tmp/ps-stderr.log
if [[ $PS_EXIT -ne 0 ]]; then
  echo "FAIL: prompt-submit exited non-zero ($PS_EXIT)" >&2
  rm -rf "$MPSUBMIT"
  exit 1
fi
# Transparency line: real "Loaded N relevant entries" line (task 3 wired engine).
# With only 1 always-load entry seeded and no other entries in the vault,
# the result count should be 0 (always-load is deduped + no other matches).
if ! echo "$PS_STDERR" | grep -qE "memory-recall-prompt-submit.*Loaded [0-9]+ relevant entries"; then
  echo "FAIL: stderr transparency line missing 'Loaded N relevant entries' shape" >&2
  echo "    stderr was: $PS_STDERR" >&2
  rm -rf "$MPSUBMIT"
  exit 1
fi
# Graceful: empty stdin → "no prompt on stdin" + exit 0
EMPTY_STDIN_OUT="$(echo -n "" | python3 "$RECALL_PY" --vault-path "$MPSUBMIT" prompt-submit 2>&1)"
EMPTY_EXIT=$?
if [[ $EMPTY_EXIT -ne 0 ]]; then
  echo "FAIL: empty stdin produced non-zero exit ($EMPTY_EXIT) — should be graceful 0" >&2
  rm -rf "$MPSUBMIT"
  exit 1
fi
if ! echo "$EMPTY_STDIN_OUT" | grep -qE "no prompt on stdin"; then
  echo "FAIL: empty stdin did not emit 'no prompt on stdin' graceful warning" >&2
  rm -rf "$MPSUBMIT"
  exit 1
fi
# Graceful: malformed JSON → "no prompt on stdin" + exit 0
BAD_JSON_OUT="$(echo '{not json' | python3 "$RECALL_PY" --vault-path "$MPSUBMIT" prompt-submit 2>&1)"
BAD_EXIT=$?
if [[ $BAD_EXIT -ne 0 ]]; then
  echo "FAIL: malformed JSON produced non-zero exit ($BAD_EXIT) — should be graceful 0" >&2
  rm -rf "$MPSUBMIT"
  exit 1
fi
if ! echo "$BAD_JSON_OUT" | grep -qE "no prompt on stdin"; then
  echo "FAIL: malformed JSON did not emit graceful warning" >&2
  rm -rf "$MPSUBMIT"
  exit 1
fi
# Graceful: JSON missing 'prompt' field → "no prompt on stdin" + exit 0
NO_PROMPT_OUT="$(echo '{"foo":"bar"}' | python3 "$RECALL_PY" --vault-path "$MPSUBMIT" prompt-submit 2>&1)"
NO_PROMPT_EXIT=$?
if [[ $NO_PROMPT_EXIT -ne 0 ]]; then
  echo "FAIL: missing-prompt JSON produced non-zero exit ($NO_PROMPT_EXIT) — should be graceful 0" >&2
  rm -rf "$MPSUBMIT"
  exit 1
fi
if ! echo "$NO_PROMPT_OUT" | grep -qE "no prompt on stdin"; then
  echo "FAIL: missing-prompt JSON did not emit graceful warning" >&2
  rm -rf "$MPSUBMIT"
  exit 1
fi
# Graceful: no MEMORY_VAULT_PATH + no --vault-path → silent stdout + exit 0
NO_VAULT_PS_OUT="$(unset MEMORY_VAULT_PATH; echo "$PS_PAYLOAD" | python3 "$RECALL_PY" prompt-submit 2>/dev/null)"
if [[ -n "$NO_VAULT_PS_OUT" ]]; then
  echo "FAIL: prompt-submit emitted stdout despite no vault configured" >&2
  rm -rf "$MPSUBMIT"
  exit 1
fi
rm -rf "$MPSUBMIT"

# ── Recall engine end-to-end test (plan #7a part 2 task 3) ─────────────────
# Verify the 5-step recall engine: tokenize / vec search (graceful-skip if
# sqlite-vec missing) / grep+frontmatter parallel / merge via sim×0.7 +
# keyword×0.3 / dedup against always-load + top-K. Uses stub embedding
# mode so the test is deterministic + portable across CI environments
# (the full happy path with populated vec-index runs only when sqlite-vec
# is available; we test the grep path + graceful-skip path here).
echo "==> Recall engine end-to-end test (plan #7a part 2 task 3)"
MQUERY="$(mktemp -d)"
mkdir -p "$MQUERY/personal-private/preferences" \
         "$MQUERY/personal-private/workflow" \
         "$MQUERY/personal-private/_always-load" \
         "$MQUERY/personal-private/_inbox" \
         "$MQUERY/personal-private/_archive"
# Always-load entry (must be deduped against in prompt_submit results)
cat > "$MQUERY/personal-private/_always-load/always-pref.md" << 'Q_EOF'
---
kind: preferences
status: active
slug: always-pref
tags: [evolve]
---
Already in session context.
Q_EOF
# Active entries with distinctive keywords
cat > "$MQUERY/personal-private/preferences/bulleted-status.md" << 'Q_EOF'
---
kind: preferences
status: active
slug: bulleted-status
tags: [status-reports, dev-flow]
---
Use bulleted lists for status reports per task.
Q_EOF
cat > "$MQUERY/personal-private/workflow/evolve-pattern.md" << 'Q_EOF'
---
kind: workflow
status: active
slug: evolve-pattern
tags: [memory, audit-trail]
---
When preferences change, use /memory evolve to preserve audit trail.
Q_EOF
cat > "$MQUERY/personal-private/workflow/release-pair.md" << 'Q_EOF'
---
kind: workflow
status: active
slug: release-pair
tags: [release, coordination]
---
Toolkit and harness ship as coordinated release pairs.
Q_EOF
# Superseded entry (must be filtered out by grep search)
cat > "$MQUERY/personal-private/preferences/superseded-pref.md" << 'Q_EOF'
---
kind: preferences
status: superseded
slug: superseded-pref
tags: [old]
---
This should never surface.
Q_EOF
# Inbox entry (excluded by default; included with --include-inbox)
cat > "$MQUERY/personal-private/_inbox/inbox-idea.md" << 'Q_EOF'
---
kind: idea
status: active
slug: inbox-idea
tags: [evolve, brainstorm]
---
Inbox candidate.
Q_EOF
# Archive entry (always excluded — even outside _archive/, status:superseded)
cat > "$MQUERY/personal-private/_archive/archived-entry.md" << 'Q_EOF'
---
kind: preferences
status: superseded
slug: archived-entry
tags: [release]
---
Archived content.
Q_EOF

# Test 1: query "evolve" returns workflow/evolve-pattern via grep
Q1_OUT="$(python3 "$RECALL_PY" --vault-path "$MQUERY" query "evolve" --mode stub 2>/dev/null)"
if ! echo "$Q1_OUT" | grep -qE "evolve-pattern"; then
  echo "FAIL: query 'evolve' did not return workflow/evolve-pattern" >&2
  echo "    output was: $Q1_OUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
# Test 2: query "status reports bulleted" returns bulleted-status with 3 keyword matches
Q2_OUT="$(python3 "$RECALL_PY" --vault-path "$MQUERY" query "status reports bulleted" --mode stub 2>/dev/null)"
if ! echo "$Q2_OUT" | grep -qE '"slug": "bulleted-status".*"keyword": 3'; then
  echo "FAIL: query 'status reports bulleted' did not return bulleted-status with keyword=3" >&2
  echo "    output was: $Q2_OUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
# Test 3: superseded entries are filtered out by default
Q3_OUT="$(python3 "$RECALL_PY" --vault-path "$MQUERY" query "superseded never surface" --mode stub 2>/dev/null)"
if echo "$Q3_OUT" | grep -qE "superseded-pref"; then
  echo "FAIL: superseded entry surfaced (should be filtered by status check)" >&2
  echo "    output was: $Q3_OUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
# Test 4: _archive/ is always excluded (even non-superseded entries there)
Q4_OUT="$(python3 "$RECALL_PY" --vault-path "$MQUERY" query "archived content release" --mode stub 2>/dev/null)"
if echo "$Q4_OUT" | grep -qE "archived-entry"; then
  echo "FAIL: _archive/ entry surfaced (should be excluded by directory filter)" >&2
  echo "    output was: $Q4_OUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
# Test 5: _inbox/ excluded by default
Q5A_OUT="$(python3 "$RECALL_PY" --vault-path "$MQUERY" query "inbox candidate brainstorm" --mode stub 2>/dev/null)"
if echo "$Q5A_OUT" | grep -qE "inbox-idea"; then
  echo "FAIL: _inbox/ entry surfaced without --include-inbox (should be excluded)" >&2
  echo "    output was: $Q5A_OUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
# Test 6: _inbox/ included with --include-inbox
Q5B_OUT="$(python3 "$RECALL_PY" --vault-path "$MQUERY" query "inbox candidate brainstorm" --include-inbox --mode stub 2>/dev/null)"
if ! echo "$Q5B_OUT" | grep -qE "inbox-idea"; then
  echo "FAIL: --include-inbox did not surface _inbox/ entry" >&2
  echo "    output was: $Q5B_OUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
# Test 7: top-K respected (K=1 returns at most 1 result)
Q7_OUT="$(python3 "$RECALL_PY" --vault-path "$MQUERY" query "release pair coordination" -k 1 --mode stub 2>/dev/null)"
Q7_LINES="$(echo "$Q7_OUT" | wc -l | tr -d ' ')"
if [[ "$Q7_LINES" != "1" ]]; then
  echo "FAIL: -k 1 returned $Q7_LINES results (expected 1)" >&2
  echo "    output was: $Q7_OUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
# Test 8: prompt-submit wires query() AND dedups against always-load.
# Query "evolve" should match always-pref (via tag) + workflow/evolve-pattern;
# prompt-submit must filter out always-pref + return only evolve-pattern.
PS_PAYLOAD='{"hookEventName":"UserPromptSubmit","prompt":"how do I evolve a memory entry"}'
PS_STDOUT="$(echo "$PS_PAYLOAD" | python3 "$RECALL_PY" --vault-path "$MQUERY" prompt-submit 2>/tmp/ps-engine-stderr.log)"
PS_STDERR="$(cat /tmp/ps-engine-stderr.log)"
rm -f /tmp/ps-engine-stderr.log
if ! echo "$PS_STDOUT" | grep -qE "evolve-pattern"; then
  echo "FAIL: prompt-submit did not surface evolve-pattern (engine wiring broken)" >&2
  echo "    stdout was: $PS_STDOUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
if echo "$PS_STDOUT" | grep -qE "always-pref"; then
  echo "FAIL: prompt-submit surfaced always-pref (should be deduped against always-load)" >&2
  echo "    stdout was: $PS_STDOUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
# Transparency line should now report real loaded count, not scaffold marker
if echo "$PS_STDERR" | grep -qE "scaffold"; then
  echo "FAIL: prompt-submit still emits scaffold marker (engine should be wired in task 3)" >&2
  echo "    stderr was: $PS_STDERR" >&2
  rm -rf "$MQUERY"
  exit 1
fi
if ! echo "$PS_STDERR" | grep -qE "Loaded [0-9]+ relevant entries"; then
  echo "FAIL: prompt-submit stderr missing 'Loaded N relevant entries' line" >&2
  echo "    stderr was: $PS_STDERR" >&2
  rm -rf "$MQUERY"
  exit 1
fi
# Test 9: empty query returns no results (token tokenization filters short tokens)
Q9_OUT="$(python3 "$RECALL_PY" --vault-path "$MQUERY" query "x" --mode stub 2>/dev/null)"
if [[ -n "$Q9_OUT" ]]; then
  echo "FAIL: query 'x' (below _MIN_TOKEN_LEN) returned results (expected empty)" >&2
  echo "    output was: $Q9_OUT" >&2
  rm -rf "$MQUERY"
  exit 1
fi
rm -rf "$MQUERY"

# ── Embedding fallback path test (plan #18 task 1 — local-only refactor) ───
# Verify the v0.9.2 local-only design: default → local sentence-transformers;
# stub mode for tests; "api" mode produces a clear error (was dropped in
# v0.9.2 per ADR 0001's 2026-05-20 amendment).
echo "==> Embedding fallback path test (plan #18 task 1)"
EMBED_PY="$SCRATCH/.claude/skills/memory/scripts/embed.py"
# Test A: mode resolution — default → "local"; "api" raises ValueError with
# clear v0.9.2 error message; unknown modes raise generic error.
RESOLVE_DEFAULT="$(python3 -c "
import sys
sys.path.insert(0, '$SCRATCH/.claude/skills/memory/scripts')
from embed import _resolve_mode
print(_resolve_mode(None))
")"
if [[ "$RESOLVE_DEFAULT" != "local" ]]; then
  echo "FAIL: default mode resolution should be 'local', got '$RESOLVE_DEFAULT'" >&2
  exit 1
fi
API_ERR="$(python3 -c "
import sys
sys.path.insert(0, '$SCRATCH/.claude/skills/memory/scripts')
from embed import _resolve_mode
try:
    _resolve_mode('api')
    print('NO_ERROR')
except ValueError as e:
    print(str(e))
")"
if ! echo "$API_ERR" | grep -qE "v0.9.2"; then
  echo "FAIL: 'api' mode should raise ValueError mentioning v0.9.2; got: $API_ERR" >&2
  exit 1
fi
# Test A2: EMBEDDING_DIM is 1024 (BGE-large native; bumped from 384 in v0.9.2)
DIM="$(python3 -c "
import sys
sys.path.insert(0, '$SCRATCH/.claude/skills/memory/scripts')
from embed import EMBEDDING_DIM
print(EMBEDDING_DIM)
")"
if [[ "$DIM" != "1024" ]]; then
  echo "FAIL: EMBEDDING_DIM should be 1024 (BGE-large native), got '$DIM'" >&2
  exit 1
fi
# Test A3: stub mode returns 1024-d deterministic vector
STUB_LEN="$(python3 -c "
import sys, json
sys.path.insert(0, '$SCRATCH/.claude/skills/memory/scripts')
from embed import embed_text
print(len(embed_text('test', mode='stub')))
")"
if [[ "$STUB_LEN" != "1024" ]]; then
  echo "FAIL: stub mode should return 1024-d vector, got $STUB_LEN" >&2
  exit 1
fi
# Test A4: AGENT_TOOLKIT_EMBEDDING_MODEL env var escape hatch works
MODEL_OVERRIDE="$(AGENT_TOOLKIT_EMBEDDING_MODEL=test-model python3 -c "
import sys
sys.path.insert(0, '$SCRATCH/.claude/skills/memory/scripts')
from embed import _resolve_model
print(_resolve_model())
")"
if [[ "$MODEL_OVERRIDE" != "test-model" ]]; then
  echo "FAIL: AGENT_TOOLKIT_EMBEDDING_MODEL override should yield 'test-model', got '$MODEL_OVERRIDE'" >&2
  exit 1
fi
# Test B: embed.py --mode local with no sentence-transformers → graceful
# EmbeddingUnavailable (exit 2 — distinct from generic error exit 1) +
# stderr message with install hint.
# Note: capture exit code via `|| EMBED_LOCAL_EXIT=$?` form so `set -e`
# doesn't kill the script on the expected non-zero.
EMBED_LOCAL_EXIT=0
EMBED_LOCAL_OUT="$(python3 "$EMBED_PY" "test text" --mode local 2>&1)" || EMBED_LOCAL_EXIT=$?
if [[ $EMBED_LOCAL_EXIT -ne 2 ]]; then
  echo "FAIL: embed.py --mode local exited $EMBED_LOCAL_EXIT (expected 2 for graceful EmbeddingUnavailable)" >&2
  echo "    output: $EMBED_LOCAL_OUT" >&2
  exit 1
fi
if ! echo "$EMBED_LOCAL_OUT" | grep -qE "sentence-transformers"; then
  echo "FAIL: embed.py --mode local error missing sentence-transformers install hint" >&2
  echo "    output: $EMBED_LOCAL_OUT" >&2
  exit 1
fi
# Test C: cache dir constant points at ~/.cache/agent-toolkit/sentence-transformers/
CACHE_DIR="$(python3 -c "
import sys
sys.path.insert(0, '$SCRATCH/.claude/skills/memory/scripts')
from embed import _LOCAL_CACHE_DIR
print(_LOCAL_CACHE_DIR)
")"
if [[ "$CACHE_DIR" != *"agent-toolkit/sentence-transformers"* ]]; then
  echo "FAIL: _LOCAL_CACHE_DIR should contain 'agent-toolkit/sentence-transformers', got '$CACHE_DIR'" >&2
  exit 1
fi
# Test D: AGENT_TOOLKIT_SENTENCE_TRANSFORMERS_CACHE env var override works
CUSTOM_CACHE="/tmp/custom-st-cache-$$"
CACHE_OVERRIDE="$(AGENT_TOOLKIT_SENTENCE_TRANSFORMERS_CACHE="$CUSTOM_CACHE" python3 -c "
import sys
sys.path.insert(0, '$SCRATCH/.claude/skills/memory/scripts')
from embed import _LOCAL_CACHE_DIR
print(_LOCAL_CACHE_DIR)
")"
if [[ "$CACHE_OVERRIDE" != "$CUSTOM_CACHE" ]]; then
  echo "FAIL: AGENT_TOOLKIT_SENTENCE_TRANSFORMERS_CACHE env override didn't apply ('$CACHE_OVERRIDE' != '$CUSTOM_CACHE')" >&2
  exit 1
fi
# Test E: recall.py with no sentence-transformers installed → falls back
# to grep-only cleanly (exit 0). This is the "offline + no local model"
# degraded-graceful path. (Post-v0.9.2: there is no API mode to opt
# into, so this test only validates the no-local-model fallback.)
MFB="$(mktemp -d)"
mkdir -p "$MFB/personal-private/workflow"
cat > "$MFB/personal-private/workflow/fb-entry.md" << 'FB_EOF'
---
kind: workflow
status: active
slug: fb-entry
tags: [evolve, fallback]
---
Evolve test body for fallback path.
FB_EOF
FB_OUT="$(python3 "$RECALL_PY" --vault-path "$MFB" query "evolve" 2>&1)"
FB_EXIT=$?
if [[ $FB_EXIT -ne 0 ]]; then
  echo "FAIL: recall.py fallback path exited $FB_EXIT (expected 0 for graceful grep-only)" >&2
  echo "    output: $FB_OUT" >&2
  rm -rf "$MFB"
  exit 1
fi
if ! echo "$FB_OUT" | grep -qE "fb-entry"; then
  echo "FAIL: fallback grep-only path did not return fb-entry" >&2
  echo "    output: $FB_OUT" >&2
  rm -rf "$MFB"
  exit 1
fi
# Should emit stderr warning about embedding unavailable (local missing).
if ! echo "$FB_OUT" | grep -qE "embedding unavailable"; then
  echo "FAIL: fallback path did not emit 'embedding unavailable' stderr warning" >&2
  echo "    output: $FB_OUT" >&2
  rm -rf "$MFB"
  exit 1
fi
rm -rf "$MFB"

# ── Local-mode integration test (plan #18 task 3) ──────────────────────────
# Validates that embed.py with --mode local (the v0.9.2 default) returns
# a real 1024-d embedding when sentence-transformers + the BGE-large model
# are available. Skipped in CI to avoid the ~1.3GB BGE-large model download
# per workflow run (SKIP_LOCAL_MODE_INTEGRATION env var set by the three
# .github/workflows/tests-*.yml files). Operators with sentence-transformers
# installed can opt in by clearing the env var + running this script
# locally; the test will gracefully skip if sentence-transformers itself
# is missing.
echo "==> Local-mode integration test (plan #18 task 3)"
if [[ -n "${SKIP_LOCAL_MODE_INTEGRATION:-}" ]]; then
  echo "    SKIP_LOCAL_MODE_INTEGRATION set — skipped (typically CI; clear var + re-run locally to validate BGE-large)"
else
  LOCAL_EXIT=0
  LOCAL_OUT="$(python3 "$EMBED_PY" "smoke test text for local mode" --mode local 2>&1)" || LOCAL_EXIT=$?
  if [[ $LOCAL_EXIT -eq 2 ]]; then
    # sentence-transformers not installed; graceful-skip path.
    if ! echo "$LOCAL_OUT" | grep -qE "sentence-transformers"; then
      echo "FAIL: --mode local exit 2 but error doesn't mention sentence-transformers" >&2
      echo "    output: $LOCAL_OUT" >&2
      exit 1
    fi
    echo "    sentence-transformers unavailable — skipped (pip install sentence-transformers to enable; first-run downloads BGE-large ~1.3GB)"
  elif [[ $LOCAL_EXIT -eq 0 ]]; then
    LOCAL_LEN="$(echo "$LOCAL_OUT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)"
    if [[ "$LOCAL_LEN" != "1024" ]]; then
      echo "FAIL: --mode local returned $LOCAL_LEN-d output, expected 1024 (BGE-large native)" >&2
      echo "    output: $LOCAL_OUT" >&2
      exit 1
    fi
    # Verify all values are numeric (json.load returns floats/ints).
    FLOAT_CHECK="$(echo "$LOCAL_OUT" | python3 -c "
import json, sys
v = json.load(sys.stdin)
if all(isinstance(x, (int, float)) for x in v):
    print('OK')
else:
    print('FAIL')
" 2>/dev/null || echo "FAIL")"
    if [[ "$FLOAT_CHECK" != "OK" ]]; then
      echo "FAIL: --mode local output had non-numeric values" >&2
      echo "    output: $LOCAL_OUT" >&2
      exit 1
    fi
    echo "    local-mode integration verified: 1024-d numeric vector from BGE-large"
  else
    echo "FAIL: --mode local exited $LOCAL_EXIT (expected 0 success or 2 graceful-skip)" >&2
    echo "    output: $LOCAL_OUT" >&2
    exit 1
  fi
fi

# ── Time budget enforcement test (plan #7a part 2 task 5) ──────────────────
# Verify wall-clock budget enforcement is real: seed many entries + set a
# tight budget (1ms) → the recall walk must terminate early + emit overrun
# warnings + still return results without blocking. Tests both hooks:
# session_start (500ms default, force overrun via --budget-ms 0) and
# prompt_submit (300ms default, same force).
echo "==> Time budget enforcement test (plan #7a part 2 task 5)"
MBUDGET="$(mktemp -d)"
mkdir -p "$MBUDGET/personal-private/_always-load" \
         "$MBUDGET/personal-private/workflow"
# Seed 40 always-load entries — enough that even a fast machine can't
# finish under 1ms of wall-clock (read 40 files + parse frontmatter each).
for i in $(seq 1 40); do
  cat > "$MBUDGET/personal-private/_always-load/budget-pref-$i.md" << BUD_EOF
---
kind: preferences
status: active
slug: budget-pref-$i
tags: [test-budget]
---
Budget test entry number $i with some body text to make parsing nontrivial.
Multiple lines of content to ensure the read_text call takes measurable time
on slow filesystems (cloud-synced vaults, network drives, etc).
BUD_EOF
done
# Also seed regular entries for the prompt-submit / query path.
for i in $(seq 1 30); do
  cat > "$MBUDGET/personal-private/workflow/budget-flow-$i.md" << BUD_EOF
---
kind: workflow
status: active
slug: budget-flow-$i
tags: [budget, workflow, test]
---
Workflow body $i containing keywords like budget and test for grep matches.
BUD_EOF
done

# Test A: session-start with 0ms budget (deadline in the past) → overrun warning + partial results
SS_STDERR_FILE="$MBUDGET/.ss-stderr.log"
python3 "$RECALL_PY" --vault-path "$MBUDGET" session-start --budget-ms 0 > /dev/null 2> "$SS_STDERR_FILE"
SS_BUDGET_EXIT=$?
SS_STDERR_BUDGET="$(cat "$SS_STDERR_FILE")"
if [[ $SS_BUDGET_EXIT -ne 0 ]]; then
  echo "FAIL: session-start with tight budget exited $SS_BUDGET_EXIT (expected graceful 0)" >&2
  echo "    stderr: $SS_STDERR_BUDGET" >&2
  rm -rf "$MBUDGET"
  exit 1
fi
if ! echo "$SS_STDERR_BUDGET" | grep -qE "500ms time budget exceeded|1ms time budget exceeded|time budget exceeded"; then
  echo "FAIL: session-start with 0ms budget (deadline in the past) did not emit overrun warning" >&2
  echo "    stderr: $SS_STDERR_BUDGET" >&2
  rm -rf "$MBUDGET"
  exit 1
fi
# Transparency line should still report loaded count (could be 0 to 40
# depending on machine speed — what matters is overrun warning + exit 0).
if ! echo "$SS_STDERR_BUDGET" | grep -qE "Loaded [0-9]+ MemoryVault always-load entries"; then
  echo "FAIL: session-start with overrun did not emit transparency line" >&2
  echo "    stderr: $SS_STDERR_BUDGET" >&2
  rm -rf "$MBUDGET"
  exit 1
fi

# Test B: session-start with default 500ms budget → no overrun (40 entries
# is well under typical budget on any sane machine).
SS_DEFAULT_STDERR="$(python3 "$RECALL_PY" --vault-path "$MBUDGET" session-start 2>&1 >/dev/null)"
if echo "$SS_DEFAULT_STDERR" | grep -qE "time budget exceeded"; then
  echo "WARN: session-start with default 500ms budget overran on 40 entries — this machine is very slow OR there's a perf regression. stderr: $SS_DEFAULT_STDERR" >&2
  # Don't fail — slow machines (e.g. emulated CI runners) might genuinely take longer.
  # The test is primarily to assert "no overrun warning under normal conditions"
  # but we accept it on slow machines.
fi

# Test C: prompt-submit with 0ms budget (deadline in the past) → engine should overrun + emit
# warning on transparency line.
PS_BUDGET_PAYLOAD='{"hookEventName":"UserPromptSubmit","prompt":"budget workflow test"}'
PS_BUDGET_STDOUT="$(echo "$PS_BUDGET_PAYLOAD" | python3 "$RECALL_PY" --vault-path "$MBUDGET" prompt-submit --budget-ms 0 2>"$MBUDGET/.ps-stderr.log")"
PS_BUDGET_STDERR="$(cat "$MBUDGET/.ps-stderr.log")"
PS_BUDGET_EXIT=$?
if [[ $PS_BUDGET_EXIT -ne 0 ]]; then
  echo "FAIL: prompt-submit with tight budget exited $PS_BUDGET_EXIT (expected graceful 0)" >&2
  echo "    stderr: $PS_BUDGET_STDERR" >&2
  rm -rf "$MBUDGET"
  exit 1
fi
if ! echo "$PS_BUDGET_STDERR" | grep -qE "time budget exceeded"; then
  echo "FAIL: prompt-submit with 0ms budget (deadline in the past) did not emit overrun warning" >&2
  echo "    stderr: $PS_BUDGET_STDERR" >&2
  rm -rf "$MBUDGET"
  exit 1
fi
if ! echo "$PS_BUDGET_STDERR" | grep -qE "Loaded [0-9]+ relevant entries"; then
  echo "FAIL: prompt-submit with overrun did not emit transparency line" >&2
  echo "    stderr: $PS_BUDGET_STDERR" >&2
  rm -rf "$MBUDGET"
  exit 1
fi

# Test D: query subcommand with 0ms budget (deadline in the past) — should still exit 0 + return
# whatever it could gather (possibly empty), never block.
QUERY_BUDGET_EXIT=0
python3 "$RECALL_PY" --vault-path "$MBUDGET" query "budget workflow" --budget-ms 0 --mode stub > /dev/null 2>&1 || QUERY_BUDGET_EXIT=$?
if [[ $QUERY_BUDGET_EXIT -ne 0 ]]; then
  echo "FAIL: query subcommand with 0ms budget (deadline in the past) exited $QUERY_BUDGET_EXIT (expected 0)" >&2
  rm -rf "$MBUDGET"
  exit 1
fi

# Test E: confirm the hooks NEVER raise / non-zero-exit under tight budget.
# Run session-start + prompt-submit each 5 times with 0ms budget (deadline in the past); if any
# call exits non-zero, the never-block-the-prompt / never-block-session
# contract is broken.
for i in 1 2 3 4 5; do
  python3 "$RECALL_PY" --vault-path "$MBUDGET" session-start --budget-ms 0 > /dev/null 2>&1
  SS_LOOP_EXIT=$?
  if [[ $SS_LOOP_EXIT -ne 0 ]]; then
    echo "FAIL: session-start (iteration $i) exited $SS_LOOP_EXIT under tight budget — never-block contract broken" >&2
    rm -rf "$MBUDGET"
    exit 1
  fi
  echo "$PS_BUDGET_PAYLOAD" | python3 "$RECALL_PY" --vault-path "$MBUDGET" prompt-submit --budget-ms 0 > /dev/null 2>&1
  PS_LOOP_EXIT=$?
  if [[ $PS_LOOP_EXIT -ne 0 ]]; then
    echo "FAIL: prompt-submit (iteration $i) exited $PS_LOOP_EXIT under tight budget — never-block contract broken" >&2
    rm -rf "$MBUDGET"
    exit 1
  fi
done
rm -rf "$MBUDGET"

# ── Reflection mining module test (plan #7a part 3 task 1) ─────────────────
# Verify reflect.py mines a seeded fixture transcript into the 4 expected
# candidate categories: preferences (HIGH from "always X"), preferences
# (MEDIUM/LOW from user correction), fix (MEDIUM/LOW from error+fix), idea
# (MEDIUM from "we should also"). Workflow detection (tool-use frequency
# threshold) gets a separate seed.
echo "==> Reflection mining module test (plan #7a part 3 task 1)"
REFLECT_PY="$SCRATCH/.claude/skills/memory/scripts/reflect.py"
if [[ ! -f "$REFLECT_PY" ]]; then
  echo "FAIL: reflect.py not installed at $REFLECT_PY" >&2
  exit 1
fi
MREFLECT="$(mktemp -d)"
cat > "$MREFLECT/transcript.jsonl" << 'REF_EOF'
{"type":"queue-operation","content":"intro"}
{"type":"user","message":{"role":"user","content":"Always use bullet points for status reports, never paragraphs."},"uuid":"u1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Got it."},{"type":"tool_use","name":"Bash"}]},"uuid":"a1"}
{"type":"user","message":{"role":"user","content":"No, that's wrong. You should have added a test plan section."},"uuid":"u2"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]},"uuid":"a2"}
{"type":"user","message":{"role":"user","content":"The CI bug was caused by line endings. Fixed by switching to write_bytes."},"uuid":"u3"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]},"uuid":"a3"}
{"type":"user","message":{"role":"user","content":"We should also build a memory inspect command later for tuning recall weights — could be its own follow-up plan."},"uuid":"u4"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read"}]},"uuid":"a4"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]},"uuid":"a5"}
REF_EOF
REFLECT_OUT="$(python3 "$REFLECT_PY" "$MREFLECT/transcript.jsonl" --summary 2>/dev/null)"
# Test 1: summary line reports messages processed + candidate counts
if ! echo "$REFLECT_OUT" | grep -qE '"pass": "summary".*"messages_processed": 9'; then
  echo "FAIL: summary line missing or wrong messages_processed count" >&2
  echo "    output: $REFLECT_OUT" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
# Test 2: HIGH preferences from "Always use bullet points" pattern
if ! echo "$REFLECT_OUT" | grep -qE '"category": "preferences", "confidence": "HIGH".*always.*bullet'; then
  echo "FAIL: HIGH-confidence preferences candidate missing for 'Always use bullet points' pattern" >&2
  echo "    output: $REFLECT_OUT" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
# Test 3: correction candidate present (MEDIUM-initial → LOW after 1-occurrence demotion)
if ! echo "$REFLECT_OUT" | grep -qE '"rationale": "user correction signal"'; then
  echo "FAIL: correction-pattern candidate missing" >&2
  echo "    output: $REFLECT_OUT" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
# Test 4: fix candidate from "Fixed by" pattern
if ! echo "$REFLECT_OUT" | grep -qE '"category": "fix".*"rationale": "explicit fix statement"'; then
  echo "FAIL: fix candidate missing for 'Fixed by' pattern" >&2
  echo "    output: $REFLECT_OUT" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
# Test 5: idea candidate from "We should also" pattern
if ! echo "$REFLECT_OUT" | grep -qE '"pass": "idea".*"rationale": "explicit follow-up suggestion"'; then
  echo "FAIL: idea candidate missing for 'We should also' pattern" >&2
  echo "    output: $REFLECT_OUT" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
# Test 6: workflow candidate (Bash used 4x → MEDIUM workflow)
if ! echo "$REFLECT_OUT" | grep -qE '"category": "workflow".*"confidence": "MEDIUM".*Bash.*4x'; then
  echo "FAIL: workflow candidate missing (expected Bash used 4x → MEDIUM)" >&2
  echo "    output: $REFLECT_OUT" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
# Test 7: --memory-only flag skips idea pass
MEM_ONLY_OUT="$(python3 "$REFLECT_PY" "$MREFLECT/transcript.jsonl" --memory-only 2>/dev/null)"
if echo "$MEM_ONLY_OUT" | grep -qE '"pass": "idea"'; then
  echo "FAIL: --memory-only flag did not suppress idea pass" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
# Test 8: --idea-only flag skips memory pass
IDEA_ONLY_OUT="$(python3 "$REFLECT_PY" "$MREFLECT/transcript.jsonl" --idea-only 2>/dev/null)"
if echo "$IDEA_ONLY_OUT" | grep -qE '"pass": "memory"'; then
  echo "FAIL: --idea-only flag did not suppress memory pass" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
# Test 9: missing transcript → exit 1 + clear error
MISSING_EXIT=0
python3 "$REFLECT_PY" /nonexistent/path/$$ 2>/dev/null || MISSING_EXIT=$?
if [[ $MISSING_EXIT -ne 1 ]]; then
  echo "FAIL: reflect.py on missing transcript exited $MISSING_EXIT (expected 1)" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
# Test 10: empty transcript → exit 0 with 0 candidates
EMPTY_TRANSCRIPT="$MREFLECT/empty.jsonl"
: > "$EMPTY_TRANSCRIPT"
EMPTY_OUT="$(python3 "$REFLECT_PY" "$EMPTY_TRANSCRIPT" --summary 2>/dev/null)"
if ! echo "$EMPTY_OUT" | grep -qE '"messages_processed": 0'; then
  echo "FAIL: empty transcript did not produce 'messages_processed: 0' summary" >&2
  echo "    output: $EMPTY_OUT" >&2
  rm -rf "$MREFLECT"
  exit 1
fi
rm -rf "$MREFLECT"

# ── Stop-event reflection hook test (plan #7a part 3 task 3) ───────────────
# Verify the memory-reflect-stop hook lands + executes end-to-end against a
# mocked Stop payload + fixture transcript. The hook should: (1) parse
# session_id + cwd from stdin JSON; (2) compute transcript path; (3) invoke
# reflect.py --summary; (4) emit transparency line on stderr; (5) re-emit
# reflect.py output on stdout; (6) exit 0 even on missing transcript / bad
# stdin (never-block-session-end contract).
echo "==> Stop-event reflection hook test (plan #7a part 3 task 3)"
REFLECT_STOP_SH="$SCRATCH/.claude/hooks/memory-reflect-stop.sh"
if [[ ! -x "$REFLECT_STOP_SH" ]]; then
  echo "FAIL: memory-reflect-stop.sh not installed/executable at $REFLECT_STOP_SH" >&2
  exit 1
fi
# settings.json must contain the Stop entry referencing memory-reflect-stop.sh
if ! grep -qE 'memory-reflect-stop\.sh' "$SETTINGS_JSON"; then
  echo "FAIL: settings.json missing memory-reflect-stop.sh Stop entry" >&2
  exit 1
fi
# Seed a fixture transcript at the expected ~/.claude/projects/<cwd-slug>/<session-id>.jsonl path
MRSTOP="$(mktemp -d)"
RSTOP_CWD_SLUG="-$(echo "$MRSTOP" | tr '/' '-')"
RSTOP_TRANSCRIPT_DIR="$HOME/.claude/projects/$RSTOP_CWD_SLUG"
RSTOP_SESSION_ID="a1b2c3d4-e5f6-7a8b-9c0d-aabbccddeeff"
mkdir -p "$RSTOP_TRANSCRIPT_DIR"
RSTOP_TRANSCRIPT="$RSTOP_TRANSCRIPT_DIR/$RSTOP_SESSION_ID.jsonl"
cat > "$RSTOP_TRANSCRIPT" << 'RS_EOF'
{"type":"user","message":{"role":"user","content":"Always lint before pushing."},"uuid":"u1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]},"uuid":"a1"}
{"type":"user","message":{"role":"user","content":"We should also add a status line later."},"uuid":"u2"}
RS_EOF

# Test A: happy path — valid Stop payload + valid transcript → transparency line + reflect output.
# Set MEMORY_VAULT_PATH so the hook's --route pass works end-to-end (saves
# HIGH candidates to canonical paths + MEDIUM/LOW + ideas to _inbox/).
# Stage reflect.py + save.py + embed.py + vec_index.py into the hook's
# script search path (reflect.py imports save module via sys.path).
mkdir -p "$MRSTOP/.claude/skills/memory/scripts" "$MRSTOP/.claude/hooks"
for pyf in reflect save embed vec_index; do
  cp "$SCRATCH/.claude/skills/memory/scripts/$pyf.py" "$MRSTOP/.claude/skills/memory/scripts/"
done
cp "$REFLECT_STOP_SH" "$MRSTOP/.claude/hooks/"
chmod +x "$MRSTOP/.claude/hooks/memory-reflect-stop.sh"
RSTOP_VAULT="$(mktemp -d)"
RSTOP_PAYLOAD='{"session_id":"'$RSTOP_SESSION_ID'","cwd":"'$MRSTOP'","hookEventName":"Stop"}'
RSTOP_STDOUT="$(cd "$MRSTOP" && MEMORY_VAULT_PATH="$RSTOP_VAULT" echo "$RSTOP_PAYLOAD" | MEMORY_VAULT_PATH="$RSTOP_VAULT" bash .claude/hooks/memory-reflect-stop.sh 2>/tmp/rstop-stderr.log)"
RSTOP_STDERR="$(cat /tmp/rstop-stderr.log)"
rm -f /tmp/rstop-stderr.log
if ! echo "$RSTOP_STDERR" | grep -qE "Mined [0-9]+ memory \+ [0-9]+ idea candidates.*saved [0-9]+, inboxed [0-9]+"; then
  echo "FAIL: Stop hook stderr missing transparency line with route counts" >&2
  echo "    stderr: $RSTOP_STDERR" >&2
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR" "$RSTOP_VAULT"
  exit 1
fi
# Verify routing actually wrote at least one canonical entry (HIGH "Always lint" → preferences/)
if [[ ! -f "$RSTOP_VAULT/personal-private/preferences/always-lint-before-pushing.md" ]]; then
  echo "FAIL: Stop hook --route did not auto-save HIGH candidate to canonical path" >&2
  echo "    vault listing:" >&2
  find "$RSTOP_VAULT" -type f >&2 2>/dev/null
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR" "$RSTOP_VAULT"
  exit 1
fi
if ! echo "$RSTOP_STDOUT" | grep -qE '"pass": "summary"'; then
  echo "FAIL: Stop hook stdout missing reflect.py summary record" >&2
  echo "    stdout: $RSTOP_STDOUT" >&2
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR"
  exit 1
fi
if ! echo "$RSTOP_STDOUT" | grep -qE "always-lint-before-pushing"; then
  echo "FAIL: Stop hook stdout missing expected always-lint candidate slug" >&2
  echo "    stdout: $RSTOP_STDOUT" >&2
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR"
  exit 1
fi

# Test B: missing stdin → graceful skip
B_STDERR="$(cd "$MRSTOP" && echo -n "" | bash .claude/hooks/memory-reflect-stop.sh 2>&1)"
B_EXIT=$?
if [[ $B_EXIT -ne 0 ]]; then
  echo "FAIL: Stop hook with empty stdin exited $B_EXIT (expected 0)" >&2
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR"
  exit 1
fi
if ! echo "$B_STDERR" | grep -qE "no stdin payload"; then
  echo "FAIL: Stop hook with empty stdin did not emit 'no stdin payload' warning" >&2
  echo "    stderr: $B_STDERR" >&2
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR"
  exit 1
fi

# Test C: stdin missing session_id → graceful skip
C_STDERR="$(cd "$MRSTOP" && echo '{"hookEventName":"Stop"}' | bash .claude/hooks/memory-reflect-stop.sh 2>&1)"
C_EXIT=$?
if [[ $C_EXIT -ne 0 ]]; then
  echo "FAIL: Stop hook with no session_id exited $C_EXIT (expected 0)" >&2
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR"
  exit 1
fi
if ! echo "$C_STDERR" | grep -qE "no session_id"; then
  echo "FAIL: Stop hook with no session_id did not emit graceful warning" >&2
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR"
  exit 1
fi

# Test D: transcript doesn't exist → graceful skip
D_PAYLOAD='{"session_id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeffff","cwd":"'$MRSTOP'","hookEventName":"Stop"}'
D_STDERR="$(cd "$MRSTOP" && echo "$D_PAYLOAD" | bash .claude/hooks/memory-reflect-stop.sh 2>&1)"
D_EXIT=$?
if [[ $D_EXIT -ne 0 ]]; then
  echo "FAIL: Stop hook with missing transcript exited $D_EXIT (expected 0)" >&2
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR"
  exit 1
fi
if ! echo "$D_STDERR" | grep -qE "transcript not found"; then
  echo "FAIL: Stop hook with missing transcript did not emit 'transcript not found' warning" >&2
  rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR"
  exit 1
fi

# Cleanup
rm -rf "$MRSTOP" "$RSTOP_TRANSCRIPT_DIR" "$RSTOP_VAULT"

# ── Idle-time reflection hook test (plan #7a part 3 task 4) ────────────────
# Verify the memory-reflect-idle hook handles orphan markers correctly:
# (1) hook installed at .claude/hooks/memory-reflect-idle.sh; (2) settings.json
# has SessionStart entry referencing the script; (3) orphan marker → reflect.py
# runs + marker renamed .start → .reflected; (4) fresh marker → no-op; (5)
# missing transcript → graceful skip; (6) .reflected GC after threshold.
echo "==> Idle-time reflection hook test (plan #7a part 3 task 4)"
REFLECT_IDLE_SH="$SCRATCH/.claude/hooks/memory-reflect-idle.sh"
if [[ ! -x "$REFLECT_IDLE_SH" ]]; then
  echo "FAIL: memory-reflect-idle.sh not installed/executable at $REFLECT_IDLE_SH" >&2
  exit 1
fi
if ! grep -qE 'memory-reflect-idle\.sh' "$SETTINGS_JSON"; then
  echo "FAIL: settings.json missing memory-reflect-idle.sh SessionStart entry" >&2
  exit 1
fi
# Stage scratch project + seed orphan marker + transcript.
MRIDLE="$(mktemp -d)"
mkdir -p "$MRIDLE/.claude/skills/memory/scripts" "$MRIDLE/.claude/hooks" "$MRIDLE/.harness"
# Stage reflect.py + save.py + embed.py + vec_index.py (reflect.py --route
# imports save module from same scripts/ dir; embed/vec_index needed by save).
for pyf in reflect save embed vec_index; do
  cp "$SCRATCH/.claude/skills/memory/scripts/$pyf.py" "$MRIDLE/.claude/skills/memory/scripts/"
done
cp "$REFLECT_IDLE_SH" "$MRIDLE/.claude/hooks/"
chmod +x "$MRIDLE/.claude/hooks/memory-reflect-idle.sh"
# Separate vault for routing destination
RIDLE_VAULT="$(mktemp -d)"
export MEMORY_VAULT_PATH="$RIDLE_VAULT"
IDLE_TRANSCRIPT="$MRIDLE/orphan-transcript.jsonl"
cat > "$IDLE_TRANSCRIPT" << 'IDLE_EOF'
{"type":"user","message":{"role":"user","content":"Always commit before EOD."},"uuid":"u1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]},"uuid":"a1"}
IDLE_EOF

# Test A: orphan marker (mtime backdated past idle threshold) → reflection + rename
cat > "$MRIDLE/.harness/session-id-aabbccdd.start" << IDLE_EOF
session_id: aabbccdd-eeffaabb
started_at: 2026-05-18T00:00:00Z
transcript: $IDLE_TRANSCRIPT
IDLE_EOF
python3 -c "import os, sys, time; os.utime(sys.argv[1], (time.time() - 172800, time.time() - 172800))" "$MRIDLE/.harness/session-id-aabbccdd.start"
IDLE_OUT="$(cd "$MRIDLE" && bash .claude/hooks/memory-reflect-idle.sh 2>&1)"
if ! echo "$IDLE_OUT" | grep -qE "processed 1 orphans"; then
  echo "FAIL: idle hook did not process orphan marker" >&2
  echo "    output: $IDLE_OUT" >&2
  rm -rf "$MRIDLE"
  exit 1
fi
if ! echo "$IDLE_OUT" | grep -qE "always-commit-before-eod"; then
  echo "FAIL: idle hook stdout missing expected reflection output" >&2
  echo "    output: $IDLE_OUT" >&2
  rm -rf "$MRIDLE"
  exit 1
fi
if [[ -f "$MRIDLE/.harness/session-id-aabbccdd.start" ]]; then
  echo "FAIL: orphan marker .start not renamed after reflection" >&2
  rm -rf "$MRIDLE"
  exit 1
fi
if [[ ! -f "$MRIDLE/.harness/session-id-aabbccdd.reflected" ]]; then
  echo "FAIL: orphan marker not renamed to .reflected" >&2
  rm -rf "$MRIDLE"
  exit 1
fi

# Test B: fresh marker (mtime now) → no-op (preserve .start)
rm -f "$MRIDLE/.harness"/*
cat > "$MRIDLE/.harness/session-id-freshfresh.start" << IDLE_EOF
session_id: freshfresh-eeffaabb
started_at: 2026-05-18T00:00:00Z
transcript: $IDLE_TRANSCRIPT
IDLE_EOF
FRESH_OUT="$(cd "$MRIDLE" && bash .claude/hooks/memory-reflect-idle.sh 2>&1)"
FRESH_EXIT=$?
if [[ $FRESH_EXIT -ne 0 ]]; then
  echo "FAIL: idle hook with fresh marker exited $FRESH_EXIT (expected 0)" >&2
  rm -rf "$MRIDLE"
  exit 1
fi
if [[ ! -f "$MRIDLE/.harness/session-id-freshfresh.start" ]]; then
  echo "FAIL: fresh marker was processed (should be preserved as .start)" >&2
  rm -rf "$MRIDLE"
  exit 1
fi
if echo "$FRESH_OUT" | grep -qE "processed [1-9]"; then
  echo "FAIL: idle hook reported processing fresh marker (mtime too recent for threshold)" >&2
  echo "    output: $FRESH_OUT" >&2
  rm -rf "$MRIDLE"
  exit 1
fi

# Test C: no .harness dir → silent exit 0
rm -rf "$MRIDLE/.harness"
NOHARNESS_OUT="$(cd "$MRIDLE" && bash .claude/hooks/memory-reflect-idle.sh 2>&1)"
NOHARNESS_EXIT=$?
if [[ $NOHARNESS_EXIT -ne 0 ]]; then
  echo "FAIL: idle hook without .harness/ exited $NOHARNESS_EXIT (expected 0)" >&2
  rm -rf "$MRIDLE"
  exit 1
fi
if [[ -n "$NOHARNESS_OUT" ]]; then
  echo "FAIL: idle hook without .harness/ emitted output (should be silent): $NOHARNESS_OUT" >&2
  rm -rf "$MRIDLE"
  exit 1
fi
mkdir -p "$MRIDLE/.harness"

# Test D: missing transcript in marker → graceful skip
cat > "$MRIDLE/.harness/session-id-missing00.start" << IDLE_EOF
session_id: missing00-eeffaabb
started_at: 2026-05-18T00:00:00Z
transcript: /nonexistent/path/$$.jsonl
IDLE_EOF
python3 -c "import os, sys, time; os.utime(sys.argv[1], (time.time() - 172800, time.time() - 172800))" "$MRIDLE/.harness/session-id-missing00.start"
MISS_OUT="$(cd "$MRIDLE" && bash .claude/hooks/memory-reflect-idle.sh 2>&1)"
if ! echo "$MISS_OUT" | grep -qE "transcript not found"; then
  echo "FAIL: idle hook with missing-transcript marker did not emit warning" >&2
  echo "    output: $MISS_OUT" >&2
  rm -rf "$MRIDLE"
  exit 1
fi
# Marker should stay as .start (failed reflection leaves marker for retry).
if [[ ! -f "$MRIDLE/.harness/session-id-missing00.start" ]]; then
  echo "FAIL: failed-reflection marker was renamed (should stay .start for retry)" >&2
  rm -rf "$MRIDLE"
  exit 1
fi

# Test E: idle threshold env override (set to 86400 = 1 day; orphan from
# python3 -c "import os, sys, time; os.utime(sys.argv[1], (time.time() - 172800, time.time() - 172800))" is older than that, so still processes; but fresh
# marker stays fresh).
rm -f "$MRIDLE/.harness"/*
cat > "$MRIDLE/.harness/session-id-overridetst.start" << IDLE_EOF
session_id: overridetst-eeffaabb
started_at: 2026-05-18T00:00:00Z
transcript: $IDLE_TRANSCRIPT
IDLE_EOF
# Don't backdate this one — mtime = now. With threshold=86400 it should NOT process.
OVERRIDE_OUT="$(cd "$MRIDLE" && MEMORY_IDLE_THRESHOLD_SEC=86400 bash .claude/hooks/memory-reflect-idle.sh 2>&1)"
if ! echo "$OVERRIDE_OUT" | grep -qE "idle threshold: 86400s"; then
  echo "FAIL: idle hook did not honor MEMORY_IDLE_THRESHOLD_SEC env override" >&2
  echo "    output: $OVERRIDE_OUT" >&2
  rm -rf "$MRIDLE"
  exit 1
fi
if echo "$OVERRIDE_OUT" | grep -qE "processed [1-9]"; then
  echo "FAIL: idle hook processed marker that should be under 86400s threshold" >&2
  rm -rf "$MRIDLE"
  exit 1
fi

rm -rf "$MRIDLE" "$RIDLE_VAULT"
unset MEMORY_VAULT_PATH

# ── Crash-recovery marker lifecycle test (plan #7a part 3 task 6) ──────────
# Verify the full marker lifecycle:
#   1. SessionStart hook (memory-recall-session-start) writes
#      .harness/session-id-<sid>.start with session_id+started_at+transcript
#   2. Stop hook (memory-reflect-stop) renames .start → .reflected on
#      successful reflection
#   3. Idle hook (memory-reflect-idle) recovers orphan .start markers +
#      GCs old .reflected markers — covered by task 4's smoke test
echo "==> Crash-recovery marker lifecycle test (plan #7a part 3 task 6)"
MMARKER="$(mktemp -d)"
MMARKER_VAULT="$(mktemp -d)"
MMARKER_SESSION_ID="b1c2d3e4-f5a6-7b8c-9d0e-marker6lifecyc"
MMARKER_CWD_SLUG="-$(echo "$MMARKER" | tr '/' '-')"
MMARKER_TRANSCRIPT_DIR="$HOME/.claude/projects/$MMARKER_CWD_SLUG"
MMARKER_TRANSCRIPT="$MMARKER_TRANSCRIPT_DIR/$MMARKER_SESSION_ID.jsonl"
mkdir -p "$MMARKER/.claude/skills/memory/scripts" "$MMARKER/.claude/hooks" "$MMARKER_TRANSCRIPT_DIR"
for pyf in recall reflect save embed vec_index; do
  cp "$SCRATCH/.claude/skills/memory/scripts/$pyf.py" "$MMARKER/.claude/skills/memory/scripts/"
done
cp "$SCRATCH/.claude/hooks/memory-recall-session-start.sh" "$MMARKER/.claude/hooks/"
cp "$SCRATCH/.claude/hooks/memory-reflect-stop.sh" "$MMARKER/.claude/hooks/"
chmod +x "$MMARKER/.claude/hooks/"*.sh
cat > "$MMARKER_TRANSCRIPT" << 'MARKER_EOF'
{"type":"user","message":{"role":"user","content":"Always commit before EOD."},"uuid":"u1"}
MARKER_EOF

# Test 1: SessionStart hook writes marker
SS_PAYLOAD='{"session_id":"'$MMARKER_SESSION_ID'","cwd":"'$MMARKER'","hookEventName":"SessionStart"}'
(cd "$MMARKER" && MEMORY_VAULT_PATH="$MMARKER_VAULT" bash -c "echo '$SS_PAYLOAD' | bash .claude/hooks/memory-recall-session-start.sh") > /dev/null 2>&1
START_MARKER="$MMARKER/.harness/session-id-$MMARKER_SESSION_ID.start"
if [[ ! -f "$START_MARKER" ]]; then
  echo "FAIL: SessionStart hook did not write .start marker at $START_MARKER" >&2
  ls -la "$MMARKER/.harness/" 2>/dev/null >&2
  rm -rf "$MMARKER" "$MMARKER_VAULT" "$MMARKER_TRANSCRIPT_DIR"
  exit 1
fi
if ! grep -q "session_id: $MMARKER_SESSION_ID" "$START_MARKER"; then
  echo "FAIL: marker missing session_id field" >&2
  cat "$START_MARKER" >&2
  rm -rf "$MMARKER" "$MMARKER_VAULT" "$MMARKER_TRANSCRIPT_DIR"
  exit 1
fi
if ! grep -q "^started_at: " "$START_MARKER"; then
  echo "FAIL: marker missing started_at field" >&2
  rm -rf "$MMARKER" "$MMARKER_VAULT" "$MMARKER_TRANSCRIPT_DIR"
  exit 1
fi
if ! grep -q "^transcript: " "$START_MARKER"; then
  echo "FAIL: marker missing transcript field" >&2
  rm -rf "$MMARKER" "$MMARKER_VAULT" "$MMARKER_TRANSCRIPT_DIR"
  exit 1
fi

# Test 2: re-invoking SessionStart hook with same session_id is idempotent
# (doesn't overwrite existing marker)
ORIG_MARKER_CONTENT="$(cat "$START_MARKER")"
sleep 1  # ensure mtime would differ if overwritten
(cd "$MMARKER" && MEMORY_VAULT_PATH="$MMARKER_VAULT" bash -c "echo '$SS_PAYLOAD' | bash .claude/hooks/memory-recall-session-start.sh") > /dev/null 2>&1
NEW_MARKER_CONTENT="$(cat "$START_MARKER")"
if [[ "$ORIG_MARKER_CONTENT" != "$NEW_MARKER_CONTENT" ]]; then
  echo "FAIL: SessionStart re-invocation overwrote existing marker (should be idempotent)" >&2
  rm -rf "$MMARKER" "$MMARKER_VAULT" "$MMARKER_TRANSCRIPT_DIR"
  exit 1
fi

# Test 3: Stop hook renames .start → .reflected
STOP_PAYLOAD='{"session_id":"'$MMARKER_SESSION_ID'","cwd":"'$MMARKER'","hookEventName":"Stop"}'
(cd "$MMARKER" && MEMORY_VAULT_PATH="$MMARKER_VAULT" bash -c "echo '$STOP_PAYLOAD' | bash .claude/hooks/memory-reflect-stop.sh") > /dev/null 2>&1
REFLECTED_MARKER="$MMARKER/.harness/session-id-$MMARKER_SESSION_ID.reflected"
if [[ -f "$START_MARKER" ]]; then
  echo "FAIL: Stop hook left .start marker in place (should have renamed to .reflected)" >&2
  ls -la "$MMARKER/.harness/" >&2
  rm -rf "$MMARKER" "$MMARKER_VAULT" "$MMARKER_TRANSCRIPT_DIR"
  exit 1
fi
if [[ ! -f "$REFLECTED_MARKER" ]]; then
  echo "FAIL: Stop hook did not create .reflected marker" >&2
  ls -la "$MMARKER/.harness/" >&2
  rm -rf "$MMARKER" "$MMARKER_VAULT" "$MMARKER_TRANSCRIPT_DIR"
  exit 1
fi

# Test 4: Stop hook with no pre-existing marker is graceful no-op (marker
# lifecycle is best-effort; Stop without prior SessionStart is rare but valid)
NO_MARKER_SESSION_ID="c1d2e3f4-a5b6-7c8d-9e0f-marker6nostart"
NO_MARKER_TRANSCRIPT="$MMARKER_TRANSCRIPT_DIR/$NO_MARKER_SESSION_ID.jsonl"
cp "$MMARKER_TRANSCRIPT" "$NO_MARKER_TRANSCRIPT"
NO_MARKER_STOP_PAYLOAD='{"session_id":"'$NO_MARKER_SESSION_ID'","cwd":"'$MMARKER'","hookEventName":"Stop"}'
NO_MARKER_EXIT=0
(cd "$MMARKER" && MEMORY_VAULT_PATH="$MMARKER_VAULT" bash -c "echo '$NO_MARKER_STOP_PAYLOAD' | bash .claude/hooks/memory-reflect-stop.sh") > /dev/null 2>&1 || NO_MARKER_EXIT=$?
if [[ $NO_MARKER_EXIT -ne 0 ]]; then
  echo "FAIL: Stop hook with no pre-existing marker exited $NO_MARKER_EXIT (expected 0)" >&2
  rm -rf "$MMARKER" "$MMARKER_VAULT" "$MMARKER_TRANSCRIPT_DIR"
  exit 1
fi

rm -rf "$MMARKER" "$MMARKER_VAULT" "$MMARKER_TRANSCRIPT_DIR"

# ── Permeable boundary helper test (plan #7a part 4 task 1) ────────────────
# Verify the A3 permeable-write-boundary helper:
#   - silent mode → auto-approve (exit 0, approved=true)
#   - auto mode → deny (exit 1, approved=false) — never silently writes
#     outside MemoryVault from non-TTY hook contexts
#   - interactive mode with non-TTY stdin → fall back to deny (exit 1)
#   - invalid mode → argparse error (exit 2)
#   - env var MEMORY_REVIEW_MODE=silent override → auto-approve
echo "==> Permeable boundary helper test (plan #7a part 4 task 1)"
PB_PY="$SCRATCH/.claude/skills/memory/scripts/permeable_boundary.py"
if [[ ! -f "$PB_PY" ]]; then
  echo "FAIL: permeable_boundary.py not installed at $PB_PY" >&2
  exit 1
fi
# Test A: silent mode → approved
PB_A=0
PB_A_OUT="$(python3 "$PB_PY" /tmp/test-write.md --content-preview "hello" --rationale "test" --mode silent 2>&1)" || PB_A=$?
if [[ $PB_A -ne 0 ]]; then
  echo "FAIL: silent mode exited $PB_A (expected 0)" >&2
  echo "    output: $PB_A_OUT" >&2
  exit 1
fi
if ! echo "$PB_A_OUT" | grep -qE '"approved": true'; then
  echo "FAIL: silent mode did not emit approved:true" >&2
  echo "    output: $PB_A_OUT" >&2
  exit 1
fi
# Test B: auto mode → denied (exit 1)
PB_B=0
PB_B_OUT="$(python3 "$PB_PY" /tmp/test-write.md --content-preview "hello" --rationale "test" --mode auto 2>&1)" || PB_B=$?
if [[ $PB_B -ne 1 ]]; then
  echo "FAIL: auto mode exited $PB_B (expected 1 — A3 says never silently write outside MemoryVault)" >&2
  echo "    output: $PB_B_OUT" >&2
  exit 1
fi
if ! echo "$PB_B_OUT" | grep -qE '"approved": false'; then
  echo "FAIL: auto mode did not emit approved:false" >&2
  echo "    output: $PB_B_OUT" >&2
  exit 1
fi
# Test C: interactive mode with non-TTY (piped stdin) → fall back to deny
PB_C=0
PB_C_OUT="$(echo "y" | python3 "$PB_PY" /tmp/test-write.md --content-preview "hello" --rationale "test" --mode interactive 2>&1)" || PB_C=$?
if [[ $PB_C -ne 1 ]]; then
  echo "FAIL: interactive mode with non-TTY exited $PB_C (expected 1 — never silently approve from piped stdin)" >&2
  echo "    output: $PB_C_OUT" >&2
  exit 1
fi
if ! echo "$PB_C_OUT" | grep -qE '"approved": false'; then
  echo "FAIL: interactive non-TTY did not emit approved:false" >&2
  exit 1
fi
# Test D: invalid mode → argparse exit 2
PB_D=0
python3 "$PB_PY" /tmp/test-write.md --mode bogus 2>/dev/null || PB_D=$?
if [[ $PB_D -ne 2 ]]; then
  echo "FAIL: invalid mode exited $PB_D (expected 2 from argparse)" >&2
  exit 1
fi
# Test E: MEMORY_REVIEW_MODE=silent env var → auto-approve
PB_E=0
PB_E_OUT="$(MEMORY_REVIEW_MODE=silent python3 "$PB_PY" /tmp/test-write.md --content-preview "x" --rationale "y" 2>&1)" || PB_E=$?
if [[ $PB_E -ne 0 ]]; then
  echo "FAIL: env MEMORY_REVIEW_MODE=silent did not auto-approve (exit $PB_E)" >&2
  echo "    output: $PB_E_OUT" >&2
  exit 1
fi
if ! echo "$PB_E_OUT" | grep -qE '"approved": true'; then
  echo "FAIL: env silent did not emit approved:true" >&2
  exit 1
fi
# Test F: Python API with mocked TTY stdin → approved on 'y', denied on 'n'
PB_F_OUT="$(python3 -c '
import io, sys
sys.path.insert(0, r"'$SCRATCH/.claude/skills/memory/scripts'")
from permeable_boundary import confirm_write_outside_memoryvault
class FakeStdin(io.StringIO):
    def isatty(self): return True
for ans, expect in [("y\n", True), ("n\n", False), ("\n", False), ("yes\n", True)]:
    fake_in = FakeStdin(ans)
    fake_out = io.StringIO()
    got = confirm_write_outside_memoryvault("/tmp/t.md", "p", "r", stdin=fake_in, stdout=fake_out, mode="interactive")
    if got != expect:
        print(f"FAIL: answer={ans!r} expected {expect} got {got}")
        sys.exit(1)
print("OK")
' 2>&1)"
if [[ "$PB_F_OUT" != "OK" ]]; then
  echo "FAIL: Python API TTY answer mapping broken: $PB_F_OUT" >&2
  exit 1
fi

# ── Ideas.md surface-tier writer test (plan #7a part 4 task 2) ─────────────
# Verify ideas_surface.py appends idea sections to Ideas.md correctly:
#   - silent mode + first write creates header + section
#   - second write appends section without touching header
#   - sections use locked format (## YYYY-MM-DD: Title + summary + wikilink)
#   - auto mode → denied (A3 boundary)
#   - empty summary → error exit 1
#   - IDEAS_SURFACE_PATH env override redirects target
echo "==> Ideas.md surface-tier writer test (plan #7a part 4 task 2)"
IS_PY="$SCRATCH/.claude/skills/memory/scripts/ideas_surface.py"
if [[ ! -f "$IS_PY" ]]; then
  echo "FAIL: ideas_surface.py not installed at $IS_PY" >&2
  exit 1
fi
MISURFACE="$(mktemp -d)"
IDEAS_MD="$MISURFACE/Ideas.md"
# Test A: silent + first write creates header + section
IS_A_OUT="$(python3 "$IS_PY" \
  'Add /memory inspect command' \
  'Operators need to audit why a candidate was mined. Build /memory inspect.' \
  --ideas-path "$IDEAS_MD" --mode silent 2>&1)"
if ! echo "$IS_A_OUT" | grep -qE '"appended": true'; then
  echo "FAIL: silent first-write did not emit appended:true. output: $IS_A_OUT" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
if ! grep -qE "^# Ideas$" "$IDEAS_MD"; then
  echo "FAIL: Ideas.md missing first-write header" >&2
  cat "$IDEAS_MD" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
if ! grep -qE "^## [0-9]{4}-[0-9]{2}-[0-9]{2}: Add /memory inspect command$" "$IDEAS_MD"; then
  echo "FAIL: section header missing or wrong format" >&2
  cat "$IDEAS_MD" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
if ! grep -qE 'See deep research: \[\[MemoryVault/personal-private/_idea-incubator/add-memory-inspect-command/_index.md\]\]' "$IDEAS_MD"; then
  echo "FAIL: section missing wikilink (or wrong slug)" >&2
  cat "$IDEAS_MD" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
# Test B: second write appends + preserves header + uses custom slug
ORIG_HEADER="$(head -5 "$IDEAS_MD")"
python3 "$IS_PY" 'Idle hook native event' 'Lobby Claude Code team for real idle-event hook.' \
  --slug claude-code-idle-event --ideas-path "$IDEAS_MD" --mode silent >/dev/null 2>&1
NEW_HEADER="$(head -5 "$IDEAS_MD")"
if [[ "$ORIG_HEADER" != "$NEW_HEADER" ]]; then
  echo "FAIL: second-write modified the first 5 lines (header should be preserved)" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
SECTION_COUNT="$(grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}:' "$IDEAS_MD" || echo 0)"
if [[ "$SECTION_COUNT" != "2" ]]; then
  echo "FAIL: expected 2 sections after second write, got $SECTION_COUNT" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
if ! grep -qE '\[\[MemoryVault/personal-private/_idea-incubator/claude-code-idle-event/_index.md\]\]' "$IDEAS_MD"; then
  echo "FAIL: second section missing custom-slug wikilink" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
# Test C: auto mode → denied (A3 boundary)
IS_C=0
python3 "$IS_PY" 'Should not appear' 'Anything' --ideas-path "$IDEAS_MD" --mode auto >/dev/null 2>&1 || IS_C=$?
if [[ $IS_C -ne 2 ]]; then
  echo "FAIL: auto mode exited $IS_C (expected 2 — permeable_boundary denied)" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
if grep -qE 'Should not appear' "$IDEAS_MD"; then
  echo "FAIL: auto-denied content leaked into Ideas.md" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
# Test D: empty summary → error exit 1
IS_D=0
python3 "$IS_PY" 'Title' '   ' --ideas-path "$IDEAS_MD" --mode silent >/dev/null 2>&1 || IS_D=$?
if [[ $IS_D -ne 1 ]]; then
  echo "FAIL: empty summary exited $IS_D (expected 1)" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
# Test E: IDEAS_SURFACE_PATH env override
ENV_IDEAS="$MISURFACE/env-Ideas.md"
IDEAS_SURFACE_PATH="$ENV_IDEAS" python3 "$IS_PY" 'Env override test' 'Test summary.' --mode silent >/dev/null 2>&1
if [[ ! -f "$ENV_IDEAS" ]]; then
  echo "FAIL: IDEAS_SURFACE_PATH env override did not redirect Ideas.md" >&2
  rm -rf "$MISURFACE"
  exit 1
fi
rm -rf "$MISURFACE"

# ── _idea-incubator skeleton writer test (plan #7a part 4 task 3) ──────────
# Verify ideas_incubator.py creates the 4-file skeleton (_index.md +
# research-pending.md + related-memoryvault.md + related-obsidian.md);
# verify slug-collision suffix; verify excerpts + rationale flow through
# to _index.md frontmatter + body.
echo "==> _idea-incubator skeleton writer test (plan #7a part 4 task 3)"
II_PY="$SCRATCH/.claude/skills/memory/scripts/ideas_incubator.py"
if [[ ! -f "$II_PY" ]]; then
  echo "FAIL: ideas_incubator.py not installed at $II_PY" >&2
  exit 1
fi
MIINCUB="$(mktemp -d)"
# Test A: skeleton creates 4 files
II_A_OUT="$(python3 "$II_PY" \
  'Add /memory inspect for tuning' \
  'Operators need to audit which patterns matched + adjust the merge weights.' \
  --vault-path "$MIINCUB" \
  --session-id "abc12345-deadbeef" \
  --rationale "Mentioned 3x during recall-loop part" \
  --excerpt "We should tune the rank-merge weights" 2>&1)"
if ! echo "$II_A_OUT" | grep -qE '"created": true'; then
  echo "FAIL: ideas_incubator did not emit created:true. output: $II_A_OUT" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
INCUB_DIR="$MIINCUB/personal-private/_idea-incubator/add-memory-inspect-for-tuning"
for fname in _index.md research-pending.md related-memoryvault.md related-obsidian.md; do
  if [[ ! -f "$INCUB_DIR/$fname" ]]; then
    echo "FAIL: incubator skeleton missing $fname at $INCUB_DIR" >&2
    ls -la "$INCUB_DIR" >&2 2>/dev/null
    rm -rf "$MIINCUB"
    exit 1
  fi
done
# Verify _index.md frontmatter has locked fields
INDEX_MD="$INCUB_DIR/_index.md"
for required_field in "kind: idea" "status: incubating" "slug: add-memory-inspect-for-tuning" "surfaced_in_session: abc12345-deadbeef" "research_budget_wall_time_sec: 300" "research_budget_web_fetches: 3" "research_budget_tokens: 5000"; do
  if ! grep -qF "$required_field" "$INDEX_MD"; then
    echo "FAIL: _index.md missing field: $required_field" >&2
    cat "$INDEX_MD" >&2
    rm -rf "$MIINCUB"
    exit 1
  fi
done
# Body should contain rationale + excerpt
if ! grep -qF "Mentioned 3x during recall-loop part" "$INDEX_MD"; then
  echo "FAIL: _index.md body missing rationale text" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
if ! grep -qF "tune the rank-merge weights" "$INDEX_MD"; then
  echo "FAIL: _index.md body missing supporting excerpt" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
# Test B: collision suffix
II_B_OUT="$(python3 "$II_PY" \
  'Add /memory inspect for tuning' \
  'Same title, different summary.' \
  --vault-path "$MIINCUB" 2>&1)"
if ! echo "$II_B_OUT" | grep -qE '"slug": "add-memory-inspect-for-tuning-2"'; then
  echo "FAIL: collision did not produce -2 suffix slug" >&2
  echo "    output: $II_B_OUT" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
if [[ ! -d "$MIINCUB/personal-private/_idea-incubator/add-memory-inspect-for-tuning-2" ]]; then
  echo "FAIL: -2 suffix dir not created" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
# Test C: no vault → error
II_C=0
python3 "$II_PY" 'Title' 'Summary' --vault-path /nonexistent/path/$$ 2>/dev/null || II_C=$?
if [[ $II_C -ne 1 ]]; then
  echo "FAIL: nonexistent vault exited $II_C (expected 1)" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
# Test D: empty title → error
II_D=0
python3 "$II_PY" '   ' 'Summary' --vault-path "$MIINCUB" 2>/dev/null || II_D=$?
if [[ $II_D -ne 1 ]]; then
  echo "FAIL: empty title exited $II_D (expected 1)" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
# Test E: custom budget caps flow through frontmatter
II_E_OUT="$(python3 "$II_PY" 'Custom budget idea' 'Test custom budgets.' \
  --vault-path "$MIINCUB" \
  --budget-wall-time-sec 60 \
  --budget-web-fetches 1 \
  --budget-tokens 1500 2>&1)"
CUSTOM_DIR=$(echo "$II_E_OUT" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["incubator_dir"])')
if ! grep -qE "^research_budget_wall_time_sec: 60$" "$CUSTOM_DIR/_index.md"; then
  echo "FAIL: custom wall-time budget not honored" >&2
  cat "$CUSTOM_DIR/_index.md" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
if ! grep -qE "^research_budget_web_fetches: 1$" "$CUSTOM_DIR/_index.md"; then
  echo "FAIL: custom web-fetch budget not honored" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
if ! grep -qE "^research_budget_tokens: 1500$" "$CUSTOM_DIR/_index.md"; then
  echo "FAIL: custom token budget not honored" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
# Test F: memory-idea-researcher sub-agent installed
RESEARCHER_MD="$SCRATCH/.claude/agents/memory-idea-researcher.md"
if [[ ! -f "$RESEARCHER_MD" ]]; then
  echo "FAIL: memory-idea-researcher.md not installed at $RESEARCHER_MD" >&2
  rm -rf "$MIINCUB"
  exit 1
fi
RESEARCHER_ANTI="$SCRATCH/.agent/skills/memory-idea-researcher/SKILL.md"
if [[ ! -f "$RESEARCHER_ANTI" ]]; then
  echo "FAIL: memory-idea-researcher antigravity skill-wrap missing at $RESEARCHER_ANTI" >&2
  rm -rf "$MIINCUB"
  exit 1
fi

rm -rf "$MIINCUB"

# ── /memory promote + GC test (plan #7a part 4 task 4) ─────────────────────
# Verify ideas_promote.py promote + gc subcommands:
#   - promote moves _idea-incubator/<slug>/ → personal-projects/<slug>/
#   - promote annotates Ideas.md section with → promoted YYYY-MM-DD
#   - promote with missing slug → exit 1
#   - promote with target collision → exit 1
#   - gc with no entries → scanned: 0
#   - gc with old entry + non-TTY stdin → defaults to keep (never silent delete)
echo "==> /memory promote + GC test (plan #7a part 4 task 4)"
IP_PY="$SCRATCH/.claude/skills/memory/scripts/ideas_promote.py"
if [[ ! -f "$IP_PY" ]]; then
  echo "FAIL: ideas_promote.py not installed at $IP_PY" >&2
  exit 1
fi
MIPROMOTE="$(mktemp -d)"
PROMOTE_IDEAS_DIR="$(mktemp -d)"
PROMOTE_IDEAS_MD="$PROMOTE_IDEAS_DIR/Ideas.md"
# Seed incubator entry + Ideas.md section
python3 "$SCRATCH/.claude/skills/memory/scripts/ideas_incubator.py" \
  'Test promote flow' 'End-to-end promote verification.' \
  --vault-path "$MIPROMOTE" >/dev/null 2>&1
python3 "$SCRATCH/.claude/skills/memory/scripts/ideas_surface.py" \
  'Test promote flow' 'End-to-end promote verification.' \
  --ideas-path "$PROMOTE_IDEAS_MD" --mode silent >/dev/null 2>&1

# Test A: promote happy path
IP_A_OUT="$(IDEAS_SURFACE_PATH="$PROMOTE_IDEAS_MD" python3 "$IP_PY" promote test-promote-flow \
  --vault-path "$MIPROMOTE" --mode silent 2>&1)"
if ! echo "$IP_A_OUT" | grep -qE '"promoted": true'; then
  echo "FAIL: promote did not emit promoted:true. output: $IP_A_OUT" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi
# Dir moved: incubator gone, personal-projects/ present
if [[ -d "$MIPROMOTE/personal-private/_idea-incubator/test-promote-flow" ]]; then
  echo "FAIL: incubator dir still exists after promote" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi
if [[ ! -d "$MIPROMOTE/personal-private/personal-projects/test-promote-flow" ]]; then
  echo "FAIL: personal-projects/test-promote-flow/ not created after promote" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi
# Ideas.md annotation
if ! grep -qE '^→ promoted [0-9]{4}-[0-9]{2}-[0-9]{2} to personal-private/personal-projects/test-promote-flow$' "$PROMOTE_IDEAS_MD"; then
  echo "FAIL: Ideas.md annotation missing or wrong format" >&2
  cat "$PROMOTE_IDEAS_MD" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi
# JSON result includes ideas_annotation: written
if ! echo "$IP_A_OUT" | grep -qE '"ideas_annotation": "written"'; then
  echo "FAIL: promote output did not report ideas_annotation: written" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi

# Test B: promote missing slug → exit 1
IP_B=0
python3 "$IP_PY" promote nonexistent-idea --vault-path "$MIPROMOTE" 2>/dev/null || IP_B=$?
if [[ $IP_B -ne 1 ]]; then
  echo "FAIL: missing slug exited $IP_B (expected 1)" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi

# Test C: promote target collision → exit 1
# Seed another incubator with same slug, then try to promote (should collide
# with the already-promoted personal-projects/test-promote-flow/).
python3 "$SCRATCH/.claude/skills/memory/scripts/ideas_incubator.py" \
  'Test promote flow' 'Second try same title.' \
  --vault-path "$MIPROMOTE" --slug test-promote-flow >/dev/null 2>&1
IP_C=0
python3 "$IP_PY" promote test-promote-flow --vault-path "$MIPROMOTE" 2>/dev/null || IP_C=$?
if [[ $IP_C -ne 1 ]]; then
  echo "FAIL: target collision exited $IP_C (expected 1)" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi

# Test D: gc with no old entries → scanned counts current entries, all fresh
IP_D_OUT="$(python3 "$IP_PY" gc --vault-path "$MIPROMOTE" 2>&1)"
if ! echo "$IP_D_OUT" | grep -qE '"deleted": 0'; then
  echo "FAIL: gc with fresh entries reported deleted > 0" >&2
  echo "    output: $IP_D_OUT" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi

# Test E: gc with non-TTY stdin + force-old entry → defaults to keep (never silent delete)
# Backdate the _index.md mtime to be 1 year old; gc threshold is 6 months;
# entry should be CANDIDATE for prompt; non-TTY stdin → defaults to keep.
OLD_INDEX="$MIPROMOTE/personal-private/_idea-incubator/test-promote-flow/_index.md"
python3 -c "import os, time; os.utime('$OLD_INDEX', (time.time() - 31536000, time.time() - 31536000))"
IP_E_OUT="$(python3 "$IP_PY" gc --vault-path "$MIPROMOTE" 2>&1 </dev/null)"
if ! echo "$IP_E_OUT" | grep -qE '"deleted": 0'; then
  echo "FAIL: gc with non-TTY stdin deleted entries (should default to keep)" >&2
  echo "    output: $IP_E_OUT" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi
# Verify entry still exists
if [[ ! -d "$MIPROMOTE/personal-private/_idea-incubator/test-promote-flow" ]]; then
  echo "FAIL: gc deleted old entry under non-TTY stdin (never-silent-delete contract broken)" >&2
  rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"
  exit 1
fi

rm -rf "$MIPROMOTE" "$PROMOTE_IDEAS_DIR"

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
