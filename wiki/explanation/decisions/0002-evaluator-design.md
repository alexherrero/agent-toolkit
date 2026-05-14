# ADR 0002: `evaluator` sub-agent — read-only fresh-context grader

> [!NOTE]
> **Status:** accepted
> **Date:** 2026-05-13

## Context

The agentic-harness `/review` phase has shipped with the `adversarial-reviewer` sub-agent since v0.8.0. Its framing is `"the code under review likely contains bugs. Find them."` and its output contract is one of: a failing test, a `file:line` defect with minimal reproducer, or `NO ISSUES FOUND` with categories checked. This works well for **defect surfacing** — find what's broken — but doesn't provide a binary judgment against an explicit rubric.

Three forces argued for a complementary primitive:

1. **`/review` taking a precise spec needs precise grading.** When the `PLAN.md` task's Verification clause is a numbered list of falsifiable claims (the typical shape — see `harness/phases/02-plan.md`), the natural verification is *"did the diff satisfy claims 1-5?"*, not *"are there bugs?"*. The adversarial framing tolerates vague rubrics; the rubric-grading framing requires precise ones.
2. **The future design skill (#6) needs a per-step grader.** The design skill (planned, separate ROADMAP item) walks the human + agent through a design doc, splits into agent-executable sub-designs + steps, and runs a per-step review loop. That loop needs a PASS / NEEDS_WORK contract — *"did this step's output match the approved sub-design?"* — and benefits from being grader-only (no Bash, no Write) so it can't drift into building.
3. **The cwc-long-running-agents pattern (`~/ContextVault/domains/anthropic-patterns/cwc-long-running-agents.md`) explicitly recommends a "fresh-context evaluator"** — a sub-agent with no `Write`/`Edit` tools that grades work the builder cannot grade itself. The harness has the fresh-context primitive (sub-agents have no parent conversation history) but lacks the explicit PASS / NEEDS_WORK contract and the tool-allowlist enforcement.

Open design questions to resolve before shipping:

- **How does the caller supply the rubric?** Inline prompt arg, sidecar `rubric.md` file, or manifest field?
- **What tools should the evaluator have?** Read-only minimum, or `Bash` for running tests?
- **Replace `adversarial-reviewer`, or coexist?** Both grade code; one could subsume the other.
- **Where does it live — `agent-toolkit` or `agentic-harness`?**
- **Output contract shape — what does PASS / NEEDS_WORK look like on the wire?**

This ADR resolves all five.

## Decision

**Ship `evaluator` as a standalone agent customization in `agent-toolkit/agents/evaluator.md`.**

- `kind: agent`, `supported_hosts: [claude-code, antigravity, gemini-cli]`, `install_scope: either`.
- Per the locked per-host paths table, the toolkit installer dispatches to `.claude/agents/evaluator.md` (Claude Code), `.agent/skills/evaluator/SKILL.md` (Antigravity, sub-agent-as-skill wrap), and `.gemini/agents/evaluator.md` (Gemini CLI).
- First real consumer of `kind: agent` — installer support for that kind ships alongside in toolkit v0.6.0.

**Tool allowlist: `[Read, Glob, Grep]` only. No `Bash`, no `Write`, no `Edit`, no network.**

- The "fresh context that never saw the build" framing only holds if the evaluator cannot re-execute. Tests are run by the caller before dispatch; their output is supplied as a readable artifact.
- The grader must not become a builder. Mutation tools would conflate roles.
- The host enforces the allowlist; allowlist-violating dispatches fail loudly rather than silently degrading.

**Caller supplies the rubric inline in the dispatch prompt.**

- Prompt shape: two labeled sections, `ARTIFACT:` (paths/globs to read) and `RUBRIC:` (numbered verifiable claims).
- No `rubric.md` file convention; no manifest field for rubrics.
- Rationale: most flexible (callers structure however they like); no extra file machinery to maintain; rubric travels with the dispatch context not the artifact.

**Coexist with `adversarial-reviewer`, do not replace.**

- Different framings serve different decision points. `adversarial-reviewer` is for defect surfacing ("contains bugs"); `evaluator` is for rubric grading ("did this satisfy claims 1-5?").
- The harness `/review` phase spec ([§3b in 04-review.md, added v2.1.0](https://github.com/alexherrero/agentic-harness/blob/main/harness/phases/04-review.md)) documents how to dispatch both in the same session — adversarial first, evaluator second when the Verification clause is precise enough to express as a rubric.
- Output shapes differ, so the outputs don't collide.

**Output contract: structured, scannable, greppable.**

```
<PASS or NEEDS_WORK>

Rubric:
1. <item summary>: PASS|FAIL — <reasoning citing artifact>
...

Verdict: <PASS or NEEDS_WORK> — <one-sentence framing>
```

- Line 1: verdict header. PASS iff every item is PASS; NEEDS_WORK otherwise.
- Per-rubric-item line cites the artifact (filename, line number, or quote).
- Final Verdict line is the greppable summary.
- Mirrors `adversarial-reviewer`'s structured-output convention (failing-test / defect / NO ISSUES FOUND) rather than the free-prose smell.

## Consequences

**Positive**

- **Binary judgment surface available.** Consumers needing PASS / NEEDS_WORK against a precise rubric can dispatch the evaluator instead of asking the adversarial-reviewer to do something it's not framed for.
- **Composable across consumers.** The harness `/review` phase uses it; the design skill (#6) will use it for per-step grading; the quality-gates bundle (#10) will package it; long-running custom skills will dispatch it for automated PASS / NEEDS_WORK gates. One primitive, many call sites.
- **No harness-shape coupling.** The evaluator lives in the toolkit as a standalone agent. It's not bolted into a phase, and it doesn't depend on `.harness/` state. Anyone (harness user or not) can dispatch it from any consumer context.
- **Fresh-context invariant is structurally protected.** The tool allowlist enforces no-replay at the host level. There's no convention to forget; the host refuses the tool call.
- **Strong dogfood for the toolkit's `kind: agent` support.** Building the evaluator forces the installer + validator + per-host paths dispatch for agent customizations end-to-end. Future agents drop into the same machinery.

**Negative**

- **Caller carries the rubric-quality responsibility.** A vague rubric ("the code is well-structured") returns FAIL with "rubric item not verifiable as written." This is the intended failure mode — the evaluator refuses to grade prose — but it means rubric authoring is a real skill consumers have to learn. The how-to ([Use the evaluator](Use-The-Evaluator)) covers rubric anti-patterns explicitly.
- **No `Bash` means tests must be pre-run by the caller.** The evaluator cannot run tests to check their status. Callers run tests beforehand, redirect output to a file, add the file to `ARTIFACT:`, and have a rubric item like *"test-output.txt's final line reads 'OK'"*. More setup than "evaluator runs the tests"; the trade-off keeps the no-replay invariant intact.
- **Two grader surfaces means consumers must pick.** `/review` users now choose: adversarial alone, evaluator alone, or both. The comparison table in `04-review.md §3b` makes the choice explicit, but it's a real discoverability cost paid by every reviewer.
- **Rubric format is a soft API.** The `ARTIFACT:` / `RUBRIC:` labeled-sections shape isn't enforced by a schema validator — it's a documented prompt convention. If a consumer dispatches with a different shape, the evaluator returns "Input contract violation" rather than silently degrading; but the contract is conventional, not enforced.

**Load-bearing assumptions** (re-audit on every consumer addition)

- The tool allowlist (`Read, Glob, Grep`) is sufficient for grading every real rubric. If a rubric class requires `Bash` (e.g. "verify the cluster is healthy"), it should be expressed differently — caller runs the check first, writes the result to disk, evaluator reads. If real-world use surfaces a class that genuinely can't be expressed that way, this ADR gets superseded.
- The PASS / NEEDS_WORK binary is the right verdict shape. Some consumers might want PASS / PARTIAL / FAIL or a numeric score. If that need surfaces, a future ADR can extend the output contract without breaking the binary case (PARTIAL would still map to NEEDS_WORK in callers that only check the verdict header).
- Caller-supplied rubric stays inline-only. If a consumer wants reusable rubrics (e.g. a "release-readiness" rubric stored once and referenced by name), a future ADR can add a rubric-file convention without breaking the inline case.

## Related

- [Use the evaluator](Use-The-Evaluator) — practical how-to with three worked rubrics.
- [Customization Types](Customization-Types) — what `kind: agent` means and the v0.6.0 installer support.
- [Per-Host Paths](Per-Host-Paths) — where the evaluator lands per host.
- [evaluator agent spec](https://github.com/alexherrero/agent-toolkit/blob/main/agents/evaluator.md) — the canonical body.
- [agentic-harness `/review` §3b](https://github.com/alexherrero/agentic-harness/blob/main/harness/phases/04-review.md) — the harness-side dispatch documentation.
- [ADR 0001 — agent-toolkit purpose](0001-agent-toolkit-purpose) — the sibling-repo decision that put this customization here vs. in the harness.
