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

# ── post-install integrity ──────────────────────────────────────────────────
echo "==> post-install integrity"
bash "$TOOLKIT_ROOT/scripts/check-integrity-bash.sh" "$SCRATCH"

echo "==> smoke-install-bash: OK"
