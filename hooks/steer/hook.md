---
name: steer
description: Mid-run redirect — write `.harness/STEER.md` with a "do it this way instead" instruction and the next tool call picks it up. The hook reads STEER.md's contents (which Claude Code injects into the agent's context) then renames the file to STEER.consumed-<iso-ts>.md for audit trail.
kind: hook
supported_hosts: [claude-code]
version: 0.1.0
install_scope: project
---

# steer — inject mid-run guidance without restart

A PreToolUse hook that lets you redirect a running agent session without closing it. Write a brief instruction to `.harness/STEER.md`; the next tool call picks it up and the file is renamed for an audit trail.

## How it works

- **Trigger:** Claude Code's `PreToolUse` event with matcher `.*` (every tool call).
- **Check:** does `<project-root>/.harness/STEER.md` exist?
- **If yes:** print the file's contents to stdout (Claude Code captures the stdout and injects it into the agent's context for the upcoming tool call), then rename the file to `.harness/STEER.consumed-<iso-timestamp>.md`. Exit 0.
- **If no:** exit 0 (no-op).

The audit-trail rename preserves a record of every steer that was injected, with timestamps. The `consumed-*.md` files accumulate in `.harness/`; periodically delete or `git mv` them as you'd prefer.

## Operator usage

**To inject guidance mid-run:**

```bash
echo "Actually, please use the existing helper in src/utils.py instead of writing a new one." > .harness/STEER.md
```

On the next tool call, the agent sees the instruction in context. The file gets renamed to `STEER.consumed-20260513T230400Z.md` (UTC timestamp) for the audit trail.

**Multi-line guidance:**

```bash
cat > .harness/STEER.md <<'EOF'
Three corrections:
1. The test file should live at tests/test_parser.py, not src/test_parser.py.
2. Don't add new imports of `os.system` — use `subprocess.run` instead.
3. The acceptance criterion at line 47 of the spec needs an explicit test.
EOF
```

**When to reach for it:**

- You realize the agent is heading the wrong direction and want to redirect without restarting the session.
- You spot a mistake the agent should fix on its next step.
- You want to add context the agent didn't have at the start of the session.

## Interaction with `kill-switch`

`kill-switch` and `steer` both fire on `PreToolUse`. They run in **alphabetical install order**: `kill-switch` first, `steer` second. This means:

- If `.harness/STOP` is present, `kill-switch` blocks the tool call **before** `steer` reads `.harness/STEER.md`. The steer file is left untouched.
- If you want to halt **and** steer for the next-attempted call, halt first (touch STOP), write STEER.md, then remove STOP. Next tool call: kill-switch passes, steer fires.

This ordering is documented as a load-bearing invariant — see [ADR 0003](0003-base-operator-hooks).

## Audit trail

After a steer fires, `.harness/STEER.consumed-<ts>.md` files accumulate. Use them for:

- **Forensics:** what redirects did I give the agent, and when?
- **Pattern detection:** if you steer the same way three sessions in a row, that's a signal to update `AGENTS.md` / `CLAUDE.md` with the pattern.
- **Cleanup:** `rm .harness/STEER.consumed-*.md` when you don't need the history.

## File location (v0.7.0)

Per-repo only: `<project-root>/.harness/STEER.md`. Device-scope is deferred.

## Failure modes

- **STEER.md unwritable / unreadable:** the hook can't read it; falls through to no-op. Check file permissions.
- **STEER.md is a directory:** `[[ -f ... ]]` only matches regular files. The hook treats it as absent and doesn't try to read.
- **Filesystem race:** if you write STEER.md while a tool call is mid-flight, the hook may or may not pick it up on this call — but it WILL pick it up on the next. Single-session, single-operator assumption.
- **`.claude/settings.json` malformed:** hooks won't load. Validate JSON.

## Manual equivalent for other hosts

- **Antigravity:** add an always-on rule: *"before each step, check `.harness/STEER.md`. If it exists, treat its contents as a redirect and rename the file with a timestamp."* Best-effort; agent has to remember.
- **Gemini CLI:** include the same instruction in the operator prompt or `AGENTS.md`.

## See also

- [`kill-switch`](../kill-switch/hook.md) — companion emergency-halt hook.
- [`commit-on-stop`](../commit-on-stop/hook.md) — companion safety-branch hook.
- [How to use the base hooks](../../wiki/how-to/Use-The-Base-Hooks.md) — practical scenarios for all three.
- [ADR 0003 — base operator hooks](../../wiki/explanation/decisions/0003-base-operator-hooks.md) — design rationale.
