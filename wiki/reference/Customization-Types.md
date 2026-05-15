# Customization types reference

The 12 primitive types `agent-toolkit` recognizes via its `kind` field. Each maps to a subdirectory in the repo and a destination path per host.

## ⚡ Quick Reference

| Kind | Subdir | What it is | Hosts that consume it |
|---|---|---|---|
| `bundle` | `bundles/` | Multi-primitive package; manifest enumerates contents | (dispatches per content kind) |
| `skill` | `skills/` | Agent-invoked helper (`SKILL.md` body + optional scripts dir) | claude-code, antigravity, gemini-cli |
| `command` | `commands/` | User-invokable slash command | claude-code, gemini-cli |
| `agent` | `agents/` | Specialized sub-agent for fan-out work | claude-code, antigravity, gemini-cli |
| `hook` | `hooks/` | Pre/post tool-call shell script (e.g. [`kill-switch`, `steer`, `commit-on-stop`](Use-The-Base-Hooks)) | claude-code (today) |
| `mcp-server` | `mcp-servers/` | MCP server config + launcher | claude-code, gemini-cli (Antigravity: TBD) |
| `status-line` | `status-line/` | Custom status line display | claude-code |
| `output-style` | `output-styles/` | Output formatting template | claude-code |
| `workflow` | `workflows/` | Antigravity multi-step workflow | antigravity |
| `rule` | `rules/` | Antigravity always-on rule | antigravity |
| `snippet` | `snippets/` | Fragment appended to `AGENTS.md` / `CLAUDE.md` at install time | all 3 |
| `settings-fragment` | `settings-fragments/` | JSON fragment merged into host `settings.json` | claude-code, gemini-cli (Antigravity: TBD) |

## Implementation status

| Kind | Installer support | Notes |
|---|---|---|
| `bundle` | ✅ (dispatches to inner primitives) | `skill`, `agent`, and `hook` kinds inside bundles are wired as of v0.7.0 |
| `skill` | ✅ (v0.5.0) | Full dispatch to `.claude/skills/<name>/`, `.agent/skills/<name>/`, `.agents/skills/<name>/` |
| `agent` | ✅ (v0.6.0) | Full dispatch to `.claude/agents/<name>.md`, `.agent/skills/<name>/SKILL.md` (sub-agent-as-skill wrap for Antigravity), `.gemini/agents/<name>.md` |
| `hook` | ✅ (v0.7.0, claude-code only) | Full dispatch to `.claude/hooks/<name>.{sh,ps1}` **plus** idempotent deep-merge of the hook's `settings-fragment-{bash,pwsh}.json` into `.claude/settings.json` via `scripts/merge-settings-fragment.py`. Other hosts have no first-class hook surface today. |
| All others | ⚠️ Warning "not yet supported — skipped" | Future toolkit versions add them as the catalog grows |

When a customization with an unsupported kind is encountered, the installer logs a warning and continues. The manifest still passes validation — the `kind` enum recognizes the value, the dispatch logic just doesn't have a handler yet.

## What goes where

### When to use a `skill` vs. `command` vs. `agent`

| You want… | Use |
|---|---|
| An agent-triggered helper that runs on a keyword or context match (e.g. [`design`](Use-The-Design-Skill), [`pii-scrubber`](https://github.com/alexherrero/agent-toolkit/blob/main/skills/pii-scrubber/SKILL.md)) | `skill` |
| A user-typed `/something` slash command | `command` |
| A specialized agent for a specific kind of task (e.g. [`evaluator`](Use-The-Evaluator), `explorer`) | `agent` |

A single concept can ship as multiple primitives — e.g. an [`evaluator`](Use-The-Evaluator) agent + a `quality-gates` bundle that references it from a skill that auto-invokes it.

### When to use a `bundle` vs. multiple standalone primitives

| You want… | Use |
|---|---|
| One coherent unit with multiple primitive types (e.g. skill + hook + agent that work together) | `bundle` |
| Multiple independent customizations | Multiple standalone primitives |

A bundle is right when the primitives **depend on each other** — installing one without the others would break the design. If the primitives are independently useful, ship them standalone.

### Bundle directory layout

```
bundles/<bundle-name>/
├── bundle.md                                # manifest + bundle-level doc
├── skills/<inner-name>/SKILL.md             # one inner skill (kind: skill)
├── hooks/<inner-name>.sh                    # one inner hook (kind: hook)  
└── agents/<inner-name>.md                   # one inner agent (kind: agent)
```

The bundle's `contents:` list enumerates each inner primitive:

```yaml
contents:
  - skill: <inner-name>
  - hook: <inner-name>
  - agent: <inner-name>
```

The installer resolves each entry by walking the bundle's matching subdir and dispatching to the right host destinations.

## Related

- [Manifest Schema](Manifest-Schema) — the YAML frontmatter contract.
- [Per-Host Paths](Per-Host-Paths) — destination paths per kind per host.
- [Add a Skill](Add-A-Skill) / [Add a Bundle](Add-A-Bundle) — practical recipes.
