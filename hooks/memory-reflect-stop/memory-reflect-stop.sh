#!/usr/bin/env bash
# memory-reflect-stop — mine the just-ended session's transcript on Stop.
#
# Fires on Claude Code's Stop event. Parses the stdin JSON payload for
# session_id, computes the transcript path at
# ~/.claude/projects/<cwd-slug>/<session_id>.jsonl, and invokes reflect.py
# to mine durable candidates. Output on stdout (pass-through from reflect.py);
# transparency line on stderr.
#
# Tri-modal routing (HIGH→auto / MEDIUM→interactive / LOW→inbox) lands in
# plan #7a part 3 task 5; this hook ships the mining-only scaffold.
#
# See hook.md in this directory for full documentation.

set -uo pipefail  # NOTE: no -e — graceful-skip pattern; hook must never block session end.

# Resolve reflect.py location. Memory skill installs to:
#   .claude/skills/memory/scripts/reflect.py
# Hook runs from target project root (Claude Code's cwd convention).
REFLECT_PY=".claude/skills/memory/scripts/reflect.py"
if [[ ! -f "$REFLECT_PY" ]]; then
    # Memory skill not installed; nothing to do.
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

# Stop hook stdin payload (per Claude Code hook spec): JSON with at minimum
# session_id (UUID) and cwd. We extract both to compute the transcript path.
# Read stdin into a variable so we can parse it WITHOUT requiring jq (not
# universally installed; Python json module is always present alongside python3).
PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
    echo "[memory-reflect-stop] no stdin payload (skipping)" >&2
    exit 0
fi

# Parse session_id + cwd via a one-liner Python invocation. Returns
# "<session_id>\t<cwd>" or empty on parse failure.
PARSED="$(printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
sid = d.get("session_id") or ""
cwd = d.get("cwd") or ""
if sid:
    print(f"{sid}\t{cwd}")
' 2>/dev/null)"

if [[ -z "$PARSED" ]]; then
    echo "[memory-reflect-stop] no session_id on stdin (skipping)" >&2
    exit 0
fi

SESSION_ID="$(printf '%s' "$PARSED" | cut -f1)"
CWD="$(printf '%s' "$PARSED" | cut -f2)"
if [[ -z "$CWD" ]]; then
    CWD="$(pwd)"
fi

# Compute transcript path: ~/.claude/projects/<cwd-slug>/<session_id>.jsonl
# where <cwd-slug> = CWD with '/' replaced by '-' and a leading '-'.
CWD_SLUG="-$(printf '%s' "$CWD" | tr '/' '-')"
TRANSCRIPT="$HOME/.claude/projects/${CWD_SLUG}/${SESSION_ID}.jsonl"

if [[ ! -f "$TRANSCRIPT" ]]; then
    echo "[memory-reflect-stop] transcript not found: $TRANSCRIPT (skipping)" >&2
    exit 0
fi

# Invoke reflect.py with --summary. stdout passes through (one JSON record
# per line for future task-5 routing to consume); stderr gets our transparency
# line + any errors from reflect.py.
SUMMARY_LINE="$(python3 "$REFLECT_PY" "$TRANSCRIPT" --summary 2>/dev/null | head -1)"
if [[ -z "$SUMMARY_LINE" ]]; then
    echo "[memory-reflect-stop] reflect.py returned no output for $TRANSCRIPT (skipping)" >&2
    exit 0
fi

# Extract candidate counts from the summary JSON for the transparency line.
MEM_COUNT="$(printf '%s' "$SUMMARY_LINE" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get("memory_candidate_count", 0))
except Exception:
    print(0)
' 2>/dev/null || echo 0)"
IDEA_COUNT="$(printf '%s' "$SUMMARY_LINE" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get("idea_candidate_count", 0))
except Exception:
    print(0)
' 2>/dev/null || echo 0)"

echo "[memory-reflect-stop] Mined ${MEM_COUNT} memory candidates + ${IDEA_COUNT} idea candidates from $TRANSCRIPT" >&2

# Re-emit the full reflect.py output on stdout (task 5 routing will parse it).
python3 "$REFLECT_PY" "$TRANSCRIPT" --summary 2>/dev/null

exit 0
