#!/usr/bin/env python3
# reflect.py — MemoryVault reflection sidecar mining logic.
#
# Reads a Claude Code session transcript (JSONL at
# ~/.claude/projects/<repo>/<session-id>.jsonl) + emits candidate entries
# in two parallel mining passes:
#
#   1. 3-category mine (writes to MemoryVault):
#      - Successful Workflows
#      - User Preferences
#      - Fixes & Workarounds
#   2. Idea-candidate mine (downstream idea-ledger part subscribes):
#      - follow-ups / future projects / research candidates
#
# Each candidate carries:
#   - category (preferences | workflow | fix | idea)
#   - confidence (HIGH | MEDIUM | LOW) per the locked tri-modal heuristic
#   - rationale (what pattern matched — instrumentation per Tech Debt #7)
#   - excerpts (verbatim transcript snippets supporting the candidate)
#   - occurrences (match count — used for confidence routing)
#
# Plan #7a part 3 task 1 (this commit) ships ONLY the mining module +
# CLI surface. Tasks 2-7 of part 3 wire this into:
#   - /memory reflect sub-command (task 2)
#   - Stop-event hook (task 3)
#   - Idle-time hook (task 4)
#   - Tri-modal routing + interactive review (task 5)
#   - Crash-recovery markers (task 6)
#   - Documentation (task 7)
#
# Locked design calls referenced:
#   - B1: aggressive end-of-session sweep + parallel idea-candidate sweep
#   - B2.iii: tri-modal confidence routing (HIGH/MEDIUM/LOW)
#   - Tech Debt #7: ship instrumented + tune from real use

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

# ── Pattern catalog ────────────────────────────────────────────────────────
#
# Each entry is (compiled_regex, rationale_string). The rationale gets
# surfaced in the candidate's `rationale` field — operator-debug surface
# for "why was this mined?". Patterns are CASE-INSENSITIVE.
#
# Heuristic shape per Tech Debt #7 — ship simple + instrumented; tune from
# real use. v1 explicitly avoids fancy NLP / LLM-based extraction. The
# "user manually corrected the agent" pattern is the noisy one (per part
# doc's "Notes for the implementing /work session" — defer fancy detection
# to follow-up if simple heuristic too noisy).

# HIGH-confidence: explicit user preference statements ("always X" / "I prefer X")
_PREFERENCE_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\b(?:always|never)\s+\w+(?:\s+\w+){0,5}", re.IGNORECASE),
     "explicit always/never directive"),
    (re.compile(r"\bI\s+(?:prefer|want|need|like|expect|require)\b[^.!?\n]{0,80}",
                re.IGNORECASE),
     "explicit preference statement"),
    (re.compile(r"\b(?:use|do|prefer)\s+[\w\s-]{1,40}\s+(?:not|instead of|rather than)\s+\w+",
                re.IGNORECASE),
     "explicit choice statement"),
    (re.compile(r"\bdon'?t\s+(?:use|do|add|include|put|write|commit)\b[^.!?\n]{0,80}",
                re.IGNORECASE),
     "explicit negative directive"),
]

# MEDIUM-confidence: user corrected the agent — simple heuristic per part-doc
# note. Detection is intentionally lossy — false positives are filtered by the
# interactive review prompt (task 5); false negatives end up in _inbox/ or stay
# uncaptured. Tune from real use per Tech Debt #7.
_CORRECTION_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\b(?:no|nope|actually|wait)[\s,.]+[^.!?\n]{0,80}(?:wrong|incorrect|missing|broken|not right)\b",
                re.IGNORECASE),
     "user correction signal"),
    (re.compile(r"\b(?:you|that)\s+should(?:n'?t|\s+not)?\s+have\s+\w+",
                re.IGNORECASE),
     "user retrospective correction"),
    (re.compile(r"\bI\s+(?:said|told|asked)\s+(?:you\s+)?(?:to\s+)?\w+",
                re.IGNORECASE),
     "user repeats instruction"),
]

# MEDIUM-confidence: fixes / workarounds
_FIX_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\bfixed by\b[^.!?\n]{0,120}", re.IGNORECASE),
     "explicit fix statement"),
    (re.compile(r"\bresolved by\b[^.!?\n]{0,120}", re.IGNORECASE),
     "explicit resolution statement"),
    (re.compile(r"\bworkaround\b[^.!?\n]{0,120}", re.IGNORECASE),
     "workaround mention"),
    (re.compile(r"\b(?:bug|error|issue|failure)\b[^.!?\n]{0,40}\bwas\b[^.!?\n]{0,40}\b(?:caused by|due to|because of)\b[^.!?\n]{0,80}",
                re.IGNORECASE),
     "root cause statement"),
]

