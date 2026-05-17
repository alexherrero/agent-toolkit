---
name: memory
description: File-based, agent-curated permanent memory layer that lives inside the user's existing Obsidian vault. Captures durable preferences / workflows / fixes via a reflection sidecar; recalls relevant entries automatically into every new prompt via SessionStart + UserPromptSubmit hooks; adapts the agent's behavior over time without explicit configuration. The goal is compound learning — each conversation makes the next one better, because the agent never forgets what already happened.
kind: skill
supported_hosts: [claude-code, antigravity]
version: 0.1.0
install_scope: project
---

# memory — permanent agent memory via Obsidian-vault-folder + reflection sidecar

The first toolkit skill that integrates with the user's own personal note-taking surface (Obsidian) rather than maintaining a separate agent-only vault. The skill exposes four sub-commands (`save` / `evolve` / `reflect` / `search`); recall is hook-driven rather than user-invoked (SessionStart + UserPromptSubmit hooks shipped alongside in the [recall-loop part](https://github.com/alexherrero/agent-toolkit/blob/main/wiki/explanation/designs/memoryvault/parts/recall-loop.md)).

**Position vs. built-in agent memory** (Claude memories, vendor-specific context features): built-in memory is per-platform, opaque, lossy, and not composable across tools. MemoryVault is file-based + version-control-friendly + human-inspectable. The user can open Obsidian + read or edit any captured entry directly; the agent's memory + the user's notes coexist in the same place.

**Position vs. session transcripts**: Claude Code transcripts capture everything that happened. MemoryVault captures what's worth keeping forever — the durable preferences / workflows / fixes that make Day 2 better than Day 1.

## When to reach for which sub-command

