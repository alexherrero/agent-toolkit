#!/usr/bin/env bash
# steer — inject mid-run guidance from .harness/STEER.md.
#
# Fires on Claude Code's PreToolUse event (matcher .*). If .harness/STEER.md
# exists in the project root, prints its contents to stdout (which Claude Code
# injects into the agent's context for the upcoming tool call) and renames
# the file to .harness/STEER.consumed-<iso-timestamp>.md for audit trail.
#
# Operator usage:
#   echo "Actually, do it this way..." > .harness/STEER.md
#
# See hook.md in this directory for full documentation.

set -euo pipefail

STEER_FILE=".harness/STEER.md"

if [[ -f "$STEER_FILE" ]]; then
    # Emit contents to stdout — Claude Code captures and injects.
    cat "$STEER_FILE"

    # Rename for audit trail (UTC timestamp).
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$STEER_FILE" ".harness/STEER.consumed-${ts}.md"
fi

exit 0
