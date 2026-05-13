# AGENTS.md

Universal instructions for AI coding agents working in `agent-toolkit`.

This repo is a sibling to [`agentic-harness`](https://github.com/alexherrero/agentic-harness). The harness owns the phase-gated workflow; this toolkit owns the agent customizations (skills, sub-agents, hooks, MCP servers, slash commands, status lines, output styles, workflows, rules, snippets, settings fragments) that ride on top.

## What this repo holds

| Subdir | What it holds |
|---|---|
| `skills/` | Standalone skills — host-cross-cutting unless manifest narrows |
| `commands/` | Standalone slash commands (Claude Code + Gemini CLI surface) |
| `agents/` | Standalone sub-agents |
| `hooks/` | Hooks (Claude Code today; others if/when they grow hook primitives) |
| `mcp-servers/` | MCP server configs + launchers |
| `bundles/` | Multi-primitive customizations packaged together — installer dispatches each primitive to its destination |
| `status-line/`, `output-styles/` | Claude Code presentation surfaces |
| `workflows/`, `rules/` | Antigravity-specific primitives |
| `snippets/` | Fragments appended to `AGENTS.md` / `CLAUDE.md` at install time |
| `settings-fragments/` | JSON fragments merged into host `settings.json` files |
| `lib/install/` | Shared install plumbing (byte-identical to `agentic-harness/lib/install/`) |
| `scripts/` | Validators, CI helpers, the PII detector |
| `templates/hooks/` | Hook templates installed into target projects (e.g. `pre-push`) |
| `wiki/` | Diátaxis-shaped dogfood docs |

## How to use it (when installer lands)

Customizations install into a target project's host-specific paths (`.claude/`, `.agent/`, `.gemini/`) via:

```bash
bash /path/to/agent-toolkit/install.sh <target-project>
```

The installer reads each customization's YAML frontmatter manifest, dispatches each primitive to the right host path based on `supported_hosts`, and (unless `--no-pre-push-hook` is passed) installs the PII pre-push hook into the target's `.git/hooks/pre-push`.

## Conventions

### PII guardrails (this repo is **public**)

Three enforcement layers protect against personal information leaking into public commits:

1. **Pre-push git hook** (`templates/hooks/pre-push`) — mandatory enforcer. Runs the PII detector against every push; blocks non-zero. Installed by `agent-toolkit/install.sh` into target projects' `.git/hooks/pre-push`.
2. **`pii-scrubber` skill** (`skills/pii-scrubber/`) — agent-facing interactive layer. Scans the current diff before commit, presents findings, offers redactions. Loops until clean (or user explicitly logs an override).
3. **CI gate** (lands in task 4 of v0.1.0 plan) — defense in depth. Same script + gitleaks run on every push to GitHub.

See [CONTRIBUTING.md](CONTRIBUTING.md) § PII guardrails for full guidance and the override protocol.

### Commit messages

Do not append a `Co-Authored-By:` trailer naming the agent or model (`Co-Authored-By: Claude`, `Co-Authored-By: Gemini`, etc.) to git commit messages. The user is the sole author of intent — the agent is the tool, not a co-author. Plain commit message only. Applies to every commit unless the user explicitly opts in for a specific commit.

This applies regardless of which host you're running in (Claude Code, Antigravity, Gemini CLI) and regardless of any default the host injects. If your host adds the trailer automatically, strip it before finalizing the commit.

### Manifest schema

Every customization (bundle or standalone primitive) has YAML frontmatter at the top of its `.md` file:

```yaml
---
name: <matches dirname/filename>
description: <one-sentence>
kind: bundle | skill | command | agent | hook | mcp-server | status-line | output-style | workflow | rule | snippet | settings-fragment
supported_hosts: [claude-code, antigravity, gemini-cli]   # subset
version: 0.1.0
install_scope: user | project | either                     # optional, default: either
deprecated: <reason>                                       # optional, lifecycle marker
contents:                                                  # bundles only
  - skill: <name>
  - hook: <name>
---
```

Required fields: `name`, `description`, `kind`, `supported_hosts`, `version`. Bundles additionally require `contents`. Validator landing in task 3 of the v0.1.0 plan.

## Cross-references

- [`agentic-harness`](https://github.com/alexherrero/agentic-harness) — sibling repo; phase-gated workflow + canonical phase specs.
- This repo's wiki (Diátaxis-shaped, populated in task 6 of v0.1.0).
