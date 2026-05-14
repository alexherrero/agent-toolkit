#!/usr/bin/env bash
# kill-switch — operator emergency halt for long-running agent sessions.
#
# Fires on Claude Code's PreToolUse event (matcher .*). If .harness/STOP
# exists in the project root, blocks the tool call with exit code 2 and
# surfaces a halt message via stderr (which Claude Code shows to the agent).
#
# Operator usage:
#   touch .harness/STOP   # halt all tool calls
#   rm    .harness/STOP   # resume
#
# See hook.md in this directory for full documentation.

set -euo pipefail

if [[ -f .harness/STOP ]]; then
    echo "kill-switch: .harness/STOP present — halting tool call. Remove the file (rm .harness/STOP) to resume." >&2
    exit 2
fi

exit 0
