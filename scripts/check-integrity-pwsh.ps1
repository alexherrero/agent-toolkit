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

# ── 1b. Every installed agent .md file non-empty + has frontmatter ─────────
Write-Host '  [integrity] installed agent .md files have valid frontmatter'
foreach ($parent in @('.claude/agents')) {
    $full = Join-Path $Scratch $parent
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
    Get-ChildItem -LiteralPath $full -File -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
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

# ── 3. No stray files under skill managed parents ──────────────────────────
Write-Host '  [integrity] no stray files under skill managed parents'
foreach ($parent in '.claude/skills', '.agent/skills') {
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
            Write-Error "FAIL: $parent/$($_.Name) is a stray file (skill managed parents contain only <name>/SKILL.md subdirs)"
            $fail = $true
        }
    }
}

# ── 4. No stray entries under agent managed parents ────────────────────────
Write-Host '  [integrity] no stray entries under agent managed parents'
foreach ($parent in @('.claude/agents')) {
    $full = Join-Path $Scratch $parent
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
    Get-ChildItem -LiteralPath $full -Force | ForEach-Object {
        if ($_.PSIsContainer) {
            Write-Error "FAIL: $parent/$($_.Name)/ is a stray subdir (agent managed parents contain only <name>.md files)"
            $fail = $true
        } elseif ($_.Extension -ne '.md') {
            Write-Error "FAIL: $parent/$($_.Name) is a stray non-.md file"
            $fail = $true
        }
    }
}

# ── 5. Hook managed parent: .claude/hooks/<name>.sh or <name>.ps1 ──────────
Write-Host '  [integrity] .claude/hooks/ scripts are script-extensioned'
$hookFull = Join-Path $Scratch '.claude/hooks'
if (Test-Path -LiteralPath $hookFull -PathType Container) {
    Get-ChildItem -LiteralPath $hookFull -Force | ForEach-Object {
        if ($_.PSIsContainer) {
            Write-Error "FAIL: .claude/hooks/$($_.Name)/ is a stray subdir (hook parent contains only <name>.sh / <name>.ps1 files)"
            $fail = $true
        } elseif ($_.Extension -notin '.sh', '.ps1') {
            Write-Error "FAIL: .claude/hooks/$($_.Name) is a stray non-.sh/.ps1 file"
            $fail = $true
        }
    }
}

# ── 6. .claude/settings.json (if present) parses as JSON with valid hook shape ─
$settings = Join-Path $Scratch '.claude/settings.json'
if (Test-Path -LiteralPath $settings) {
    Write-Host '  [integrity] .claude/settings.json parses + hooks shape valid'
    try {
        $obj = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
        if ($obj.hooks) {
            $obj.hooks.PSObject.Properties | ForEach-Object {
                if ($_.Value -isnot [System.Collections.IList]) {
                    Write-Error "FAIL: hooks.$($_.Name) is not an array"
                    $fail = $true
                }
            }
        }
    } catch {
        Write-Error "FAIL: .claude/settings.json invalid JSON: $_"
        $fail = $true
    }
}

if ($fail) {
    Write-Error 'check-integrity-pwsh: one or more integrity assertions failed'
    exit 1
}

Write-Host 'check-integrity-pwsh: OK'
