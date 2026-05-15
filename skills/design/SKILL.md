---
name: design
description: Human-facing design pipeline that walks the user through a locked 10-section design-doc template, gates on human approval (Status draft → review → final), then translates the approved design into structural parts and generates a PLAN.md per part for the harness's `/work` + `/review` flow to execute. Published designs surface in `wiki/Home.md` as the canonical "Why we built X" entry point.
kind: skill
supported_hosts: [claude-code, antigravity, gemini-cli]
version: 0.1.0
install_scope: project
---

# design — human-facing design pipeline → agent execution handoff

A skill that runs the **front** of a project: the design phase a human cares about. Walks the user through a precise 10-section design-doc template, gates on human approval, then hands the approved design off to the harness's `/work` + `/review` flow as one or more `PLAN.md` files (one per structural part).

**Position vs. the harness's `/plan`:** `/plan` expects a brief and emits tasks — good for "I know what I want, give me a task breakdown." This skill starts *earlier*: it walks you through assembling a real design doc in a specific structured shape, then uses that same shape to drive the breakdown. Reach for `/design` when the problem is ambiguous, has multiple stakeholders, or needs Quality Attributes / Operations thinking before code starts. Reach for `/plan` when the design is already settled.

## Sub-commands

The skill exposes three sub-commands, dispatched by the host's slash-command surface:

| Sub-command | Inputs | Outputs | Status gate |
|---|---|---|---|
| `/design author` | Slug + Visibility | Design doc at `wiki/explanation/designs/<slug>.md` (published) or `.harness/designs/<slug>.md` (confidential) | Drives `draft → review → final` |
| `/design translate` | A `Status: final` design doc | Structural-part files at `<doc-dir>/parts/<part-slug>.md` | Requires `Status: final` (hard gate) |
| `/design sequence` | A populated `<doc-dir>/parts/` directory | One `PLAN.md` per part (first activated; rest queued) | Requires `Status: final` |

**Status `launched`** is set by the harness `/release` flow when the last part's PLAN.md completes — the design skill does not transition to `launched` directly.

### `/design author` *(stub — full body lands in task 2 of plan #6)*

Walks the human through the 10-section template at [`templates/design-doc.md`](templates/design-doc.md) section by section. Prompts for each Quality Attribute sub-attribute (11 total) and forces an explicit N/A-with-rationale if the design has no concerns in that dimension. Saves after every section so partial drafts survive session interruption. Transitions Status `draft → review` on human signal, `review → final` on explicit approval.

### `/design translate` *(stub — full body lands in task 3 of plan #6)*

Reads a `Status: final` design doc and proposes a split of the Detailed Design into N structural parts (one per top-level subsection by default; human can merge / split / reshape). Writes `<doc-dir>/parts/<part-slug>.md` files with: inherited frontmatter, part-specific Title / Scope / Dependencies on other parts / Verification criteria. Appends to Document History.

### `/design sequence` *(stub — full body lands in task 4 of plan #6)*

Topologically sorts the parts by their declared dependencies and generates one `PLAN.md` per part using the harness's existing `templates/PLAN.md` shape. First part's plan activates at `.harness/PLAN.md`; subsequent parts queue in `.harness/designs/<doc-slug>/queued-plans/`. Harness `/release` auto-promotes the next queued plan when the active plan completes.

## Tool allowlist

**`Read, Write, Edit, Glob, Grep` only.** No `Bash`, no `NotebookEdit`. The skill's job is file authorship + structured edits — not shell invocation. Bash invocation, if needed downstream, comes from the harness `/work` phase during stage 5 (per-part execution).

## File conventions

- **Template:** `agent-toolkit/skills/design/templates/design-doc.md` (ships with the skill). The `/design author` flow copies this template into the target project as the starting point for a new design.
- **Confidential designs:** `.harness/designs/<slug>.md` — gitignored, machine-local; not committed to a public repo. Use for early exploration, internal-only designs.
- **Published designs:** `wiki/explanation/designs/<slug>.md` — committed; surfaces in `wiki/Home.md` + `wiki/_Sidebar.md` as the canonical "Why we built X" entry point per ADR 0004 (lands in task 6 of plan #6).
- **Parts:** `<doc-dir>/parts/<part-slug>.md` — same dir as the parent design doc, in a `parts/` subdir.
- **Queued plans:** `.harness/designs/<doc-slug>/queued-plans/<part-slug>.PLAN.md` — waiting in the wings until harness `/release` promotes the next one.

## Status lifecycle

| State | Set by | Meaning |
|---|---|---|
| `draft` | `/design author` (initial creation) | Authoring in progress; not ready for review. |
| `review` | `/design author` (human signals readiness) | Author thinks it's done; awaiting human approval. |
| `final` | `/design author` (explicit human approval) | Approved. **Hard gate:** `/design translate` and `/design sequence` only run on `Status: final`. |
| `launched` | Harness `/release` (last queued part's PLAN.md hits `Status: done`) | All structural parts shipped. The design's full execution arc is complete. |

`Status` is set by the skill; users don't edit it by hand.

## When to reach for it

- **Use `/design`** when: the problem is ambiguous, multiple stakeholders need to align, the change has cross-cutting Quality Attributes (security/reliability/scalability/etc.) or Operations (SLAs/monitoring/rollback) concerns that need explicit thinking before code starts, or you want a canonical "Why we built X" wiki entry point.
- **Use `/plan` instead** when: the problem is already well-scoped, you can name the verification criteria in one sentence per task, and the change is fully contained to code (no ops / no rollout complexity).
- **Use both** when: you're standing up something substantial that will ship in multiple parts. Run `/design author` → `/design translate` → `/design sequence` once; then `/work` cycles through each part's PLAN.md tasks.

## Cross-references

- [Use-The-Design-Skill](../../wiki/how-to/Use-The-Design-Skill.md) — practical recipe with three worked scenarios *(lands in task 6 of plan #6)*
- [ADR 0004 — Design skill design](../../wiki/explanation/decisions/0004-design-skill.md) — locked design calls + rationale + consequences *(lands in task 6 of plan #6)*
- Template: [`templates/design-doc.md`](templates/design-doc.md) — the 10-section structure all `/design author` flows write against
- agentic-harness phases: [`/work`](https://github.com/alexherrero/agentic-harness/blob/main/harness/phases/03-work.md), [`/release`](https://github.com/alexherrero/agentic-harness/blob/main/harness/phases/05-release.md) — execute the per-part PLAN.md files generated by `/design sequence`
