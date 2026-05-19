# How to use the memory skill

> [!NOTE]
> **Goal:** capture durable preferences / workflows / fixes to MemoryVault so the agent's behavior compounds across sessions. Evolve entries when preferences change without losing the audit trail.
> **Prereqs:** `agent-toolkit` installed (skill lands at `.claude/skills/memory/` + `.agent/skills/memory/`); an Obsidian vault folder set up as your `MemoryVault/` root + the path exported as `MEMORY_VAULT_PATH` (or passed via `--vault-path` on each invocation). Optional: `pip install sqlite-vec sentence-transformers` for full vec-index + offline embedding; `VOYAGE_API_KEY` or `ANTHROPIC_API_KEY` env var for online embedding. Without these the skill still works (file writes always succeed; embedding work queues for later).

The `memory` skill ships as plan #7a parts 1 + 2 + 3 of [MemoryVault — Permanent agent memory via Obsidian-vault-folder + reflection sidecar](../explanation/designs/memoryvault.md). This page covers the **two write primitives** (`/memory save` + `/memory evolve`), the **two recall hooks** (SessionStart + UserPromptSubmit), the **`/memory reflect` skill + Stop / idle reflection hooks** (the write loop), and **crash-recovery markers**. Idea ledger + discovery come in subsequent parts.

## ⚡ At-a-glance