# Idea-candidate patterns
_IDEA_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\bwe\s+(?:should|could)\s+(?:also|later|eventually)\b[^.!?\n]{0,120}",
                re.IGNORECASE),
     "explicit follow-up suggestion"),
    (re.compile(r"\b(?:later|future)\b[\s,]+[^.!?\n]{0,30}\b(?:could|should|might|may|would)\b[^.!?\n]{0,80}",
                re.IGNORECASE),
     "future-possibility statement"),
    (re.compile(r"\bfollow.?ups?\b[^.!?\n]{0,120}", re.IGNORECASE),
     "follow-up marker"),
    (re.compile(r"\bcould be (?:its|their) own\b[^.!?\n]{0,80}", re.IGNORECASE),
     "potential project split"),
    (re.compile(r"\bas a follow.?up\b[^.!?\n]{0,120}", re.IGNORECASE),
     "follow-up marker"),
    (re.compile(r"\bidea[s]?\s*[:—-]\s+\w+[^.!?\n]{0,120}", re.IGNORECASE),
     "idea declaration"),
]

# Workflow detection: tool-use frequency threshold. Locked design call B1
# says "pattern-inferred 3+ occurrences" → MEDIUM. Simple v1 detection: count
# distinct tool names used; any tool used N>=3 times suggests a workflow.
_WORKFLOW_OCCURRENCE_THRESHOLD = 3


@dataclass
class Candidate:
    """A mined candidate entry. Either heading for MemoryVault (memory pass)
    or for the future idea-ledger (idea pass)."""
    category: str          # preferences | workflow | fix | idea
    confidence: str        # HIGH | MEDIUM | LOW
    slug: str              # kebab-case slug suggestion
    title: str             # 1-line summary
    body: str              # full markdown body for save.py
    rationale: str         # what pattern matched (instrumentation)
    excerpts: list[str] = field(default_factory=list)  # verbatim snippets
    occurrences: int = 1   # match count (instrumentation)


def _extract_text(msg: dict) -> str:
    """Extract plain text from a transcript message.

    Claude Code transcripts have two content shapes:
      - user messages: `message.content` is a string OR a list of content blocks
      - assistant messages: `message.content` is always a list of content blocks
        ({type: text|thinking|tool_use|tool_result, ...})

    We extract `text` blocks + record tool_use names as bracketed markers
    (e.g. `[tool_use: Bash]`) so workflow detection can tally them downstream.
    Thinking blocks are skipped — they're internal-only and not part of the
    agent's visible output.
    """
    content = msg.get("message", {}).get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for c in content:
            if not isinstance(c, dict):
                continue
            ctype = c.get("type")
            if ctype == "text":
                parts.append(c.get("text", ""))
            elif ctype == "tool_use":
                tool = c.get("name", "?")
                parts.append(f"[tool_use: {tool}]")
            # Skip thinking + tool_result + attachments — not part of mining
            # surface area (per part doc: mining works on user signals +
            # assistant turn content, not introspection).
        return " ".join(parts)
    return ""


def _extract_tool_uses(msg: dict) -> list[str]:
    """Return the list of tool names used in an assistant message."""
    if msg.get("type") != "assistant":
        return []
    content = msg.get("message", {}).get("content")
    if not isinstance(content, list):
        return []
    tools: list[str] = []
    for c in content:
        if isinstance(c, dict) and c.get("type") == "tool_use":
            tools.append(c.get("name", "?"))
    return tools


def _slug_from_text(text: str, max_words: int = 6) -> str:
    """Generate a kebab-case slug from text.

    Lowercases, extracts alphanumeric runs, takes the first N tokens,
    joins with `-`. Falls back to "candidate" if input has no extractable
    alphanumerics (rare — typically only for emoji-only messages).
    """
    words = re.findall(r"[a-z0-9]+", text.lower())[:max_words]
    return "-".join(words) or "candidate"


def _excerpt_around(text: str, start: int, end: int, radius: int = 80) -> str:
    """Extract a windowed excerpt around a regex match.

    Returns the match plus up to `radius` chars on each side, with `...`
    ellipses if the window doesn't cover the full text. Newlines flattened
    to spaces so the excerpt is a single line (rationale + excerpts are
    rendered in transparency lines + interactive review prompts; multi-line
    excerpts would break that surface).
    """
    lo = max(0, start - radius)
    hi = min(len(text), end + radius)
    excerpt = text[lo:hi].replace("\n", " ").replace("\r", " ").strip()
    # Collapse runs of whitespace to single spaces for readability.
    excerpt = re.sub(r"\s+", " ", excerpt)
    if lo > 0:
        excerpt = "..." + excerpt
    if hi < len(text):
        excerpt = excerpt + "..."
    return excerpt


