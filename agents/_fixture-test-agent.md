---
name: _fixture-test-agent
description: Temporary fixture for task 1 of plan #3 — exercises the toolkit's kind=agent installer dispatch end-to-end. Replaced by the real evaluator agent in task 2.
kind: agent
supported_hosts: [claude-code, antigravity, gemini-cli]
version: 0.1.0
install_scope: either
deprecated: Temporary fixture for installer-path verification; remove in task 2 of plan #3 when evaluator.md lands.
---

# _fixture-test-agent

Temporary fixture used during task 1 of plan #3 to exercise the toolkit's
`kind: agent` installer dispatch end-to-end across Claude Code, Antigravity,
and Gemini CLI host destinations.

This file is **replaced by** `agent-toolkit/agents/evaluator.md` in task 2 of
the same plan. If you see this file in a tagged release, that's a bug — task 2
should have removed it before the v0.6.0 release pair landed.

## Tool allowlist

`[Read, Glob, Grep]` — read-only. Mirrors the evaluator's intended allowlist so
the fixture exercises the same per-host wiring the real evaluator will use.

## Body

This is a placeholder. The real evaluator's body (input contract, output
contract, workflow, failure modes, examples) lands in task 2.
