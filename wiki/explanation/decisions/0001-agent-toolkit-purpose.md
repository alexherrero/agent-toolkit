# ADR 0001: `agent-toolkit` purpose, scope, and public-with-PII-guardrails framing

> [!NOTE]
> **Status:** accepted
> **Date:** 2026-05-12

## Context

`agentic-harness` shipped its first four skills (`dependabot-fixer`, `doctor`, `migrate-to-diataxis`, `ship-release`) bundled into the harness repo itself. Each skill was duplicated across the three adapter dirs (`adapters/claude-code/skills/`, `adapters/antigravity/skills/`, plus the `.agents/skills/` delivery for Gemini's reuse), and the parity invariant enforced by `scripts/check-parity.sh` required every skill to ship in all three places.

The model worked at four skills. Two costs surfaced as the skill catalog was projected forward:

- **Parity tax scales linearly.** Every new skill costs three adapter wrappers + a `CANON_SKILLS` entry + a `SHARED_SKILLS` entry. Cheap at four; painful at twenty.
- **Identity collision.** The harness's README pitches "a small, opinionated harness — not a 150-agent supermarket." The phase workflow (`/setup`, `/plan`, `/work`, `/review`, `/release`, `/bugfix`) is the protagonist; skills are background characters. Growing the skill catalog directly contradicts that framing.
- **Cross-host customization beyond skills.** A real personal-customizations layer would hold not just skills, but also slash commands, sub-agents, hooks, MCP server configs, status-line snippets, output styles, Antigravity workflows, Antigravity rules, instruction-snippet fragments, and settings-fragments — eleven primitive types. The harness's structure has no place for most of them; bolting them into `adapters/` would muddy the parity story.

Three architectural options were considered (see [agentic-harness ADR 0006](https://github.com/alexherrero/agentic-harness/blob/main/wiki/explanation/decisions/0006-agent-toolkit-split.md) for the full discussion):

1. **Lower parity in place, expand `agentic-harness/harness/skills/`** — keeps one repo, but every README change has to balance two audiences (harness users vs. customization users) and the parity invariant either stays (taxing skill growth) or weakens (taxing harness coherence).
2. **Two surfaces, one repo** — `agentic-harness/personal-skills/` alongside `agentic-harness/harness/`. Cleaner than option 1 but the README still mixes two stories.
3. **Split repos** — new `agent-toolkit` repo, shared `lib/install/` via copy-the-lib with byte-identity CI gate.

Option 3 was chosen.

## Decision

**`agent-toolkit` exists as a separate public GitHub repo** alongside `agentic-harness`. The two repos:

- Have independent release cycles.
- Share `lib/install/` byte-identically (see `scripts/sync-lib.sh`; CI gates self-consistency in each repo).
- Are expected to live as sibling working trees (`~/Antigravity/agentic-harness/`, `~/Antigravity/agent-toolkit/`).

**Scope of `agent-toolkit`:**

- All eleven customization-primitive types (skills, commands, agents, hooks, mcp-servers, bundles, status-line, output-styles, workflows, rules, snippets, settings-fragments) get their own subdir.
- Each customization carries a YAML-frontmatter manifest declaring `name`, `description`, `kind`, `supported_hosts` (subset of `{claude-code, antigravity, gemini-cli}`), `version`, and optional `install_scope` + `deprecated`.
- The installer dispatches per `supported_hosts` to host-native paths (see [reference/Per-Host-Paths](Per-Host-Paths)). No more adapter-tree duplication.
- Bundles package multiple primitives together when they ship as a coherent unit (e.g. a quality-gates bundle that combines an evaluator agent + several hooks + an evidence-tracking skill).

**Public, not private.** The repo is intended for the user's personal customizations. It is public because:

- The customizations encode the user's workflow conventions and are reusable by others as patterns.
- The byte-identity machinery + the manifest schema are themselves reference patterns worth showing.
- A private repo would make `agentic-harness`'s install-time delegation more complex (the harness installer can't `gh repo clone` a private repo without an auth token).

**Public-with-PII-guardrails.** Because personal customizations risk leaking personal information into public commits, three enforcement layers ship from day one:

1. **Pre-push git hook** (`templates/hooks/pre-push`, installed by the toolkit's installer into target projects' `.git/hooks/pre-push`) — runs `scripts/check-no-pii.sh` against the push range; blocks non-zero. **Mandatory enforcer.**
2. **`pii-scrubber` skill** (`skills/pii-scrubber/SKILL.md`) — agent-facing interactive layer. Scans the current diff, presents findings, offers redactions, loops until clean (or an explicit override is logged).
3. **CI gate** — `scripts/check-no-pii.sh --all` + the official `gitleaks-action` run on every push to GitHub.

## Consequences

**Positive**

- **Parity invariant simplifies.** No more parity table to enforce; per-customization manifests declare what they support, and the installer reads them at install time.
- **Customization catalog can grow without retrofitting.** Adding a new skill is now a single directory under `skills/<name>/` with a manifest, not three adapter copies.
- **Harness identity stays focused.** `agentic-harness` README continues to pitch the phase workflow; this repo handles the customizations growth story.
- **Cross-repo byte-identity discipline is exercised** by the lib/install/ sync flow. The mechanism is small (~100 lines of bash + a checksums file) but it's a real working pattern for "shared infrastructure across sibling repos without submodules."
- **PII guardrails are foundational, not bolted-on.** A public repo with personal customizations could easily leak; three layers of defense (skill, hook, CI) make leaks structurally hard.

**Negative**

- **Two repos to keep in sync** for any change that touches `lib/install/`. Mitigation: `scripts/sync-lib.sh` is a one-command operation; the byte-identity CI gate catches drift before it gets to main.
- **Users must install both repos** to get the full pre-v2.0.0 harness behavior. After v2.0.0 (the agentic-harness release that paired with this toolkit's v0.1.0), `dependabot-fixer` and `ship-release` migrated here; harness users who don't install the toolkit lose those skills. Mitigation: graceful-skip patterns in `harness/phases/{03-work,05-release}.md` + the toolkit ships its own installer.
- **PATH-CLI sugar deferred.** Long-term, both `agentic-harness` and `agent-toolkit` should be invokable as `harness` and `agent-toolkit` on `$PATH` (via `dev-machine-setup`). Today, both require knowing the path to their installers. Deferred to a `dev-machine-setup` plan; not a v0.1.0 concern.

**Load-bearing assumptions** (re-audit on every roadmap milestone)

- The user's customizations live in `agent-toolkit`, not in target projects. If a target project gains repo-specific customizations that don't belong here, the user adds them under the project's own `.claude/` (or equivalent) and the toolkit's `--update` doesn't clobber them (managed-parent wipes only touch toolkit-managed paths).
- `lib/install/` byte-identity is preserved by discipline + CI. If the two repos drift, `check-lib-parity.sh` fails CI; `sync-lib.sh` is the recovery path.
- The Diátaxis convention (this wiki) and the manifest schema are stable enough to grow on. If a customization kind needs a fundamentally different shape (e.g. binary artifacts, large file storage), this ADR gets superseded by a new ADR.

## Amendment 2026-05-17

**v0.9.0 — Gemini CLI host removed.**

> [!NOTE]
> **Status:** accepted · **Date:** 2026-05-17 · **Source:** [ROADMAP item #15](https://github.com/alexherrero/agentic-harness/blob/main/.harness/ROADMAP.md). Implemented in plan #15. See [ADR 0006](0006-gemini-cli-host-removal) for the host-scope-reduction rationale.

The original ADR 0001 (2026-05-12) sized the toolkit around three supported hosts: Claude Code, Antigravity, Gemini CLI. The Context section's narrative about the `agentic-harness` v1.0.0 → v2.0.0 split — *"Each skill was duplicated across the three adapter dirs (`adapters/claude-code/skills/`, `adapters/antigravity/skills/`, plus the `.agents/skills/` delivery for Gemini's reuse)"* — and the Decision section's manifest schema citation of `supported_hosts (subset of {claude-code, antigravity, gemini-cli})` both reflect that three-host scope.

In v0.9.0 (2026-05-17), the toolkit dropped standalone Gemini CLI from supported hosts. Antigravity (Gemini-in-IDE) stays as a supported host — different surface. The original ADR text above is preserved as historical record. Forward-looking references to host scope should read as two hosts: `{claude-code, antigravity}`.

This amendment does not supersede ADR 0001's central decision (the toolkit/harness split). It only narrows the host scope. See ADR 0006 for the full host-scope-reduction rationale + load-bearing assumptions for the reduction.

## Amendment 2026-05-20

**v0.10.0 — Local-only embeddings; BGE-large default.**

> [!NOTE]
> **Status:** accepted · **Date:** 2026-05-20 · **Source:** [ROADMAP item #18](https://github.com/alexherrero/agentic-harness/blob/main/.harness/ROADMAP.md). Implemented in plan #18 (inserted mid-flight of plan #7a part 5). See `agent-toolkit/skills/memory/scripts/embed.py` v0.10.0+ for the implementation; this amendment captures the design rationale.

The original ADR 0001 (2026-05-12) implied — and the parent [MemoryVault design](../designs/memoryvault.md)'s locked design call **C2** made explicit — that the toolkit would ship both an API-based embedding path (Anthropic API routed through Voyage) and a local `sentence-transformers` fallback. The dual-mode posture was driven by the assumption that operators with API access would prefer it for quality while local mode existed as an offline-capable fallback.

In v0.10.0 (2026-05-20), the API embedding mode was **dropped entirely**. The toolkit now ships a single embedding mode — local `sentence-transformers` — with the default model upgraded from `all-MiniLM-L6-v2` (384-d, MTEB English 56.3) to `BAAI/bge-large-en-v1.5` (1024-d, MTEB English 64.2). `EMBEDDING_DIM` bumped 384 → 1024. The original ADR text above is preserved as historical record. Forward-looking references to embedding modes should read as a single production mode: `local` (plus `stub` for tests).

**Why this narrowing:**

- The primary operator is a Claude Ultra subscriber without a separate Anthropic / Voyage API key — the API path was unreachable for the toolkit's actual user.
- Dual-mode added surface area (mode resolution, env-var contract, dim-truncation, two test paths) without providing value for the personal-dev-env use case.
- Modern small-to-mid-size local models (BGE-large family, mxbai, nomic-embed) deliver near-SOTA MTEB results on desktop-class hardware (M-series + 64GB RAM) — the quality gap that motivated dual-mode is no longer load-bearing.

**Why not the alternatives:**

- *Keep dual-mode + flip the default to local.* Rejected — the surface area of "two paths" is the cost we wanted to eliminate; making one the default doesn't help.
- *Drop both API and local; require operator to BYO embedding.* Rejected — the toolkit's value depends on out-of-the-box recall functionality.
- *Default to a smaller model (e.g. keep `all-MiniLM-L6-v2`).* Rejected — the operator's desktop-class hardware runs BGE-large with no perceived overhead, and the MTEB quality gap is meaningful for the recall use case.
- *Write a new ADR 0007.* Rejected (operator decision 2026-05-20) — the change is a scope narrowing of the same architectural decision captured in ADR 0001; amending preserves the audit trail without splitting the discussion across two ADRs.

**Operational changes shipped in v0.10.0:**

- `sentence-transformers` becomes a hard install dep (was optional fallback). `install.sh` + `install.ps1` pip-install it by default from `requirements.txt`; opt-out via `--no-python-deps` / `-NoPythonDeps`.
- `vec_index.py` gained dim-mismatch detection + a `rebuild` subcommand. Operators who upgrade from v0.9.x on top of an existing 384-d index see a clear stderr warning + a manual remediation command — never silent corruption.
- All `VOYAGE_API_KEY` / `ANTHROPIC_API_KEY` env var reads removed from `embed.py`. `MEMORY_USE_API_EMBEDDINGS` env var no longer consulted.
- New `AGENT_TOOLKIT_EMBEDDING_MODEL` env var as escape hatch for swapping local models (still local-only — no API option ever).
- Smoke install split: CI runs with `--no-python-deps` + `SKIP_LOCAL_MODE_INTEGRATION` to avoid the ~1.3GB BGE-large download per workflow run; operators get the full pip-install + first-run download on their own machine.

**Load-bearing assumptions** (re-audit on every roadmap milestone, especially when bringing a new operator onto the toolkit):

1. **Operator hardware is desktop-class.** Toolkit defaults assume M-series + 64GB-RAM (or equivalent). Operators on low-spec hosts swap to a smaller model via `AGENT_TOOLKIT_EMBEDDING_MODEL`. **Re-audit trigger:** if low-spec-host complaints become a recurring pattern, change the default or document the swap pattern prominently in `Use-The-Memory-Skill.md`.
2. **PyTorch MPS backend works on Apple Silicon** for sentence-transformers's underlying inference. If a PyTorch release breaks MPS, local-mode degrades to CPU — still fast on M-series + 64GB, just non-accelerated. **Re-audit trigger:** PyTorch major-version bump + operator-perceived perf regression.
3. **`sentence-transformers` stays maintained.** It's a widely-used library with strong upstream support, but if the project is abandoned or pivots in an incompatible way, the toolkit needs a swap (candidates: direct PyTorch + tokenizers integration; or move to `transformers` library directly). **Re-audit trigger:** sentence-transformers stops shipping releases for 6+ months, OR drops support for the BGE-large family.
4. **The MemoryVault design's C2 (dual-mode embeddings) is superseded by this amendment for v0.10.0+.** The design doc still narrates dual-mode in places that describe the v1 implementation timeline; readers should treat any "Anthropic API by default" reference as historical context, not current behavior. A future docs pass may rewrite the design doc body; for now, the amendment is the source of truth.

This amendment does not supersede ADR 0001's central decision (the toolkit/harness split or the PII-guardrails framing). It narrows the embedding-mode scope from `{api, local, stub}` to `{local, stub}` and locks the operator-config assumption to desktop-class hardware.

## Related

- [agentic-harness ADR 0006](https://github.com/alexherrero/agentic-harness/blob/main/wiki/explanation/decisions/0006-agent-toolkit-split.md) — the sibling decision in the harness repo, focused on the harness-side framing.
- [ADR 0006 (agent-toolkit) — Gemini CLI host removal](0006-gemini-cli-host-removal) — the host-scope-reduction rationale that the 2026-05-17 amendment cross-references.
- [MemoryVault design](../designs/memoryvault.md) — parent design doc; locked design call C2 (dual-mode embeddings) is superseded by the 2026-05-20 amendment.
- [agentic-harness ROADMAP item #18](https://github.com/alexherrero/agentic-harness/blob/main/.harness/ROADMAP.md) — the inserting-mid-flight context for plan #18 (local-only embeddings).
- [Purpose and scope](Purpose-And-Scope) — narrative summary of what this repo is for.
- [Manifest schema reference](Manifest-Schema) — the YAML frontmatter contract.
- [Per-host paths reference](Per-Host-Paths) — how each `kind` maps to a host destination at install time.
