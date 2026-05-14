---
name: kill-switch
description: Operator emergency halt for long-running agent sessions. Fires on PreToolUse (matcher `.*`); if `.harness/STOP` exists in the project root, blocks the tool call with a stderr message. Touch the file to halt, remove it to resume.
kind: hook
supported_hosts: [claude-code]
version: 0.1.0
install_scope: project
---

# kill-switch — operator emergency halt

A PreToolUse hook that gives you precise control over a long-running agent session: touch a file to halt all tool execution, remove it to resume. No session restart needed.

## How it works

- **Trigger:** Claude Code's `PreToolUse` event with matcher `.*` (every tool call).
- **Check:** does `<project-root>/.harness/STOP` exist?
- **If yes:** print a halt message to stderr and exit with code 2. Claude Code surfaces the stderr to the agent and blocks the tool call.
- **If no:** exit 0 (no-op). The tool call proceeds normally.

The hook runs in the project root (the directory Claude Code was invoked from), so `.harness/STOP` is checked there.

## Operator usage

**To halt all tool execution:**

```bash
touch .harness/STOP
```

The next tool call sees the halt message and refuses to proceed. The agent learns the session is halted; further tool calls will keep failing until the file is removed.

**To resume:**

```bash
rm .harness/STOP
```

The next tool call proceeds normally.

**When to reach for it:**

- The agent is in a runaway iteration loop and you want to stop it without closing the session.
- The agent is about to do something destructive and you want to halt mid-thought.
- You need to take over manually for a step without ending the session.

## Interaction with `steer`

`kill-switch` and `steer` both fire on `PreToolUse`. They run in **alphabetical install order** (`commit-on-stop` < `kill-switch` < `steer`; only `kill-switch` and `steer` share PreToolUse). This means:

- **`kill-switch` runs first.** If `.harness/STOP` is present, the tool call is blocked before `steer` reads `.harness/STEER.md`.
- This ordering is **load-bearing**: a halt must take precedence over a steer.

Hook ordering within an event is documented as alphabetical install order. If Claude Code ever changes hook event semantics, re-audit this invariant (see [ADR 0003](0003-base-operator-hooks)).

## File location (v0.7.0)

Per-repo only: `<project-root>/.harness/STOP`. Device-scope (`~/.harness/STOP` halting all sessions globally) is deferred to a future `dev-machine-setup` plan.

## Failure modes

- **Hook script missing or not executable:** Claude Code logs the hook-call error but does not block the tool call. The agent proceeds normally. Re-run `bash agent-toolkit/install.sh --update <project>` to restore.
- **`.claude/settings.json` malformed:** Claude Code refuses to load any hooks. Validate JSON with `python3 -m json.tool .claude/settings.json`.
- **`.harness/STOP` is a directory or symlink:** `[[ -f ... ]]` only matches regular files. A directory or symlink at that path causes the hook to behave as if STOP is absent. Don't create non-file entries at `.harness/STOP`.

## Manual equivalent for other hosts

Antigravity and Gemini CLI have no first-class hook surface today (v0.7.0). The manual equivalent on those hosts:

- **Antigravity:** add an always-on rule that says *"before each step, check whether `.harness/STOP` exists. If yes, halt and inform the operator."* The agent reads the rule on each step.
- **Gemini CLI:** include the same instruction in the agent's operator prompt or `AGENTS.md` so the agent self-checks.

These manual equivalents are best-effort (the agent has to remember to check) and don't have the precision of the Claude Code hook (which fires before every tool call). Use Claude Code for the strongest kill-switch guarantee.

## See also

- [`steer`](../steer/hook.md) — companion mid-run-redirect hook.
- [`commit-on-stop`](../commit-on-stop/hook.md) — companion safety-branch hook.
- [How to use the base hooks](../../wiki/how-to/Use-The-Base-Hooks.md) — practical scenarios for all three.
- [ADR 0003 — base operator hooks](../../wiki/explanation/decisions/0003-base-operator-hooks.md) — design rationale.
