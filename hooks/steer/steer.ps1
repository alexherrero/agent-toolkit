# steer — inject mid-run guidance from .harness/STEER.md.
# Mirrors steer.sh for Windows / pwsh hosts.
#
# Fires on Claude Code's PreToolUse event (matcher .*). If .harness/STEER.md
# exists in the project root, prints its contents to stdout (Claude Code
# injects into agent context) and renames it to STEER.consumed-<ts>.md.
#
# Operator usage:
#   "Actually, do it this way..." | Out-File .harness/STEER.md
#
# See hook.md in this directory for full documentation.

$ErrorActionPreference = 'Stop'

$steerFile = '.harness/STEER.md'

if (Test-Path -LiteralPath $steerFile -PathType Leaf) {
    # Emit contents to stdout — Claude Code captures and injects.
    Get-Content -LiteralPath $steerFile -Raw

    # Rename for audit trail (UTC timestamp).
    $ts = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    Move-Item -LiteralPath $steerFile -Destination ".harness/STEER.consumed-$ts.md"
}

exit 0