| You want to... | Reach for |
|---|---|
| Capture a specific preference / workflow / fix manually right now | `/memory save` |
| Replace an existing entry with a corrected version (preserving audit trail) | `/memory evolve` |
| Run reflection over the current session transcript on demand (or a specified transcript path) | `/memory reflect` |
| Search the vault for entries matching a query (when auto-recall via UserPromptSubmit hook didn't pull what you wanted) | `/memory search` |

Auto-recall happens via the [SessionStart + UserPromptSubmit hooks](https://github.com/alexherrero/agent-toolkit/blob/main/wiki/explanation/designs/memoryvault/parts/recall-loop.md) — operators don't invoke a recall command directly. Reflection happens automatically via Stop + idle hooks too; the manual `/memory reflect` is for one-off runs against arbitrary transcripts.

## Sub-commands

### `/memory save`

> [!NOTE]
> **Status**: stub. Full body lands in **task 2** of plan #7a part 1 (`write-primitives`). See `.harness/PLAN.md` for the task spec.

Synchronously writes a markdown entry at `MemoryVault/<group>/<kind>/<slug>.md` with YAML frontmatter (`kind`, `status: active`, `created`, `updated`, `tags`, optional `supersedes`). Body is free-form markdown. File write is synchronous (<50ms target); embedding + vec-index update are async (don't block the agent or the user).

**Planned invocation shape** (subject to refinement in task 2):

```
/memory save <kind> <slug> [--group <group>] [--always-load]
```

The `--always-load` flag writes to `MemoryVault/personal-private/_always-load/` and sets `always_load: true` frontmatter — entries flagged this way get injected at SessionStart per the recall-loop part.

### `/memory evolve`

> [!NOTE]
> **Status**: stub. Full body lands in **task 3** of plan #7a part 1 (`write-primitives`). See `.harness/PLAN.md` for the task spec.

Atomic archive-and-replace primitive that prevents memory rot when preferences change. Five-step flow: (1) read the old entry; (2) write new entry with `supersedes: <old-path>` frontmatter pointing back; (3) atomically move old entry to `MemoryVault/personal-private/_archive/<original-path>.YYYYMMDD.md` via filesystem rename (single-syscall atomicity on APFS); (4) update old entry's frontmatter `status: superseded` + `superseded_by: <new-path>` cross-link; (5) trigger vec-index update for both. Recall filters skip `status: superseded` by default.

**Planned invocation shape** (subject to refinement in task 3):

```
/memory evolve <old-path> <new-content> <reason>
```

Integrates with the tri-modal review flow (lands in plan #7a part 3, `reflection-and-recovery`): when a new candidate contradicts an existing entry, "supersede existing entry X?" is one of the four approve / edit / reject / supersede options at review time.

### `/memory reflect`

> [!NOTE]
> **Status**: stub. Full body lands in plan #7a **part 3** (`reflection-and-recovery`). See `.harness/designs/memoryvault/queued-plans/reflection-and-recovery.PLAN.md` for the queued plan.

User-invokable trigger for the reflection sidecar logic. Two parallel mining passes over a session transcript: (a) the **3-category mine** (Successful Workflows / User Preferences / Fixes & Workarounds) writes MemoryVault entries via `/memory save`; (b) the **idea-candidate mine** (follow-ups / project ideas / research candidates) writes to `~/Obsidian/Ideas.md` + `MemoryVault/personal-private/_idea-incubator/<slug>/` via the idea-ledger flow (lands in plan #7a part 4).

Tri-modal confidence routing applies: HIGH-confidence candidates auto-save; MEDIUM go through interactive review; LOW land in `_inbox/` for batch triage. Controlled by `memory.review_mode: interactive (default) | silent`.

The same logic runs automatically via Stop-event hook (after every session) + idle-time hook (after N minutes idle, also recovers crashed sessions). `/memory reflect` is the manual trigger for on-demand runs.

**Planned invocation shape** (subject to refinement in plan #7a part 3):

```
/memory reflect [--session <path>]
```

Defaults to the current Claude Code session transcript.

### `/memory search`

> [!NOTE]
> **Status**: stub. Full body lands in plan #7a **part 2** (`recall-loop`) where the recall engine is built. See `.harness/designs/memoryvault/queued-plans/recall-loop.PLAN.md` for the queued plan.

Manual semantic query against the vault — the read primitive that complements `/memory save`'s write. Useful when the automatic recall (via UserPromptSubmit hook) didn't surface what you wanted, or when you want to inspect what's in the vault without re-loading via a session prompt.

Calls the same recall engine the UserPromptSubmit hook uses: sqlite-vec primary + grep + frontmatter alongside, merge results via the locked rank-merge formula (`sim × 0.7 + keyword × 0.3`), dedup, return top-K (K=5 default).

**Planned invocation shape** (subject to refinement in plan #7a part 2):

```
/memory search <query> [--group <group>] [--include-inbox] [--top-k <N>]
```

Default behavior: query against all groups; exclude `_inbox/`; return top-5 results.

## Tool allowlist

**`Read, Write, Edit, Glob, Grep`** — no Bash. Same restriction as `/design` skill. The skill body never invokes shell commands directly; Python scripts under `skills/memory/scripts/` (added in tasks 2-4) handle the heavy lifting (file ops via Python's `os` / `pathlib`; embedding API calls via Python `requests` or vendor SDK; sqlite-vec via the `sqlite-vec` Python wheel).

Python-side scripts can use whatever they need (network for embedding API, filesystem for vec-index, subprocess for `pip install <pkg>` on first invocation if needed) — the allowlist restriction is on the SKILL.md body itself, not the dispatched scripts.

## Host scope

`supported_hosts: [claude-code, antigravity]` — `gemini-cli` deliberately excluded per ROADMAP item #15 (Gemini-CLI host removal, added 2026-05-16). The memory skill is the first new skill that ships post-#15-decision so we don't include + then remove. Existing skills (`pii-scrubber`, `design`, `dependabot-fixer`, `ship-release`, `evaluator`, base hooks) retain `gemini-cli` in their manifests until #15 sweeps them in one coordinated patch.

See the [parent design's 2026-05-16 Document History row](https://github.com/alexherrero/agent-toolkit/blob/main/wiki/explanation/designs/memoryvault.md#document-history) for the host-scope correction rationale.

## Cross-references

- **Parent design**: [MemoryVault — permanent agent memory](https://github.com/alexherrero/agent-toolkit/blob/main/wiki/explanation/designs/memoryvault.md) — the canonical "Why we built this" wiki entry point per the locked design call from plan #6
- **Part 1 plan**: `write-primitives` (active at `.harness/PLAN.md`) — ships `save` + `evolve` bodies (tasks 2 + 3) + embedding integration (task 4) + partial how-to (task 5)
- **Queued parts**: `recall-loop` (part 2) / `reflection-and-recovery` (part 3) / `idea-ledger` (part 4) / `seed-pass` (part 5) / `discovery-mining` (part 6 = plan #7b)
- **Conventions**: shipping pattern follows [`design` skill's multi-sub-command body shape](https://github.com/alexherrero/agent-toolkit/blob/main/skills/design/SKILL.md) — the first toolkit skill with multiple sub-commands handing off between each other
- **External-review handoff**: applies to design + plan refinement passes; lands via [agent-toolkit v0.8.1](https://github.com/alexherrero/agent-toolkit/releases/tag/v0.8.1) + [agentic-harness v2.3.1](https://github.com/alexherrero/agentic-harness/releases/tag/v2.3.1) shipped 2026-05-16

## Status

This skill is **stub-shipped** as of v0.9.0 (plan #7a part 1, task 1). All 4 sub-commands have documented shape + planned invocation but no functional implementation yet. The 4 sub-commands fill in across plan #7a tasks 2-5 + the 5 queued parts (recall-loop, reflection-and-recovery, idea-ledger, seed-pass, discovery-mining) which complete the v0.9.0 → v0.10.0 sequence.

Until full bodies land, invoking any of the 4 sub-commands will surface a "Stub — full implementation lands in <task/part X>. See parent design at <link>." message rather than executing the operation.
