---
name: commit-on-stop
description: Safety-branch commit at session end. Fires on Claude Code's Stop event; if the working tree has uncommitted changes, creates `auto-save/<iso-timestamp>` branch and commits all changes there with a greppable message. Never modifies the current branch; never pushes to remote.
kind: hook
supported_hosts: [claude-code]
version: 0.1.0
install_scope: project
---

# commit-on-stop — safety-branch commit at session end

A Stop-event hook that creates a safety branch with the agent's uncommitted work at the end of each turn. Crashed or interrupted sessions stop losing in-flight work; the worst case becomes a stale branch you can recover from.

## How it works

- **Trigger:** Claude Code's `Stop` event (matcher `.*`) — fires at the end of each agent turn.
- **Check:** is the working tree dirty (uncommitted changes per `git status --porcelain`)?
- **If clean:** exit 0 (no-op). Nothing to save.
- **If dirty:**
  1. Capture UTC timestamp: `auto-save/<YYYYMMDDTHHMMSSZ>`.
  2. Stash all changes (including untracked).
  3. Create the safety branch from current HEAD: `git branch auto-save/<ts>`.
  4. Switch to the safety branch.
  5. Pop the stash (restores the changes on the safety branch).
  6. Commit all changes with message `auto-save: stop at <ts> on branch <original-branch>`.
  7. Switch back to the original branch (working tree is now clean there — the changes are committed on the safety branch).
- **Exit 0** with stderr message naming the safety branch.

After the hook fires:

- HEAD is back on the original branch with a clean working tree.
- The work is preserved as a commit on `auto-save/<ts>`.
- Recovery: `git checkout auto-save/<ts>` (or `git diff <orig-branch>` to see what was saved).

## Operator usage — recovery

```bash
# See all safety branches
git branch -a | grep auto-save

# Inspect one
git checkout auto-save/20260513T230400Z
git diff main

# Or cherry-pick the saved commit back onto your working branch
git checkout main
git cherry-pick auto-save/20260513T230400Z
```

## Operator usage — cleanup

`auto-save/*` branches accumulate. Periodically:

```bash
# List safety branches older than a week (manual cleanup)
git for-each-ref --format='%(refname:short) %(committerdate:iso8601)' refs/heads/auto-save/

# Delete a specific one
git branch -D auto-save/20260513T230400Z

# Or nuke all of them at once (if you're sure you don't need any)
git branch | grep auto-save/ | xargs git branch -D
```

Auto-cleanup is **not** part of v0.7.0 — operators manage their own safety-branch hygiene. A future plan may add an opt-in cleanup script.

## What it never does

- **Never pushes to remote.** Local-only safety net. Pushing is an operator decision.
- **Never modifies the current branch.** All changes go on `auto-save/<ts>`; original branch points where it did before.
- **Never silently amends history.** Each invocation creates a new safety branch with a new commit.
- **Never runs in a non-git directory.** Exit 0 if `git rev-parse --is-inside-work-tree` fails.

## Commit identity

The hook commits as:

- `user.name = "commit-on-stop hook"`
- `user.email = "commit-on-stop@agent-toolkit.local"`

These are scoped to the single commit via `git -c user.email=... -c user.name=...` — they don't pollute `git config`. The commits are also unsigned (`commit.gpgsign=false`) since the hook runs non-interactively and signing prompts would hang.

## Triggers (v0.7.0)

- **Stop event only.** Fires at the end of each agent turn.

A future enhancement may add a `PostToolUse` trigger that fires after N consecutive tool errors (configurable via `COMMIT_ON_STOP_ERROR_THRESHOLD` env var). v0.7.0 ships the `Stop` trigger only; the N-errors variant is deferred to a follow-up plan.

## Failure modes

- **git missing:** silently exits 0. Hook is a no-op.
- **Not a git work tree:** silently exits 0.
- **`git stash pop` conflict** (e.g. partial-stash edge case): the hook leaves the operator on the safety branch with the conflict to resolve, and the stderr message names the safety branch. Operator resolves the conflict manually.
- **`git branch auto-save/<ts>` collides** (two Stop events in the same second): exit non-zero with a stderr message. The earlier branch is preserved; the second turn's changes remain uncommitted. Rare in practice (Stop events don't fire that fast).
- **`.claude/settings.json` malformed:** hooks won't load. Validate JSON.

## See also

- [`kill-switch`](../kill-switch/hook.md) — companion emergency-halt hook.
- [`steer`](../steer/hook.md) — companion mid-run-redirect hook.
- [How to use the base hooks](../../wiki/how-to/Use-The-Base-Hooks.md) — practical scenarios for all three.
- [ADR 0003 — base operator hooks](../../wiki/explanation/decisions/0003-base-operator-hooks.md) — design rationale.
