# check-integrity-pwsh.ps1 — post-install integrity check on a scratch dir.
#
# Verifies the installed tree is usable: every installed SKILL.md is non-empty
# and has frontmatter; the pre-push hook (if present) parses; no stray files
# under managed parents.
#
# Usage: pwsh -NoProfile -File scripts/check-integrity-pwsh.ps1 <SCRATCH_DIR>

param([Parameter(Mandatory=$true)][string]$Scratch)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Scratch -PathType Container)) {
    Write-Error "scratch dir $Scratch does not exist"
    exit 1
}

$fail = $false

# ── 1. Every installed SKILL.md non-empty + has frontmatter ────────────────
Write-Host '  [integrity] installed SKILL.md files have valid frontmatter'
Get-ChildItem -LiteralPath $Scratch -Recurse -File -Filter SKILL.md -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'skills' } |
    ForEach-Object {
        if ($_.Length -eq 0) {
            Write-Error "FAIL: $($_.FullName) is empty"
            $fail = $true
            return
        }
        $firstLine = (Get-Content -LiteralPath $_.FullName -TotalCount 1)
        if ($firstLine -notmatch '^---\s*$') {
            Write-Error "FAIL: $($_.FullName) has no opening --- frontmatter delimiter"
            $fail = $true
        }
    }

# ── 2. Pre-push hook integrity ─────────────────────────────────────────────
$hook = Join-Path $Scratch '.git/hooks/pre-push'
if (Test-Path -LiteralPath $hook) {
    Write-Host '  [integrity] .git/hooks/pre-push parses'
    $firstLine = Get-Content -LiteralPath $hook -TotalCount 1
    if ($firstLine -notmatch '^#!.*bash') {
        Write-Error 'FAIL: pre-push hook shebang is not bash'
        $fail = $true
    }
    # Optional: bash -n via a separate process. On Windows the bash may not be
    # available; skip the syntax check in that case.
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        $output = bash -n $hook 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "FAIL: pre-push hook bash -n parse failed: $output"
            $fail = $true
        }
    }
}

# ── 3. No stray files under managed parents ────────────────────────────────
Write-Host '  [integrity] no stray files under managed parents'
foreach ($parent in '.claude/skills', '.agent/skills', '.agents/skills') {
    $full = Join-Path $Scratch $parent
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
    Get-ChildItem -LiteralPath $full -Force | ForEach-Object {
        if ($_.PSIsContainer) {
            $skillMd = Join-Path $_.FullName 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillMd)) {
                Write-Error "FAIL: $parent/$($_.Name)/ has no SKILL.md"
                $fail = $true
            }
        } else {
            Write-Error "FAIL: $parent/$($_.Name) is a stray file (managed parents contain only <name>/SKILL.md subdirs)"
            $fail = $true
        }
    }
}

if ($fail) {
    Write-Error 'check-integrity-pwsh: one or more integrity assertions failed'
    exit 1
}

Write-Host 'check-integrity-pwsh: OK'
