# agent-toolkit

> Scaffolded 2026-05-12. v0.1.0 in progress. Full README arrives with the v0.1.0 release.

Personal collection of agent customizations — skills, sub-agents, hooks, MCP servers, slash commands, status lines, output styles, workflows, rules, snippets, and settings fragments — across Claude Code, Antigravity, and Gemini CLI.

Sibling repo to [`agentic-harness`](https://github.com/alexherrero/agentic-harness). The harness owns phase-gated workflow; the toolkit owns the customizations that ride on top.

## Status

Scaffold complete. Currently shipping:

- Directory structure for 12 customization-type subdirs
- PII guardrails — `scripts/check-no-pii.sh` (regex detector), `.gitleaks.toml` (gitleaks config), `skills/pii-scrubber/` (agent-facing interactive remediation skill), `templates/hooks/pre-push` (git hook that blocks PII at push time)
- An `example-bundle/` reference skeleton for new contributors

Still to come in v0.1.0:

- Shared install plumbing extracted from `agentic-harness` (task 2)
- Working `install.sh` / `install.ps1` (task 3) — currently stubs
- Manifest validator + CI (tasks 3-4)
- `dependabot-fixer` + `ship-release` skills migrated from agentic-harness (task 5)
- Full README + Diátaxis wiki + cross-repo ADRs (task 6)
- v0.1.0 tag + GitHub release (task 7)

## Install

Coming in task 3. Today the installer is a stub.

When complete:

```bash
bash /path/to/agent-toolkit/install.sh /path/to/your-project
```

## License

MIT. See [LICENSE](LICENSE).
