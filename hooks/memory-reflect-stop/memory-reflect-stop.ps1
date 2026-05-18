# memory-reflect-stop — mine the just-ended session's transcript on Stop (Windows / pwsh).
# Mirrors memory-reflect-stop.sh.
#
# See hook.md in this directory for full documentation.

# NOTE: no `$ErrorActionPreference = 'Stop'` — graceful-skip pattern; hook
# must never block session end.

$RecallPy = $null  # Unused; kept for symmetry with recall hooks.
$ReflectPy = ".claude/skills/memory/scripts/reflect.py"
if (-not (Test-Path $ReflectPy)) {
    exit 0
}

if (-not (Get-Command python3 -ErrorAction SilentlyContinue) -and
    -not (Get-Command python -ErrorAction SilentlyContinue)) {
    exit 0
}

$Py = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }

# Read stdin (Stop event JSON payload). PowerShell forwards stdin via $Input.
$Payload = ($Input | Out-String).Trim()
if (-not $Payload) {
    [Console]::Error.WriteLine("[memory-reflect-stop] no stdin payload (skipping)")
    exit 0
}

# Parse session_id + cwd via embedded Python (consistent with the bash side).
$ParseDriver = @"
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
sid = d.get('session_id') or ''
cwd = d.get('cwd') or ''
if sid:
    print(f'{sid}\t{cwd}')
"@
$Parsed = ($Payload | & $Py -c $ParseDriver 2>$null).Trim()
if (-not $Parsed) {
    [Console]::Error.WriteLine("[memory-reflect-stop] no session_id on stdin (skipping)")
    exit 0
}

$Parts = $Parsed -split "`t"
$SessionId = $Parts[0]
$Cwd = if ($Parts.Length -gt 1 -and $Parts[1]) { $Parts[1] } else { (Get-Location).Path }

# Compute transcript path: ~/.claude/projects/<cwd-slug>/<session_id>.jsonl
# CWD slug: replace path separators with '-' + add leading '-'.
$CwdSlug = "-" + ($Cwd -replace '[\\/]', '-')
$Transcript = Join-Path $HOME ".claude/projects/$CwdSlug/$SessionId.jsonl"

if (-not (Test-Path $Transcript)) {
    [Console]::Error.WriteLine("[memory-reflect-stop] transcript not found: $Transcript (skipping)")
    exit 0
}

# Invoke reflect.py and capture summary line.
$SummaryLine = (& $Py $ReflectPy $Transcript "--summary" 2>$null | Select-Object -First 1)
if (-not $SummaryLine) {
    [Console]::Error.WriteLine("[memory-reflect-stop] reflect.py returned no output for $Transcript (skipping)")
    exit 0
}

# Extract counts.
$CountDriver = @"
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('memory_candidate_count', 0))
    print(d.get('idea_candidate_count', 0))
except Exception:
    print(0)
    print(0)
"@
$Counts = ($SummaryLine | & $Py -c $CountDriver 2>$null) -split "`n"
$MemCount = if ($Counts.Length -ge 1) { $Counts[0] } else { '0' }
$IdeaCount = if ($Counts.Length -ge 2) { $Counts[1] } else { '0' }

[Console]::Error.WriteLine("[memory-reflect-stop] Mined $MemCount memory candidates + $IdeaCount idea candidates from $Transcript")

# Re-emit full output on stdout for task-5 routing.
& $Py $ReflectPy $Transcript "--summary" 2>$null
exit 0
