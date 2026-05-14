# kill-switch — operator emergency halt for long-running agent sessions.
# Mirrors kill-switch.sh for Windows / pwsh hosts.
#
# Fires on Claude Code's PreToolUse event (matcher .*). If .harness/STOP
# exists in the project root, blocks the tool call with exit code 2 and
# surfaces a halt message via stderr.
#
# Operator usage:
#   New-Item .harness/STOP -ItemType File   # halt
#   Remove-Item .harness/STOP               # resume
#
# See hook.md in this directory for full documentation.

$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath '.harness/STOP' -PathType Leaf) {
    [Console]::Error.WriteLine('kill-switch: .harness/STOP present — halting tool call. Remove the file (Remove-Item .harness/STOP) to resume.')
    exit 2
}

exit 0
