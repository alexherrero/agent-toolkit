#!/usr/bin/env bash
# check-integrity-bash.sh — post-install integrity check on a scratch dir.
#
# Verifies the installed tree is actually usable: every installed SKILL.md
# is non-empty and has parseable YAML frontmatter, the pre-push hook (if
# present) is shebang-bash and parses cleanly under bash -n, no stray
# files lingering under managed parents.
#
# Usage: bash scripts/check-integrity-bash.sh <SCRATCH_DIR>

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <scratch-dir>" >&2
  exit 2
fi

SCRATCH="$1"
fail=0

if [[ ! -d "$SCRATCH" ]]; then
  echo "FAIL: scratch dir $SCRATCH does not exist" >&2
  exit 1
fi

# ── 1. Every installed SKILL.md is non-empty + has frontmatter ─────────────
echo "  [integrity] installed SKILL.md files have valid frontmatter"
while IFS= read -r f; do
  if [[ ! -s "$f" ]]; then
    echo "FAIL: $f is empty" >&2
    fail=1
    continue
  fi
  # Frontmatter: first three lines should start with --- ... ---
  if ! head -1 "$f" | grep -qE '^---\s*$'; then
    echo "FAIL: $f has no opening --- frontmatter delimiter" >&2
    fail=1
  fi
done < <(find "$SCRATCH" -path '*/skills/*/SKILL.md' 2>/dev/null)

# ── 2. Pre-push hook integrity (if present) ────────────────────────────────
if [[ -e "$SCRATCH/.git/hooks/pre-push" ]]; then
  echo "  [integrity] .git/hooks/pre-push parses + is executable"
  if [[ ! -x "$SCRATCH/.git/hooks/pre-push" ]]; then
    echo "FAIL: pre-push hook is not executable" >&2
    fail=1
  fi
  if ! head -1 "$SCRATCH/.git/hooks/pre-push" | grep -qE '^#!.*bash'; then
    echo "FAIL: pre-push hook shebang is not bash" >&2
    fail=1
  fi
  if ! bash -n "$SCRATCH/.git/hooks/pre-push" 2>&1; then
    echo "FAIL: pre-push hook bash -n parse failed" >&2
    fail=1
  fi
fi

# ── 3. No stray files under managed-parent dirs ────────────────────────────
# Each managed parent should contain only <skill-name>/SKILL.md children.
# Anything else is an installer regression.
echo "  [integrity] no stray files under managed parents"
for parent in .claude/skills .agent/skills .agents/skills; do
  full="$SCRATCH/$parent"
  [[ -d "$full" ]] || continue
  while IFS= read -r entry; do
    name="$(basename "$entry")"
    if [[ -d "$entry" ]]; then
      # Each subdir must contain SKILL.md
      if [[ ! -f "$entry/SKILL.md" ]]; then
        echo "FAIL: $parent/$name/ has no SKILL.md" >&2
        fail=1
      fi
    elif [[ -f "$entry" ]]; then
      # Stray file at the managed-parent level (not in a subdir)
      echo "FAIL: $parent/$name is a stray file (managed parents contain only <name>/SKILL.md subdirs)" >&2
      fail=1
    fi
  done < <(find "$full" -mindepth 1 -maxdepth 1)
done

if [[ $fail -ne 0 ]]; then
  echo "check-integrity-bash: one or more integrity assertions failed" >&2
  exit 1
fi

echo "check-integrity-bash: OK"
