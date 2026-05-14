#!/usr/bin/env bash
# commit-on-stop — safety-branch commit at session end.
#
# Fires on Claude Code's Stop event. If the working tree has uncommitted
# changes, creates auto-save/<iso-timestamp> branch and commits all changes
# there with a greppable message. Returns HEAD to the original branch with
# a clean working tree.
#
# Recovery:
#   git checkout auto-save/<timestamp>
#
# See hook.md in this directory for full documentation.

set -euo pipefail

# Skip if git unavailable or not in a git work tree.
if ! command -v git >/dev/null 2>&1; then
    exit 0
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    exit 0
fi

# Skip if working tree clean — nothing to save.
if [[ -z "$(git status --porcelain)" ]]; then
    exit 0
fi

ts="$(date -u +%Y%m%dT%H%M%SZ)"
orig_branch="$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD)"
safety_branch="auto-save/${ts}"
msg="auto-save: stop at ${ts} on branch ${orig_branch}"

echo "commit-on-stop: saving dirty tree on '${orig_branch}' -> ${safety_branch}" >&2

# Stash everything (including untracked); create safety branch; switch to it;
# restore the changes there; commit; switch back to original branch.
git stash push --include-untracked --quiet -m "commit-on-stop-${ts}"
git branch "${safety_branch}"
git checkout --quiet "${safety_branch}"
git stash pop --quiet
git add -A
git -c commit.gpgsign=false \
    -c user.email="commit-on-stop@agent-toolkit.local" \
    -c user.name="commit-on-stop hook" \
    commit --quiet -m "${msg}"
git checkout --quiet "${orig_branch}"

echo "commit-on-stop: saved -> ${safety_branch}. Recover: git checkout ${safety_branch}" >&2
exit 0