| Sub-command | Input | Output | Backed by |
|---|---|---|---|
| `/memory save` | `<kind> <slug>` + body (stdin or interactive) | Entry at `<vault>/<group>/<kind>/<slug>.md` (or `_always-load/<slug>.md`); queued embedding | `skills/memory/scripts/save.py` |
| `/memory evolve` | `<old-path> <reason>` + new body | Archive at `_archive/<original>.YYYYMMDD.md` + new entry replacing old | `skills/memory/scripts/evolve.py` |
| **(recall, auto)** | — (fires on session boot + every prompt) | Always-load entries injected into session; top-K relevant entries injected per prompt | `skills/memory/scripts/recall.py` + 2 Claude Code hooks |
| `python3 recall.py query "<text>"` | — | Top-K matches as one JSON record per line | `skills/memory/scripts/recall.py` |
| `/memory reflect` | `[--session <path>] [--memory-only \| --idea-only]` | Mined candidate JSON records on stdout (one per line); routing summary on stderr; HIGH→canonical save, MEDIUM→see `--route-mode`, LOW→`_inbox/` | `skills/memory/scripts/reflect.py` |
| **(reflect, auto)** | — (fires on Stop + on every SessionStart for idle scan) | Mines + routes candidates per the tri-modal heuristic; renames `.start` → `.reflected` markers on success | `skills/memory/scripts/reflect.py` + 2 Claude Code hooks |
| `/memory search` | — | (stub; thin wrap of `recall.py query` lands in plan #7a part 4) | — |

## When to use which sub-command

| You want to... | Reach for |
|---|---|
| Save a new preference / workflow / fix you want the agent to remember | `/memory save` |
| Mark an entry as "always loaded" — injected at SessionStart for every session | `/memory save --always-load` |
| Replace an existing entry with a corrected version, preserving the old one as audit trail | `/memory evolve` |
| Rename an entry's slug while evolving content | `/memory evolve --new-slug <new>` |
| Have relevant entries automatically injected on every prompt | Recall is automatic — see [Auto-recall via the two-hook pattern](#auto-recall-via-the-two-hook-pattern) below |
| Manually search the vault from the shell | `python3 ~/Antigravity/agent-toolkit/skills/memory/scripts/recall.py query "<text>"` |
| Run reflection on the current session to mine durable entries | `/memory reflect` (manual) — see [Reflection sidecar — Stop + idle + manual](#reflection-sidecar--stop--idle--manual) below |
| Have crashed sessions recovered automatically when you next start Claude Code | Crash-recovery markers are automatic — see [Crash-recovery markers](#crash-recovery-markers) below |

## Scenario 1 — Save a new preference

Capture a dev-flow convention you want the agent to follow forever:

```bash
echo "Status:[x] task closeouts in PLAN.md must be paragraph-long narratives,
not just checkmarks. The next session's context is whatever the closeout
captures — so capture everything that matters: files changed, design calls,
scope adjustments, CI per-OS times, manual verification scenarios, negative
test results when relevant." \
| python3 ~/Antigravity/agent-toolkit/skills/memory/scripts/save.py \
  preferences paragraph-long-status-narratives \
  --vault-path ~/Library/CloudStorage/GoogleDrive-<account>/My\ Drive/Obsidian/MemoryVault \
  --tags dev-flow,status-reports,locked-design-call \
  --always-load
```

Or via Claude Code (the agent invokes the skill's documented flow using `Read` / `Write` / `Edit` tools — byte-identical output):

```
/memory save preferences paragraph-long-status-narratives \
  --always-load \
  --tags dev-flow,status-reports,locked-design-call
```

The file lands at `MemoryVault/personal-private/_always-load/paragraph-long-status-narratives.md` with YAML frontmatter:

```yaml
---
kind: preferences
status: active
created: 2026-05-17
updated: 2026-05-17
tags: [dev-flow, status-reports, locked-design-call]
group: personal-private
slug: paragraph-long-status-narratives
always_load: true
---
```

Followed by the body content.

The `--always-load` flag routes the entry to `_always-load/` (regardless of `--group`) and sets `always_load: true` so future recall hooks inject it at SessionStart.

## Scenario 2 — Evolve a preference when you change your mind

Three months later you decide bulleted lists work better than paragraphs for status reports. Use `/memory evolve` to preserve the audit trail:

```bash
echo "Status:[x] task closeouts in PLAN.md use bulleted lists per task:
- files changed (count + key paths)
- design calls (locked decisions only)
- CI per-OS times (Linux / Mac / Windows)
- manual verification scenarios (if applicable)
- negative-test results (if applicable)
Each bullet 1-2 sentences max." \
| python3 ~/Antigravity/agent-toolkit/skills/memory/scripts/evolve.py \
  personal-private/_always-load/paragraph-long-status-narratives.md \
  "Switched preference: bulleted lists scale better; paragraph format was hard to scan when reviewing PLAN archives" \
  --vault-path ~/Library/CloudStorage/GoogleDrive-<account>/My\ Drive/Obsidian/MemoryVault
```

After:

- **Active entry** at the original path now contains the new bulleted preference. Its frontmatter gains `supersedes: personal-private/_archive/personal-private/_always-load/paragraph-long-status-narratives.md.20260817.md`.
- **Archive entry** at `personal-private/_archive/personal-private/_always-load/paragraph-long-status-narratives.md.20260817.md` contains the original body (unchanged) plus updated frontmatter: `status: superseded`, `superseded_by: <new-path>`, `superseded_at: 2026-08-17T...Z`, `superseded_reason: "Switched preference: bulleted lists scale better..."`.

The recall engine (lands in plan #7a part 2) skips `status: superseded` entries by default, so the agent picks up the new preference automatically. The archive stays for human-review of the supersession history.

## Scenario 3 — Rename an entry while evolving

The slug `paragraph-long-status-narratives` no longer fits the new preference. Use `--new-slug` to rename:

```bash
echo "New content for renamed entry..." \
| python3 ~/Antigravity/agent-toolkit/skills/memory/scripts/evolve.py \
  personal-private/preferences/paragraph-long-status-narratives.md \
  "Renamed to reflect new bulleted format" \
  --new-slug bulleted-status-narratives \
  --vault-path ~/Library/CloudStorage/GoogleDrive-<account>/My\ Drive/Obsidian/MemoryVault
```

The old entry is unlinked from its original path; a new entry appears at `<old-parent>/bulleted-status-narratives.md` with `supersedes:` cross-link to the archive. The archive contains the old body + slug, frozen at the evolution moment.

**Note**: `--new-slug` is rejected for `_always-load/` entries — those evolve in place only (the directory structure under `_always-load/` is flat by convention).

## Auto-recall via the two-hook pattern

Two Claude Code hooks install alongside the memory skill and run automatically — no command needed. They form the **recall side** of MemoryVault: the agent sees relevant entries from your vault without you having to surface them.

### SessionStart hook

Fires once per session boot (also on resume / clear / compact). Globs every entry under `<vault>/personal-private/_always-load/*.md` and injects their bodies into session context. A single transparency line on stderr names what got loaded:

```
[memory-recall-session-start] Loaded 3 MemoryVault always-load entries: paragraph-status, commit-trailer, release-pair-order
```

**Hard time budget**: 500ms wall clock. On overrun: emits partial results + warning, exits 0 (never blocks session boot). Filtering invariants: entries with `status: superseded` are skipped.

### UserPromptSubmit hook

Fires on every user prompt. Takes the prompt as a recall query, runs the **5-step recall engine**, dedups results against the always-load set (no redundant context), and injects up to K=5 matches as additional context before the agent processes the prompt:

```
[memory-recall-prompt-submit] Loaded 2 relevant entries: evolve-pattern, supersedes-cross-link
```

**Hard time budget**: 300ms wall clock. Same degraded-graceful contract as SessionStart.

### Recall engine — 5 steps

1. **Tokenize the query** — lowercase + alphanumeric runs + drop tokens shorter than 3 chars.
2. **Vec search** — embed the query (via the configured mode — see Embedding modes below) + sqlite-vec MATCH query for top-k by cosine similarity.
3. **Grep + frontmatter scan** in parallel — count distinct query tokens appearing in `slug + tags + body[:500]` per entry; filter `status: superseded`; exclude `_archive/` always + `_inbox/` by default.
4. **Merge** — combined score = `sim × 0.7 + keyword_match_count × 0.3` (locked weights; tune from real use per Tech Debt #7).
5. **Dedup + top-K** — drop entries that match the always-load set (already injected), sort by combined-desc, return top-K (default 5).

**Degraded-graceful chain** — any failure falls back rather than blocking:
- sqlite-vec not installed → grep-only recall.
- No API key set + no local sentence-transformers → grep-only recall.
- Vec-index empty → grep-only recall.
- Time budget exceeded → partial results + warning.

### Manual recall (operator debug)

Run the engine directly from the shell. JSON-Lines output is pipeable for scripting:

```bash
python3 ~/Antigravity/agent-toolkit/skills/memory/scripts/recall.py \
  --vault-path ~/Library/CloudStorage/GoogleDrive-<account>/My\ Drive/Obsidian/MemoryVault \
  query "how do I evolve a memory entry" -k 3
```

Output (one JSON record per line):

```json
{"path": "personal-private/workflow/evolve-pattern.md", "slug": "evolve-pattern", "sim": 0.73, "keyword": 3, "combined": 1.411}
{"path": "personal-private/preferences/supersedes-cross-link.md", "slug": "supersedes-cross-link", "sim": 0.52, "keyword": 2, "combined": 0.964}
```

Useful for tuning the merge weights, debugging "why didn't this entry surface", or composing manual searches before `/memory search` lands as a first-class skill sub-command (deferred to a future plan).

Flags:
- `-k N` — top-K (default 5).
- `--budget-ms N` — time budget override (default 300ms).
- `--include-inbox` — surface `_inbox/` entries too (default excluded — those are raw, unfiltered candidates).
- `--mode api|local|stub` — embedding mode override (default: api unless `MEMORY_USE_API_EMBEDDINGS=false`).

### Antigravity equivalent

Antigravity has no first-class hook surface as of v0.9.0, so the SessionStart + UserPromptSubmit hooks land on Claude Code only. The functional equivalent for Antigravity is a future **always-on rule** that reads from `_always-load/` at agent boot + a per-prompt skill auto-invocation — tracked under MemoryVault's discovery-mining part. The recall engine itself (`recall.py`) is host-agnostic and exposed via the CLI today; Antigravity skills can shell out to it directly.

## Reflection sidecar — Stop + idle + manual

Three trigger surfaces run the **same mining logic** in `skills/memory/scripts/reflect.py`. Together they form the **write loop** — distinct from the recall side documented above.

### Mining algorithm

Each trigger reads a Claude Code session transcript (at `~/.claude/projects/<cwd-slug>/<session-id>.jsonl`) and runs two parallel mining passes:

- **3-category memory mine**: scans user + assistant messages for explicit user preferences (`always X` / `never Y` / `I prefer Z` / `use X not Y` patterns → **HIGH** confidence), user corrections (`no, that's wrong` / `you should have X` patterns → **MEDIUM**), fixes & workarounds (`fixed by X` / `resolved by Y` / `workaround` patterns → **MEDIUM**), and workflow patterns (any tool used 3+ times → **MEDIUM**).
- **Idea-candidate mine**: scans for forward-looking statements (`we should also` / `later we could` / `follow-up` / `could be its own` patterns).

Each mined candidate gets full instrumentation per Tech Debt #7: category + confidence + slug suggestion + title + body + rationale (which pattern matched) + verbatim excerpts (windowed ±80 chars) + occurrences count. The rationale + excerpts make `/memory inspect` (future plan) the auditing surface for "why did this candidate surface?".

### Tri-modal routing — 3 modes

After mining, candidates route per **confidence tier** + selected mode:

| Mode | HIGH | MEDIUM | LOW | Idea |
|---|---|---|---|---|
| `auto` (default; hook-safe) | canonical save | `_inbox/` | `_inbox/` | `_inbox/` |
| `silent` | canonical save | canonical save (auto-approve) | `_inbox/` | `_inbox/` |
| `interactive` | canonical save | stdin prompt (approve / reject / skip / inbox) | `_inbox/` | `_inbox/` |

Mode resolution: `--route-mode` CLI flag → `MEMORY_REVIEW_MODE` env var → default `auto`. `interactive` mode falls back to `auto` when stdin isn't a TTY (preserves the never-block-the-hook contract).

### Trigger 1: manual `/memory reflect`

User-invokable; runs against the current Claude Code session by default or an arbitrary transcript path via `--session`. Useful for dogfooding new patterns, re-running over an old session, or doing on-demand triage:

```bash
python3 ~/Antigravity/agent-toolkit/skills/memory/scripts/reflect.py \
  ~/.claude/projects/<cwd-slug>/<session-id>.jsonl \
  --summary --route --route-mode interactive
```

`--summary` prefixes a 1-line summary record; `--route` enables the routing pass (requires `--vault-path` or `MEMORY_VAULT_PATH`). Without `--route`, the script just emits candidates on stdout for inspection.

### Trigger 2: Stop-event hook (`memory-reflect-stop`)

Auto-installed at `.claude/hooks/memory-reflect-stop.sh`. Fires on Claude Code's `Stop` event (end of each agent turn). Parses the Stop payload for `session_id` + `cwd`, resolves the transcript path, invokes `reflect.py --route`, emits a transparency line on stderr:

```
[memory-reflect-stop] Mined 3 memory + 1 idea candidates from <transcript-path>; saved 1, inboxed 3
```

Coexists with `commit-on-stop` (both register on the Stop event). Hook context has no TTY, so the `interactive` mode falls back to `auto` automatically. Never blocks session end — graceful-skip exhaustively across missing reflect.py / no session_id on stdin / transcript missing / MEMORY_VAULT_PATH unset.

### Trigger 3: idle-time hook (`memory-reflect-idle`)

Auto-installed at `.claude/hooks/memory-reflect-idle.sh`. **First new agent-toolkit hook primitive** — Claude Code has no native "idle" event, so this hook fires on `SessionStart` instead (alongside `memory-recall-session-start`) and scans `.harness/session-id-*.start` markers for orphans (markers older than 1 hour = sessions where Stop didn't fire — Claude Code crashed / kill -9 / force-quit). For each orphan, it invokes `reflect.py --route` retroactively, renames `.start` → `.reflected` on success. Also GCs `.reflected` markers older than 30 days.

Three convergent trigger surfaces give layered coverage:

1. **SessionStart event** (auto, every session boot): catches the common "operator returned after break" case.
2. **Manual invocation**: `bash .claude/hooks/memory-reflect-idle.sh` for on-demand orphan sweep.
3. **Cron / launchd / scheduled task** (operator-installed; opt-in for aggressive coverage): example crontab — `*/30 * * * * cd /path/to/project; bash .claude/hooks/memory-reflect-idle.sh`.

Idle threshold + GC threshold are env-overridable: `MEMORY_IDLE_THRESHOLD_SEC` (default 3600) + `MEMORY_REFLECTED_GC_SEC` (default 2592000).

## Crash-recovery markers

Locked design call B2.ii: every session writes a `.harness/session-id-<uuid>.start` marker at SessionStart; Stop hook renames it to `.reflected` after successful reflection. The marker format is plain text (not JSON — operator-debuggable by hand):

```
session_id: <uuid>
started_at: <iso-8601-utc>
transcript: <absolute-path-to-jsonl>
```

If Stop doesn't fire (crash, kill -9, force-quit), the `.start` marker stays — the next SessionStart triggers the idle hook, which scans for `.start` markers older than the idle threshold, runs `reflect.py --route` retroactively, and renames them. No agent observation lost across crashed sessions.

Markers live in `.harness/` (gitignored — runtime metadata only; no PII / transcript content). The idle hook's 30-day GC keeps the directory bounded without operator intervention.

## Vault path resolution

The skill resolves the MemoryVault root in this order:

1. **`--vault-path <path>`** CLI arg (highest priority; overrides everything)
2. **`MEMORY_VAULT_PATH`** environment variable
3. **Config file** at `~/.config/agent-toolkit/memory.yml` (`vault_path:` key) — **documented but not yet implemented as of v0.9.0**; tracked for a future task

If none resolve, both `save.py` and `evolve.py` error out with a clear next-step message. No implicit fallback to `cwd` or `~` (prevents accidental writes to wrong directories).

## Embedding modes

By default the skill embeds entries via the Voyage AI endpoint (Anthropic's recommended embedding provider). Set `MEMORY_USE_API_EMBEDDINGS=false` to use the local `sentence-transformers` fallback (offline-capable; ~80MB `all-MiniLM-L6-v2` model; `pip install sentence-transformers` required). The local model cache lives at `~/.cache/agent-toolkit/sentence-transformers/` — override with `AGENT_TOOLKIT_SENTENCE_TRANSFORMERS_CACHE` if you need a different location.

The embedding step is **async** for writes — `/memory save` and `/memory evolve` queue to `<vault>/_meta/embedding-queue.jsonl` synchronously (fast; never blocks the file write) and a separate drain step (`python3 vec_index.py --vault-path <vault> drain` or future idle-time hook) processes the queue + writes to the vec-index. The **recall** side (UserPromptSubmit hook) is **synchronous** — it embeds the query inline + runs vec search + grep merge within the 300ms budget. This means:

- Save / evolve always succeed even if no embedding mode is available (no API key, no local model, sqlite-vec missing). The queue accumulates pending work.
- Recall always returns SOMETHING — if vec search fails (no API key, no local model, sqlite-vec missing, network down), the grep+frontmatter path still runs and returns keyword matches.
- Drain processes the queue when deps become available — graceful-skip pattern across multiple layers (sqlite-vec / embedding mode / enable_load_extension).
- The queue file is operator-debuggable (`cat <vault>/_meta/embedding-queue.jsonl`) and the drain function is idempotent (re-runs on a stable queue produce the same final state).

**Offline-capable recall**: with `MEMORY_USE_API_EMBEDDINGS=false` + `pip install sentence-transformers` + `pip install sqlite-vec` + a Homebrew/pyenv Python (Apple's macOS system Python disables `enable_load_extension`), the full happy path works without network access. Without those deps, recall degrades gracefully to grep-only — slower-to-match but always-on.

## Troubleshooting

**`save.py` exits with `No vault path resolved`**
Set `--vault-path` or `export MEMORY_VAULT_PATH=...` before invoking. The skill refuses to guess.

**`save.py` exits with `entry already exists at <path>`**
The collision check is non-negotiable — `/memory save` never overwrites. Either use a different slug, or use `/memory evolve` to supersede the existing entry (preserves it as audit trail).

**`evolve.py` exits with `old entry status is 'superseded', not 'active'`**
You can't evolve an already-superseded entry. The supersession graph traverses outward from active state. Manual escape hatch: edit the entry's `status:` frontmatter to `active` if you really need to evolve it.

**Drain reports `skipped: N, processed: 0` with `errors: 0`**
This is the graceful-skip path: sqlite-vec is missing OR the Python build doesn't support `enable_load_extension` (Apple system Python). Workaround: install Homebrew Python (`brew install python`) or use pyenv, then `pip install sqlite-vec`. Until then, save + evolve still work; embeddings queue stays pending.

**Drain reports embedding skipped for some entries**
The configured embedding mode wasn't available for those entries (no API key for api mode, or `sentence-transformers` missing for local mode). The entries stay in the queue; re-running drain after configuring the mode will process them.

**Recall hook fires but no entries surface in the agent's context**
Check the hook's stderr line — Claude Code shows hook output in its logs. If it says `Loaded 0 ...` despite saved entries, either `MEMORY_VAULT_PATH` is unset (hook can't find the vault), `_always-load/` is empty (SessionStart hook), or no entries matched the query tokens (UserPromptSubmit hook — verify via the manual `recall.py query` invocation above).

**Recall transparency line includes `(WARNING: 500ms time budget exceeded ...)`**
The vault has grown large enough that the walk + frontmatter parse + read overrun the 500ms (SessionStart) or 300ms (UserPromptSubmit) budgets. Partial results were emitted; the hook didn't block. Mitigation: prune `_always-load/` (those are read on every session boot — keep them lean), or move stale entries to `_archive/` via `/memory evolve`.

**Recall returns "embedding unavailable" stderr but still surfaces results**
This is the graceful-skip path firing — no API key + no local model, so vec search short-circuits and recall falls back to grep+frontmatter-only. Results are still returned; semantic-paraphrase matches won't surface but exact-keyword matches will. Configure `VOYAGE_API_KEY` / `ANTHROPIC_API_KEY` env var (api mode) or `pip install sentence-transformers` + set `MEMORY_USE_API_EMBEDDINGS=false` (local mode) to restore the full pipeline.

**Stop hook fired but no entries appear in MemoryVault**
Check the hook's stderr line in Claude Code logs. If it says `saved 0, inboxed N`, no HIGH-confidence patterns were detected — all candidates went to `_inbox/` for triage. Check `<vault>/personal-private/_inbox/` for the mined candidates; review + promote via `/memory save` (or `/memory evolve` to supersede an existing entry). If stderr says `MEMORY_VAULT_PATH set?`, the hook's environment didn't inherit the vault env var — set it globally in your shell config (`.bashrc` / `.zshrc`) so Claude Code's hook child processes see it.

**Idle hook never seems to fire**
The idle hook is registered on `SessionStart` (not a true idle event — Claude Code doesn't expose one). It scans for orphan `.harness/session-id-*.start` markers only when SessionStart events fire (boot / resume / clear / compact). For more aggressive coverage, set up a cron job: `*/30 * * * * cd /path/to/project; bash .claude/hooks/memory-reflect-idle.sh`. Also: the default idle threshold is 1 hour — markers younger than that are skipped (session might still be active). Override via `MEMORY_IDLE_THRESHOLD_SEC` env var for testing.

**Crashed session — what should I see?**
After Claude Code crashes mid-session: `.harness/session-id-<sid>.start` should still exist (Stop never fired, so no rename). Next time you boot Claude Code in that project: SessionStart fires, `memory-reflect-idle.sh` scans, finds the orphan past the 1-hour threshold, runs `reflect.py --route` against the crashed session's transcript, renames the marker to `.reflected`. If the marker doesn't get reflected even after waiting 1+ hour: check `MEMORY_VAULT_PATH` is set in the operator's shell config, and `reflect.py --route` requires the vault — without it, the rename doesn't happen + the marker stays for retry next session.

**Interactive `/memory reflect` doesn't prompt; goes straight to inbox**
The interactive mode requires stdin to be a TTY. If you piped output / redirected stdin / ran from a non-interactive context, `--route-mode interactive` falls back to `auto` (which sends MEDIUM to `_inbox/`). Re-run from an interactive shell or use `--route-mode silent` to auto-approve MEDIUM candidates without prompting.

**`_inbox/` is growing unchecked**
Low-signal candidates accumulate in `_inbox/` over time. There's no automatic triage — that's plan #7a part 5's `seed-pass` scope. For now, periodically: `ls <vault>/personal-private/_inbox/` to see what's piled up; for each entry, decide to `/memory save` (promote to canonical), `/memory evolve` (supersede an existing entry), or `rm` (reject). Future plans will add `/memory triage` for batch processing.

## See also

- [MemoryVault design doc](memoryvault) — the canonical "Why we built this" entry point per the locked design call from plan #6. Covers the full architecture across all 6 parts.
- [Customization Types](Customization-Types) — `kind: skill` row covers the memory skill.
- [Manifest Schema](Manifest-Schema) — frontmatter contract for skill manifests.
- [Per-Host Paths](Per-Host-Paths) — destination paths per kind per host.
- [Use the design skill](Use-The-Design-Skill) — the skill that authored MemoryVault's design doc (first real dogfood).