def load_messages(transcript_path: Path) -> list[dict]:
    """Read transcript JSONL + return only user + assistant messages in order.

    Skips queue-operation / ai-title / last-prompt / attachment / system /
    custom-title — those are metadata, not mining surface area.

    Raises FileNotFoundError if the transcript path doesn't exist. Malformed
    JSON lines are silently skipped (transcripts can have partial writes if
    Claude Code crashed mid-line; ship robust).
    """
    if not transcript_path.exists():
        raise FileNotFoundError(f"Transcript not found: {transcript_path}")
    messages: list[dict] = []
    with open(transcript_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if r.get("type") in ("user", "assistant"):
                messages.append(r)
    return messages


def _scan_patterns(
    text: str,
    patterns: list[tuple[re.Pattern, str]],
    *,
    role: str,
) -> list[tuple[str, str, str]]:
    """Run all patterns over text. Returns list of (match_text, rationale, excerpt) tuples.

    `role` is used in the excerpt rationale tagging but doesn't change matching
    behavior (kept here for future per-role pattern tuning).
    """
    out: list[tuple[str, str, str]] = []
    for pattern, rationale in patterns:
        for m in pattern.finditer(text):
            excerpt = _excerpt_around(text, m.start(), m.end())
            out.append((m.group(0), rationale, excerpt))
    return out


def mine_transcript(transcript_path: Path) -> dict:
    """Mine a session transcript for memory + idea candidates.

    Returns a dict with:
      - transcript_path: stringified path
      - messages_processed: int (user + assistant messages scanned)
      - memory_candidates: list[Candidate] for the 3-category pass
      - idea_candidates: list[Candidate] for the idea-ledger pass

    Candidates are deduped per (category, slug) — repeated patterns bump
    `occurrences` rather than emit duplicate candidates. Confidence is
    initially set per pattern type; candidates with `occurrences < 3` in
    MEDIUM-mode-initial buckets get demoted to LOW per the locked tri-modal
    routing (single-instance inference → _inbox/).

    The function is deterministic for a given transcript — same input
    produces same output. No I/O beyond reading the transcript.
    """
    messages = load_messages(transcript_path)

    # (category, slug) → Candidate. Dedupes repeated matches.
    seen_memory: dict[tuple[str, str], Candidate] = {}
    seen_ideas: dict[str, Candidate] = {}

    # Tool-use frequency tally for workflow mining
    tool_counts: dict[str, int] = {}

    for msg in messages:
        role = msg.get("type")
        text = _extract_text(msg)
        if not text:
            continue

        # ── Preferences + corrections + ideas only apply to user messages.
        # User intent is the signal; agent outputs are derivative.
        if role == "user":
            # HIGH-confidence preferences
            for match, rationale, excerpt in _scan_patterns(
                text, _PREFERENCE_PATTERNS, role=role
            ):
                slug = _slug_from_text(match)
                key = ("preferences", slug)
                if key in seen_memory:
                    seen_memory[key].occurrences += 1
                    seen_memory[key].excerpts.append(excerpt)
                else:
                    seen_memory[key] = Candidate(
                        category="preferences",
                        confidence="HIGH",
                        slug=slug,
                        title=match.strip()[:80],
                        body=f"User stated: {excerpt}",
                        rationale=rationale,
                        excerpts=[excerpt],
                    )

            # MEDIUM-confidence corrections
            for match, rationale, excerpt in _scan_patterns(
                text, _CORRECTION_PATTERNS, role=role
            ):
                slug = _slug_from_text(match)
                key = ("preferences", slug)
                if key in seen_memory:
                    seen_memory[key].occurrences += 1
                    seen_memory[key].excerpts.append(excerpt)
                else:
                    seen_memory[key] = Candidate(
                        category="preferences",
                        confidence="MEDIUM",
                        slug=slug,
                        title=f"Correction: {match.strip()[:60]}",
                        body=f"User corrected the agent: {excerpt}",
                        rationale=rationale,
                        excerpts=[excerpt],
                    )

            # Idea candidates
            for match, rationale, excerpt in _scan_patterns(
                text, _IDEA_PATTERNS, role=role
            ):
                slug = _slug_from_text(excerpt[:60])
                if slug in seen_ideas:
                    seen_ideas[slug].occurrences += 1
                    seen_ideas[slug].excerpts.append(excerpt)
                else:
                    seen_ideas[slug] = Candidate(
                        category="idea",
                        confidence="MEDIUM",
                        slug=slug,
                        title=excerpt[:80],
                        body=excerpt,
                        rationale=rationale,
                        excerpts=[excerpt],
                    )

        # ── Fixes apply to both user + assistant messages (either side can
        # report a fix).
        for match, rationale, excerpt in _scan_patterns(
            text, _FIX_PATTERNS, role=role
        ):
            slug = _slug_from_text(excerpt[:60])
            key = ("fix", slug)
            if key in seen_memory:
                seen_memory[key].occurrences += 1
                seen_memory[key].excerpts.append(excerpt)
            else:
                seen_memory[key] = Candidate(
                    category="fix",
                    confidence="MEDIUM",
                    slug=slug,
                    title=f"Fix: {excerpt[:60]}",
                    body=f"Fix observed: {excerpt}",
                    rationale=rationale,
                    excerpts=[excerpt],
                )

        # ── Workflow: tally tool usages from assistant turns.
        for tool in _extract_tool_uses(msg):
            tool_counts[tool] = tool_counts.get(tool, 0) + 1

    memory_candidates: list[Candidate] = list(seen_memory.values())
    idea_candidates: list[Candidate] = list(seen_ideas.values())

    # Workflow candidates: any tool used >= threshold times.
    for tool, count in sorted(tool_counts.items()):
        if count >= _WORKFLOW_OCCURRENCE_THRESHOLD:
            slug = _slug_from_text(f"workflow {tool}")
            memory_candidates.append(Candidate(
                category="workflow",
                confidence="MEDIUM",
                slug=slug,
                title=f"Workflow: {tool} used {count}x",
                body=(
                    f"The `{tool}` tool was invoked {count} times during this "
                    f"session. If this represents a repeatable workflow, capture "
                    f"the sequence + when to use it."
                ),
                rationale=(
                    f"tool_use frequency threshold "
                    f"(N>={_WORKFLOW_OCCURRENCE_THRESHOLD}, observed {count})"
                ),
                excerpts=[],
                occurrences=count,
            ))

    # ── Tri-modal demotion: MEDIUM-initial candidates with <3 occurrences
    # get demoted to LOW (single-instance inference → _inbox/ per locked
    # design call B2.iii). HIGH candidates stay HIGH regardless of count
    # (explicit user signal trumps frequency).
    for c in memory_candidates:
        if c.confidence == "MEDIUM" and c.occurrences < _WORKFLOW_OCCURRENCE_THRESHOLD:
            c.confidence = "LOW"
    # For idea candidates, the bar is lower (2+ occurrences keeps MEDIUM;
    # ideas don't need 3 repetitions to be worth surfacing).
    for c in idea_candidates:
        if c.confidence == "MEDIUM" and c.occurrences < 2:
            c.confidence = "LOW"

    # Sort: HIGH first, then MEDIUM, then LOW; within tier, by occurrences desc.
    _confidence_order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
    memory_candidates.sort(
        key=lambda c: (_confidence_order.get(c.confidence, 99), -c.occurrences, c.slug)
    )
    idea_candidates.sort(
        key=lambda c: (_confidence_order.get(c.confidence, 99), -c.occurrences, c.slug)
    )

    return {
        "transcript_path": str(transcript_path),
        "messages_processed": len(messages),
        "memory_candidates": memory_candidates,
        "idea_candidates": idea_candidates,
    }


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="memory-reflect",
        description=(
            "Mine a Claude Code session transcript for durable candidate "
            "entries. Emits one JSON record per line (pass='memory' for the "
            "3-category mine; pass='idea' for the idea-ledger mine). "
            "Plan #7a part 3 task 1 — mining only; wiring to /memory reflect "
            "+ Stop/idle hooks + tri-modal routing lands in tasks 2-7."
        ),
    )
    parser.add_argument(
        "transcript_path",
        help="path to a Claude Code session transcript JSONL "
             "(typically ~/.claude/projects/<repo>/<session-id>.jsonl)",
    )
    parser.add_argument(
        "--memory-only", action="store_true",
        help="emit only the 3-category memory candidates (skip idea pass)",
    )
    parser.add_argument(
        "--idea-only", action="store_true",
        help="emit only the idea candidates (skip memory pass)",
    )
    parser.add_argument(
        "--summary", action="store_true",
        help="prefix output with a 1-line summary "
             "(messages processed + candidate counts per pass)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    try:
        result = mine_transcript(Path(args.transcript_path).expanduser())
    except FileNotFoundError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    if args.summary:
        print(json.dumps({
            "pass": "summary",
            "transcript_path": result["transcript_path"],
            "messages_processed": result["messages_processed"],
            "memory_candidate_count": len(result["memory_candidates"]),
            "idea_candidate_count": len(result["idea_candidates"]),
        }))

    if not args.idea_only:
        for c in result["memory_candidates"]:
            print(json.dumps({"pass": "memory", **asdict(c)}))
    if not args.memory_only:
        for c in result["idea_candidates"]:
            print(json.dumps({"pass": "idea", **asdict(c)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
