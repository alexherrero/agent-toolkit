# How to use the evaluator

> [!NOTE]
> **Goal:** Dispatch the `evaluator` sub-agent from your skill, command, slash workflow, or `/review` session to get a PASS / NEEDS_WORK verdict against an explicit rubric.
> **Prereqs:** `agent-toolkit` installed into the target project (so `evaluator` is wired into the host); you have an artifact on disk and a precise rubric you can express as numbered claims.

## When to reach for it (and when not to)

The evaluator is a **read-only grader**. It reads files, applies a rubric, returns PASS or NEEDS_WORK. It is **not**:

- a defect finder (use `adversarial-reviewer` for "the code contains bugs, find them")
- a code reviewer in the prose sense (it will refuse to return prose-only critiques)
- a test runner (the tool allowlist is `Read, Glob, Grep` only — no Bash)

Reach for it when:

| You have… | Use evaluator |
|---|---|
| A precise rubric (a numbered list of falsifiable claims) | ✅ |
| A precise spec that doubles as a rubric (e.g. a PLAN.md Verification clause) | ✅ |
| An artifact on disk the evaluator can read (file path / diff / test-output file) | ✅ |
| A vague brief ("is this code good?") | ❌ — use `adversarial-reviewer` |
| A need to *run* tests as part of the grading | ❌ — run them first, supply the output file as an artifact |
| A need to *fix* what fails | ❌ — evaluator is read-only; route NEEDS_WORK back to `/work` |

A useful mental model: the evaluator is the "did this match the contract?" check. If you can write the contract down as a numbered list, the evaluator can grade against it.

## Dispatch prompt template

The evaluator expects a prompt with two labeled sections:

```
ARTIFACT:
- <path or glob 1>
- <path or glob 2>
- ...

RUBRIC:
1. <verifiable claim 1>
2. <verifiable claim 2>
3. ...
```

Both sections are mandatory. Additional sections (e.g. `CONTEXT:`) are allowed but the evaluator only grades the rubric.

**Rubric authoring rules:**

- **Verifiable** — a fresh reader can check it by reading the artifact, without your context.
- **Falsifiable** — has a clear failure mode (avoid "the code is good", "this is well-structured").
- **Independent** — items don't reference each other ("item 3 is true if item 2 is true" is a smell).
- **Numbered** — the output mirrors the numbering, so the rubric and output line up 1:1.

## Three worked rubric examples

### 1. Code-change rubric (typical `/review` use)

Use when a task's PLAN.md Verification clause is precise enough to grade as a rubric.

```
ARTIFACT:
- src/parser.py
- tests/test_parser.py
- spec/parser-spec.md

RUBRIC:
1. Every acceptance criterion in spec/parser-spec.md §"Acceptance" has a matching test in tests/test_parser.py (criterion → test name; not just "there are tests").
2. The four edge cases listed in spec/parser-spec.md §"Edge cases" are covered by tests with descriptive names.
3. No tests are skipped (no @skip, @pytest.mark.skip, .skip(), or pytest.skip() in the diff).
4. No print() / breakpoint() / pdb / debug-log statements remain in src/parser.py.
```

Output shape on PASS:

```
PASS

Rubric:
1. Acceptance criteria covered: PASS — spec lists 5 criteria (lines 18-32); tests test_basic_parse, test_empty_input, test_nested, test_malformed, test_unicode map 1:1.
2. Edge cases covered: PASS — tests at lines 47-92 exercise empty / deeply-nested / malformed-utf8 / mixed-line-endings.
3. No skipped tests: PASS — no @skip or .skip() in the diff.
4. No debug residue: PASS — no print() or breakpoint() in src/parser.py.

Verdict: PASS — diff satisfies all four rubric items.
```

### 2. Docs rubric (e.g. `/release` doc-drift check)

Use when grading a docs change against a content contract.

```
ARTIFACT:
- wiki/reference/Per-Host-Paths.md
- CHANGELOG.md

RUBRIC:
1. wiki/reference/Per-Host-Paths.md's "agent" row destination column lists all three host paths (.claude/agents/<name>.md, .agent/skills/<name>/SKILL.md, .gemini/agents/<name>.md).
2. The CHANGELOG.md v0.6.0 entry's "Added" section names `evaluator` agent explicitly with a one-line description.
3. No section of Per-Host-Paths.md still says "kind=agent: not yet supported" (the v0.5.0 placeholder text).
```

The evaluator reads the docs, checks each claim, returns PASS or per-item FAIL with a quote/line citation.

### 3. Release rubric (pre-tag readiness)

Use to grade whether the tree is releasable.

```
ARTIFACT:
- CHANGELOG.md
- README.md

RUBRIC:
1. CHANGELOG.md has a header section for the version about to be tagged, dated within the last 7 days.
2. The CHANGELOG entry's "Added" / "Changed" / "Removed" subsections (if present) are non-empty.
3. README.md "What's inside" table mentions every customization the CHANGELOG entry's "Added" section names.
4. CHANGELOG.md has a link reference for the new version tag at the bottom of the entry.
```

