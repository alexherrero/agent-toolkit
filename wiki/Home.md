# agent-toolkit Wiki

Dogfood documentation for `agent-toolkit` — a personal collection of agent customizations across Claude Code, Antigravity, and Gemini CLI. Sibling repo to [`agentic-harness`](https://github.com/alexherrero/agentic-harness). Every page is written for a single reader intent (learn / do / look up / understand) per the Diátaxis convention.

> [!NOTE]
> Repo: [github.com/alexherrero/agent-toolkit](https://github.com/alexherrero/agent-toolkit). Public, MIT-licensed. PII guardrails (script + skill + pre-push hook) are foundational — see [Purpose and scope](Purpose-And-Scope) for why.

## 📚 New here? Learn by doing.

- [Tutorial 1 — Your first customization](01-First-Customization) — add a hello-world skill, install it into a scratch project, see it land at three host paths. ~10 minutes.

## 🔧 Trying to do something specific?

- [Install agent-toolkit into a project](Install-Into-Project) — drop the shipped customizations into a target project.
- [Add a skill](Add-A-Skill) — add a new standalone skill.
- [Add a bundle](Add-A-Bundle) — package multiple primitives that ship together.
- [Use the evaluator](Use-The-Evaluator) — dispatch the `evaluator` sub-agent for PASS / NEEDS_WORK grading against a precise rubric.
- [Use the base hooks](Use-The-Base-Hooks) — kill-switch, steer, commit-on-stop. Operator-precision control for long-running Claude Code sessions.
- [Use the design skill](Use-The-Design-Skill) — `/design author` walks the 10-section template, `/design translate` splits into parts, `/design sequence` generates a PLAN.md per part. Hand-off to harness `/work` + `/review` for execution.

## 📖 Looking up a detail?

- [Customization Types](Customization-Types) — what each of the 11 kinds means and where to put them.
- [Manifest Schema](Manifest-Schema) — YAML frontmatter contract.
- [Per-Host Paths](Per-Host-Paths) — destination paths per kind per host.
- [Installer CLI](Installer-CLI) — flags, prereqs, exit codes.

## 💡 Want to know why?

- [Purpose and scope](Purpose-And-Scope) — what this repo is for, what it's not.

### Architecture decisions

- [ADR 0001 — agent-toolkit purpose, scope, public-with-PII-guardrails](0001-agent-toolkit-purpose)
- [ADR 0002 — evaluator sub-agent design](0002-evaluator-design)
- [ADR 0003 — base operator-control hooks](0003-base-operator-hooks)
- [ADR 0004 — design skill: human-facing design pipeline → agent execution handoff](0004-design-skill)

## Conventions

Page templates, filename rules, and the Diátaxis four-mode split mirror the sibling repo's documentation convention — see [agentic-harness/harness/documentation.md](https://github.com/alexherrero/agentic-harness/blob/main/harness/documentation.md). The mode-purity lint (`scripts/check-wiki.py --strict`) is the same.
