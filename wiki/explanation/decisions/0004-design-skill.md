# ADR 0004 — Design skill: human-facing design pipeline → agent execution handoff

> [!NOTE]
> **Status:** accepted · **Date:** 2026-05-15 · **Related:** [ADR 0001 — agent-toolkit purpose](0001-agent-toolkit-purpose.md) · [ADR 0002 — evaluator design](0002-evaluator-design.md) · [ADR 0003 — base operator-control hooks](0003-base-operator-hooks.md) · [agentic-harness ADR 0006 — agent-toolkit split](https://github.com/alexherrero/agentic-harness/blob/main/wiki/explanation/decisions/0006-agent-toolkit-split.md)

## Context

Agent-driven development in this personal-dev-env has had four persistent gaps that this design addresses:

1. **The harness `/plan` phase expects a brief and emits tasks.** That works when the problem statement is precise, but it doesn't accommodate the *design phase* a human cares about — where the doc itself is the load-bearing artifact and the agent stays out of the way until the human is ready. Several roadmap items (#7 ContextVault, #8 auto-context, #9 evidence-tracking, #10 quality-gates bundle) need design thinking before they're tasks-shaped. Without a skill for the front of the project, that thinking happens in scratch files that don't survive into the wiki.

2. **Per-step drift in agent-driven execution.** Long-running implementations drift between checkpoints — the agent freelances away from the original intent because there's no per-step contract to grade against. The cwc-long-running-agents pattern documented at `~/ContextVault/domains/anthropic-patterns/cwc-long-running-agents.md` proposed a fresh-context evaluator that grades each step before the human approves moving on. ROADMAP item #3 (Fresh-context evaluator, shipped in toolkit v0.6.0) ships that primitive; the design skill is the natural consumer.

3. **No canonical "Why we built X" wiki entry point.** Today's wiki has ADRs (point-in-time decisions) + how-tos + reference + explanation, but no top-level surface for "here's the comprehensive design we executed against." Readers landing on the wiki Home page can find HOW to do things and WHY a specific decision was made, but not the full design narrative that produced a feature. The user surfaced this gap explicitly during plan #6 framing: *"the original design [should] be the thing highlighted in the wiki/documentation hub as the starting point for anyone looking to understand what was built and why."*

4. **No pattern for cross-cutting Quality Attributes + Operations thinking at design time.** Quality Attributes (security, reliability, scalability, accessibility, etc.) and Operations (SLAs, monitoring, logging, rollback) concerns are best surfaced *before* code starts, not bolted on at release. The user's preferred design-doc shape (locked verbatim 2026-05-14, see Decision §2) makes both sections mandatory with per-sub-attribute N/A-or-describe prompts — catching ops blind spots early.

**Anthropic-pattern reference reading** that informed the design:

- `~/ContextVault/domains/anthropic-patterns/cwc-long-running-agents.md` — fresh-context evaluator pattern (no Write tools, returns PASS/NEEDS_WORK) as the right shape for per-step review during stage 5 execution.
- `~/ContextVault/domains/anthropic-patterns/managed-agents-architecture.md` — Session/Harness/Sandbox decoupling validates the "design doc is the durable artifact; execution is replaceable" framing.

**Open design questions resolved at plan time** (settled 2026-05-14):

- What's the design-doc style? → The user provided the exact 10-section structure (see Decision §2). Locked verbatim.
- How is the skill decomposed? → Hybrid (Decision §1).
- Per-step execution loop? → Reuse harness `/work` + `/review` (Decision §1).
- Sub-design / parts location? → `<doc-dir>/parts/<part-slug>.md` (Decision §3).
- One PLAN.md per part or shared? → One per part (Decision §6).
- Mid-execution design changes? → Human edits design + appends Document History + re-runs translate (Decision §9).
- Skill home? → `agent-toolkit` (Decision §7).

## Decision

Seven locked design calls captured at plan time (2026-05-14):

### §1 — Hybrid decomposition: `/design` skill for stages 1-4 + harness `/work` + `/review` for stage 5

The skill ships with three sub-commands in `agent-toolkit/skills/design/`:

- `/design author` — interactive 10-section authoring (workflow stages 1-2)
- `/design translate` — Status: final doc → N structural parts (stage 3)
- `/design sequence` — parts → PLAN.md per part (stage 4)

**Stage 5 (per-part execution) reuses the harness's existing `/work` + `/review` flow** — no new execution primitives. The harness already has deterministic gates + adversarial-reviewer + evaluator (#3) + kill-switch / steer / commit-on-stop (#4/#5) integrated; the design skill leverages all of that by producing PLAN.md files in the harness's existing template shape.

**Why not the alternatives:**

- **Per-stage skills** (separate `/design`, `/translate`, `/sequence`, `/execute`): considered + rejected because `/execute` would duplicate the harness's existing `/work` phase. More skills to maintain; users have to remember invocation order.
- **One orchestrator skill + sub-agents**: considered + rejected because the orchestrator would get thick and the sub-agent contracts would have to be sharp. The hybrid keeps the toolkit-side surface lean.

### §2 — User's 10-section design-doc template locked verbatim 2026-05-14

The skill embeds the user's specific design-doc pattern, not a generic shape. The template at `agent-toolkit/skills/design/templates/design-doc.md` codifies:

**Frontmatter** (10 fields): title, status (`draft|review|final|launched`), visibility (`confidential|published`), author, contributors, created, updated, last_major_revision, prd, project.

**Body** (10 sections):

1. Context (Objective + Background)
2. Design (Overview + Infrastructure + Detailed Design)
3. Alternatives Considered *(added 2026-05-14 by the user)*
4. Dependencies
5. Migrations
6. Technical Debt & Risks
7. Quality Attributes (11 sub-attrs: Security / Reliability / Data Integrity / Privacy / Scalability / Latency / Abuse / Accessibility / Testability / I18n & L10n / Compliance — each mandatory either with content or N/A-with-rationale)
8. Project management (Work estimates / Documentation Plan / Launch Plans)
9. Operations (SLAs / Monitoring & Alerting / Logging Plan / Rollback Strategy)
10. Document History

**Why not the alternatives:**

- **Define collaboratively as task 1**: considered + rejected because the user had a clear pattern to provide; collaborative drafting would have been make-work given a precise spec was available.
- **Reverse-engineer from an existing doc**: considered + rejected because no existing doc was identified at plan time; the user provided the structure inline.

The template is the load-bearing artifact for tasks 2-7 of plan #6 — sub-command bodies, harness integration, and the how-to all derive from this exact shape.

### §3 — Design doc is the canonical wiki entry point

`visibility: published` design docs live at `wiki/explanation/designs/<slug>.md` and surface in `wiki/Home.md` + `wiki/_Sidebar.md` as the canonical "Why we built X" entry point. Not buried metadata; the headline artifact.

The harness `/release` flow (§1b, agentic-harness v2.3.0) handles the surfacing: when the design's last queued part's `PLAN.md` completes, the design Status transitions `final → launched` and `/release` updates `Home.md` + `_Sidebar.md` to add the design to the wiki's "Designs" section. Idempotent — re-runs are no-op.

**Why not the alternatives:**

- **Design docs as ADRs**: considered + rejected. ADRs are point-in-time decision records (typically narrower than a full design). Design docs are pre-execution authoring artifacts (forward-looking → executed). Both live in `wiki/explanation/` but different lifecycles. A design doc can reference an ADR; not the same artifact.
- **Design docs buried in `wiki/explanation/`**: considered + rejected because that defeats the user's stated goal of making them the headline artifact. The Home + Sidebar surface is explicit.

### §4 — Status lifecycle 4-state machine

Status transitions are skill-driven and harness-driven, never silently auto-advanced:

| State | Set by | Meaning |
|---|---|---|
| `draft` | `/design author` (bootstrap) | Authoring in progress |
| `review` | `/design author` (human signals readiness) | Awaiting review pass |
| `final` | `/design author` (explicit human approval after review pass) | Approved; hard gate for translate + sequence |
| `launched` | Harness `/release` §1b (last queued part's PLAN.md hits Status: done) | Full execution arc complete |

The skill **never transitions backwards**. `review → draft` is a manual escape-hatch documented for stalled reviews; the operator edits the frontmatter Status field directly + appends Document History.

**Why this shape:**

- `draft → review` separation lets the author signal readiness without finalizing — review can take multiple sessions.
- `review → final` as the hard gate means downstream sub-commands have a single check (`Status: final`) rather than a fuzzy "ready enough" judgment.
- `final → launched` only after **execution** completes (not approval) means the wiki "Why we built X" surface reflects shipped reality, not approved intent.

### §5 — Visibility field routes confidential vs. published

The `visibility:` frontmatter field controls the doc's destination + lifecycle:

- `confidential` → `.harness/designs/<slug>.md` (gitignored, machine-local; never enters public repo; doesn't surface in wiki)
- `published` → `wiki/explanation/designs/<slug>.md` (committed; surfaces in wiki on `launched`)

Parts + PLAN.md generation flows identically for both. Visibility only affects the canonical home of the design doc itself + the wiki surfacing decision.

**Why this shape:** the user has both kinds of designs — public-facing work (toolkit + harness features) and internal-only tooling (designs for personal scripts, dev-machine-setup work, etc.). A single skill that handles both via a frontmatter field is cleaner than two parallel skills.

### §6 — One PLAN.md per part (not shared)

Each structural part gets its own `PLAN.md` file. First part topologically activates at `<project>/.harness/PLAN.md`; subsequent parts queue at `<project>/.harness/designs/<doc-slug>/queued-plans/<part-slug>.PLAN.md`. Harness `/release` Case B auto-promotes the next queued plan when the active completes.

**Why not the alternatives:**

- **One shared PLAN.md with sections per part**: considered + rejected. Each part should be independently shippable + reviewable; sharing one PLAN.md couples the parts' lifecycles. The `/work` phase expects one active task at a time, and a single PLAN.md with multiple parts blurs which task is current.

### §7 — Skill ships in `agent-toolkit`, not the harness

`/design` is customization-shaped (an authoring + translation skill that produces artifacts the harness consumes) — not phase-shaped (the harness owns the phase-gated workflow). Per [ADR 0001](0001-agent-toolkit-purpose.md) (agent-toolkit purpose) and agentic-harness ADR 0006 (the split), customizations live in toolkit; phases live in harness.

The harness gains a small `/release` lifecycle hook (§1b, v2.3.0) for plan promotion + Status transition, but no `/design` slash command. Users install agent-toolkit alongside the harness to get the skill.

**Why not the alternative:** putting `/design` in the harness would conflate authoring (customization) with phase orchestration (harness identity). Same reasoning as the dependabot-fixer + ship-release migration from harness to toolkit in v2.0.0.

### §8 — Tool allowlist `[Read, Write, Edit, Glob, Grep]` only; no Bash

All three sub-commands use file-ops only. Specifically:

- `Read` for design doc + part files + harness `.harness/PLAN.md` (in-progress check) + `templates/PLAN.md` (shape reference) + `.git/config` (author lookup with fallback prompt).
- `Glob` for parts/ subdir state discovery on re-run.
- `Write` for new files (template copy on bootstrap; part files; PLAN.md files).
- `Edit` for in-place updates (frontmatter Status transitions; Document History appends; section walks).

No `Bash` means the skill never shells out — the `mv` commands documented in `/design sequence`'s manual-promotion fallback are **operator-side**, executed by the human between active-plan and next-queued-plan, not by the skill.

### §9 — Mid-execution design changes via Document History audit trail

When the operator discovers a design flaw mid-execution (e.g. at step 3 of part 2): edit the parent design doc + append a row to Document History + re-run `/design translate`. The skill diffs proposed split against existing parts/ and presents the delta per-file (Overwrite / Keep existing / Cancel). Then `/design sequence --force-replace` regenerates affected PLAN.md files.

The Document History at the doc's bottom is the **audit trail** — every translate / sequence / launched transition writes a row. Mid-execution revisions append rows; nothing is silent.

## Consequences

### Positive

- **Precise design-first flow** — operators get a place to think through a design before code starts, with cross-cutting Quality Attributes + Operations concerns surfaced early. Reduces the "we shipped this and discovered the security gap on day 30" failure mode.
- **Ops thinking forced early** — the 11 Quality Attribute sub-attrs each get prompted; N/A is allowed only with one-sentence rationale. Catches blind spots before code.
- **Canonical wiki entry point** — published designs surface in `wiki/Home.md` + `_Sidebar.md` automatically when `launched`. Anyone landing on the wiki can find "why we built X" without hunting.
- **Reuses existing `/work` + `/review`** — stage 5 execution is the harness's already-battle-tested flow. The skill ships the design-side surface only; no new execution machinery.
- **Per-part shippability** — designs that ship in slices (independently reviewable, releasable) instead of one mega-PR. Each part has its own PLAN.md + execution arc.

### Negative

- **`/design author` is interactive and slow first time** — walking 10 sections + 11 Quality Attribute sub-attrs takes time. Acceptable for substantial designs; overkill for small features. Operators can skip-with-rationale per section; the friction is the price of the discipline.
- **Quality Attributes prompts add friction for small designs** — designing a 1-day feature shouldn't require 11 sub-attr decisions. Mitigation: explicit "skip with one-line N/A" guidance per section + the cap-of-6-parts soft warning suggesting splitting upstream if the design is too small to need parts.
- **Per-part PLAN.md promotion adds `/release` complexity** — `/release` §1b is conditional on design-doc origin signals; three cases (A/B/C) with different halt-vs-continue semantics. More moving parts in the release flow.
- **Cross-repo coordinated designs not supported in v0.8.0** — a design that spans both agent-toolkit + agentic-harness needs to live as two separate design docs cross-linking each other. Future plan can extend.
- **Mid-execution revisions require operator discipline** — the skill doesn't auto-detect when a design is wrong; the human has to notice + edit + re-translate. Acceptable for a v1 skill; auto-detection is speculative.

### Load-bearing assumptions (re-audit triggers)

| Assumption | Re-audit when |
|---|---|
| Operators will tolerate the 10-section + 11-sub-attr authoring flow without abandonment | After plan #7 (ContextVault) first dogfood — if `/design author` is abandoned mid-flow on the first real design, the template is too heavy and needs trimming |
| The part-split heuristic (one-per-Detailed-Design-subsection) produces useful splits most of the time | After plan #7 (first dogfood) and #8 (second dogfood) — if override rate during `/design translate` Reshape exceeds 50%, the heuristic needs revision or the user-driven approach should be default |
| `/release` §1b's three-case logic correctly handles all design-sourced plan scenarios | Every Claude Code release that changes phase semantics + after the first 3 real designs ship via the full chain |
| The Status lifecycle 4-state machine + the wiki-surfacing trigger on `launched` is the right granularity | At retrospective #12 — does the user benefit from the canonical entry point as much as the design predicted, or does it just become clutter? |

## Related

- [`/design` skill spec](../../skills/design/SKILL.md) — full body documentation for all three sub-commands (692 lines)
- [10-section design-doc template](../../skills/design/templates/design-doc.md) — locked verbatim 2026-05-14
- [How to use the design skill](../how-to/Use-The-Design-Skill.md) — practical recipe with three worked scenarios
- [agentic-harness `/release` §1b](https://github.com/alexherrero/agentic-harness/blob/main/harness/phases/05-release.md) — harness-side plan promotion + Status transition hook (v2.3.0)
- [ADR 0001 — agent-toolkit purpose](0001-agent-toolkit-purpose.md) — sibling-repo + customization-vs-phase split decision
- [ADR 0002 — evaluator design](0002-evaluator-design.md) — fresh-context grader consumed by `/review` during stage 5 execution
- [ADR 0003 — base operator-control hooks](0003-base-operator-hooks.md) — kill-switch / steer / commit-on-stop consumed by stage 5 execution
- [ROADMAP item #6](https://github.com/alexherrero/agentic-harness/blob/main/.harness/ROADMAP.md) — locally-stored roadmap context (gitignored; see plan #6 in `.harness/PLAN.archive.<date>.md` after plan close for the full task breakdown + locked design calls)