Note: this rubric checks **content alignment**, not test status. If you want test status as a gate, run the tests beforehand, save their output to a file, and add the file as an ARTIFACT line + a rubric item like "test-output.txt's final line reads 'OK'".

## Output interpretation

```
<PASS or NEEDS_WORK>

Rubric:
1. <item summary>: PASS|FAIL — <reasoning citing artifact>
2. <item summary>: PASS|FAIL — <reasoning citing artifact>
...

Verdict: <PASS or NEEDS_WORK> — <one-sentence framing>
```

- **Line 1** is the verdict header. PASS iff every rubric item is PASS; otherwise NEEDS_WORK.
- **Each rubric line** cites the artifact (filename + section, line number, or specific quote). Reasoning is one sentence.
- **Final Verdict line** restates the header — this is what callers grep for.

**On PASS:** the diff/artifact satisfies the rubric. Move on.

**On NEEDS_WORK:** the FAIL lines name specific rubric items + cite the artifact. Route to:

- `/work` if the fix is small (single-file, test easy to write)
- `/plan` if the gap reveals a spec misunderstanding
- Re-dispatching the evaluator with a revised rubric, if your rubric was the problem

## Common failure modes

### "Rubric item not verifiable as written"

If a rubric item is prose-only or so vague it has no clear failure mode, the evaluator marks it FAIL with reasoning `"rubric item not verifiable as written; caller must rephrase as a verifiable claim"`. Final Verdict is NEEDS_WORK.

**Symptom:** you wrote `"the code is well-structured"` or `"the diff is clean"`.

**Fix:** rephrase as a falsifiable claim. Examples:

- `"the code is well-structured"` → `"no function in src/foo.py exceeds 50 lines"` and `"src/foo.py has no nested function definitions"`
- `"the diff is clean"` → `"the diff modifies only files under src/ and tests/"` and `"the diff adds no new imports of `os.system` or `subprocess.run` with shell=True"`

### "Artifact unreadable"

If a path in ARTIFACT resolves to nothing readable, the evaluator halts with `"Artifact unreadable: <path> — <reason>"` and final Verdict NEEDS_WORK.

**Symptom:** typo in the path; relative path resolved against the wrong cwd; file not committed yet.

**Fix:** confirm the path exists from the cwd the evaluator will run from. Absolute paths or paths relative to repo root are safest.

### "Input contract violation"

If the dispatch prompt is missing the `ARTIFACT:` or `RUBRIC:` label (or both), the evaluator halts immediately with `"Input contract violation: <which section missing or malformed>"`.

**Symptom:** you dispatched with prose instead of labeled sections.

**Fix:** re-dispatch using the template in this page. The `ARTIFACT:` and `RUBRIC:` labels are mandatory.

### Item references something not in ARTIFACT

If a rubric item references a file not listed in `ARTIFACT:` (e.g. *"the deploy succeeded"* with no deploy log supplied), the evaluator marks that item FAIL with reasoning `"cannot verify; required artifact not in ARTIFACT list"`. Final Verdict is NEEDS_WORK.

**Fix:** either add the missing file to `ARTIFACT:` or drop the item from the rubric.

## Tool allowlist (why it's tight)

The evaluator's tool allowlist is **`[Read, Glob, Grep]` only** — no `Bash`, no `Write`, no `Edit`, no network.

Consequences:

- The evaluator **cannot run tests**. The caller runs them and supplies the output file as an artifact.
- The evaluator **cannot modify the artifact**. Reading is the entire job.
- The evaluator **cannot fetch from the network**. If the rubric depends on external state, the caller fetches and writes it to disk first.

This is intentional. The "fresh context that never saw the build" framing only holds if the evaluator cannot re-execute. See [ADR 0002 — evaluator design](0002-evaluator-design) for the rationale.

## Pair with `/review` (harness)

The harness's `/review` phase ([`harness/phases/04-review.md` §3b](https://github.com/alexherrero/agentic-harness/blob/main/harness/phases/04-review.md)) documents how to dispatch the evaluator alongside the existing `adversarial-reviewer` flow. Both can run in the same session — adversarial-reviewer for "find bugs", evaluator for "grade against the PLAN.md Verification clause". Their outputs combine into a richer finding set.

## Related

- [evaluator agent spec](https://github.com/alexherrero/agent-toolkit/blob/main/agents/evaluator.md) — the canonical body (frontmatter, input contract, output contract, full failure modes, worked examples).
- [ADR 0002 — evaluator design](0002-evaluator-design) — why the allowlist is tight, why caller-supplied rubric, why coexist with adversarial-reviewer.
- [Customization Types](Customization-Types) — what `kind: agent` means and where it lands per host.
- [Per-Host Paths](Per-Host-Paths) — the destination paths the toolkit installer dispatches to.
