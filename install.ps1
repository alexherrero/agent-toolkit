# install.ps1 — agent-toolkit installer.
#
# Installs personal agent customizations (skills, sub-agents, hooks, MCP
# servers, slash commands, etc.) into a target project under host-specific
# paths (.claude/, .agent/, .gemini/). Also installs a pre-push git hook
# that runs check-no-pii.sh against every push.
#
# Usage:
#   pwsh -NoProfile -File install.ps1 [OPTIONS] <target-project-path>
#
# Options:
#   -Bundle <name>           install one bundle (instead of all)
#   -Skill <name>            install one standalone skill (instead of all)
#   -Agent <name>            install one standalone agent (instead of all)
#   -All                     install everything (default)
#   -Update                  true-sync; wipe and recreate managed dirs
#   -NoPrePushHook           skip pre-push hook installation
#   -Help                    print this help and exit

[CmdletBinding()]
param(
    [string]$Bundle,
    [string]$Skill,
    [string]$Agent,
    [switch]$All,
    [switch]$Update,
    [switch]$NoPrePushHook,
    [switch]$Help,
    [Parameter(Position=0)]
    [string]$Target
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Get-Content $PSCommandPath | Where-Object { $_ -match '^#' -or $_ -eq '' } | ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

# ── argument validation ───────────────────────────────────────────────────
if (-not $Target) {
    Write-Error "<target-project-path> is required. Run with -Help for usage."
    exit 2
}
if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    Write-Error "target directory does not exist: $Target"
    exit 1
}
$Target = (Resolve-Path -LiteralPath $Target).ProviderPath

# Selection mode: default to All unless -Bundle, -Skill, or -Agent given
$ModeAll = $true
if ($Bundle -or $Skill -or $Agent) { $ModeAll = $false }
if ($All) { $ModeAll = $true; $Bundle = ''; $Skill = ''; $Agent = '' }

# ── locate toolkit root ───────────────────────────────────────────────────
$ToolkitRoot = Split-Path -Parent $PSCommandPath
$ToolkitRoot = (Resolve-Path -LiteralPath $ToolkitRoot).ProviderPath

# ── source shared install plumbing ────────────────────────────────────────
$BoundaryRoots = @(
    (Join-Path $ToolkitRoot 'skills'),
    (Join-Path $ToolkitRoot 'commands'),
    (Join-Path $ToolkitRoot 'agents'),
    (Join-Path $ToolkitRoot 'hooks'),
    (Join-Path $ToolkitRoot 'mcp-servers'),
    (Join-Path $ToolkitRoot 'bundles'),
    (Join-Path $ToolkitRoot 'status-line'),
    (Join-Path $ToolkitRoot 'output-styles'),
    (Join-Path $ToolkitRoot 'workflows'),
    (Join-Path $ToolkitRoot 'rules'),
    (Join-Path $ToolkitRoot 'snippets'),
    (Join-Path $ToolkitRoot 'settings-fragments'),
    (Join-Path $ToolkitRoot 'templates')
)

. (Join-Path $ToolkitRoot 'lib/install/pwsh/primitives.ps1')

# ── operate from inside target dir ────────────────────────────────────────
Set-Location $Target
Write-Host "==> agent-toolkit install: $Target"

# ── -Update sync ──────────────────────────────────────────────────────────
# See install.sh note on .claude/agents + .gemini/agents — these parents are
# also written to by the sibling agentic-harness installer; the LATER-run
# installer's -Update wipes the parent before recreating from its own source.
$ManagedParents = @(
    '.claude/skills',
    '.agent/skills',
    '.agents/skills',
    '.claude/agents',
    '.gemini/agents'
)
$EmptyParentCandidates = @('.agents')

if ($Update) {
    Write-Host '==> sync mode: wiping toolkit-managed dirs before recreate from source'
    Sync-ManagedParents $ManagedParents $EmptyParentCandidates
}

# ── helpers ───────────────────────────────────────────────────────────────
function Get-Field([string]$file, [string]$field) {
    $result = python3 (Join-Path $ToolkitRoot 'scripts/manifest-info.py') $file $field 2>$null
    return ($result -join '').Trim()
}

function Install-Skill([string]$srcDir, [string]$name, [string]$hosts) {
    # Note: NOT named $host — that's a read-only PowerShell built-in (the host
    # environment). Use $hostName instead for the loop variable.
    foreach ($hostName in ($hosts -split ',')) {
        $hostName = $hostName.Trim()
        if (-not $hostName) { continue }
        switch ($hostName) {
            'claude-code' {
                New-Item -ItemType Directory -Path '.claude/skills' -Force | Out-Null
                Copy-ManagedDir $srcDir (Join-Path '.claude/skills' $name)
            }
            'antigravity' {
                New-Item -ItemType Directory -Path '.agent/skills' -Force | Out-Null
                Copy-ManagedDir $srcDir (Join-Path '.agent/skills' $name)
            }
            'gemini-cli' {
                New-Item -ItemType Directory -Path '.agents/skills' -Force | Out-Null
                Copy-ManagedDir $srcDir (Join-Path '.agents/skills' $name)
            }
            default {
                Write-Warning "unknown host '$hostName' for skill '$name' - skipped"
            }
        }
    }
}

function Install-Agent([string]$srcFile, [string]$name, [string]$hosts) {
    # Agents are file-level for claude-code + gemini-cli; antigravity wraps
    # them as skills (no first-class sub-agent surface in Antigravity).
    # $hostName not $host — see note above.
    foreach ($hostName in ($hosts -split ',')) {
        $hostName = $hostName.Trim()
        if (-not $hostName) { continue }
        switch ($hostName) {
            'claude-code' {
                New-Item -ItemType Directory -Path '.claude/agents' -Force | Out-Null
                Copy-ManagedFile $srcFile (Join-Path '.claude/agents' "$name.md")
            }
            'antigravity' {
                $wrap = Join-Path '.agent/skills' $name
                New-Item -ItemType Directory -Path $wrap -Force | Out-Null
                Copy-ManagedFile $srcFile (Join-Path $wrap 'SKILL.md')
            }
            'gemini-cli' {
                New-Item -ItemType Directory -Path '.gemini/agents' -Force | Out-Null
                Copy-ManagedFile $srcFile (Join-Path '.gemini/agents' "$name.md")
            }
            default {
                Write-Warning "unknown host '$hostName' for agent '$name' - skipped"
            }
        }
    }
}

function Install-PrePushHook {
    if ($NoPrePushHook) {
        Write-Host '  skipping pre-push hook (-NoPrePushHook)'
        return
    }
    if (-not (Test-Path -LiteralPath '.git' -PathType Container)) {
        Write-Warning 'skipping pre-push hook (target is not a git repo)'
        return
    }
    $hookSrc = Join-Path $ToolkitRoot 'templates/hooks/pre-push'
    $hookDst = '.git/hooks/pre-push'
    if (-not (Test-Path -LiteralPath $hookSrc)) {
        Write-Warning "hook template not found at $hookSrc - pre-push hook not installed"
        return
    }
    if (Test-Path -LiteralPath $hookDst) {
        $a = Get-FileHash -LiteralPath $hookSrc -Algorithm SHA256
        $b = Get-FileHash -LiteralPath $hookDst -Algorithm SHA256
        if ($a.Hash -eq $b.Hash) {
            Write-Host "    kept    $hookDst (already managed by agent-toolkit)"
            return
        }
        $bak = "$hookDst.agent-toolkit-bak.$([int][double]::Parse((Get-Date -UFormat %s)))"
        Copy-Item -LiteralPath $hookDst -Destination $bak
        Write-Host "    backed up existing $hookDst -> $bak"
    }
    Copy-Item -LiteralPath $hookSrc -Destination $hookDst
    Write-Host "    installed $hookDst"
}

function Install-Bundles {
    Get-ChildItem -LiteralPath (Join-Path $ToolkitRoot 'bundles') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $bundleDir = $_.FullName
            $bundleName = $_.Name
            $bundleMd = Join-Path $bundleDir 'bundle.md'
            if (-not (Test-Path -LiteralPath $bundleMd)) { return }
            if (-not $ModeAll -and $Bundle -and $Bundle -ne $bundleName) { return }
            Write-Host "==> installing bundle: $bundleName"
            $hosts = Get-Field $bundleMd 'supported_hosts'
            if (-not $hosts) {
                Write-Warning "bundle '$bundleName' has no supported_hosts - skipped"
                return
            }
            $skillsDir = Join-Path $bundleDir 'skills'
            if (Test-Path -LiteralPath $skillsDir -PathType Container) {
                Get-ChildItem -LiteralPath $skillsDir -Directory | ForEach-Object {
                    Install-Skill $_.FullName $_.Name $hosts
                }
            }
            $agentsDir = Join-Path $bundleDir 'agents'
            if (Test-Path -LiteralPath $agentsDir -PathType Container) {
                Get-ChildItem -LiteralPath $agentsDir -Filter '*.md' -File | ForEach-Object {
                    Install-Agent $_.FullName $_.BaseName $hosts
                }
            }
            foreach ($other in 'commands','hooks','mcp-servers','status-line','output-styles','workflows','rules','snippets','settings-fragments') {
                $od = Join-Path $bundleDir $other
                if ((Test-Path -LiteralPath $od -PathType Container) -and (Get-ChildItem -LiteralPath $od -Force -ErrorAction SilentlyContinue)) {
                    Write-Warning "kind '$other' is not yet supported by this installer - skipped"
                }
            }
        }
}

function Install-StandaloneSkills {
    Get-ChildItem -LiteralPath (Join-Path $ToolkitRoot 'skills') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $skillDir = $_.FullName
            $skillName = $_.Name
            $skillMd = Join-Path $skillDir 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillMd)) { return }
            if (-not $ModeAll -and $Skill -and $Skill -ne $skillName) { return }
            $kind = Get-Field $skillMd 'kind'
            if ($kind -ne 'skill') {
                Write-Warning "$skillMd has kind '$kind' (expected 'skill') - skipped"
                return
            }
            $hosts = Get-Field $skillMd 'supported_hosts'
            if (-not $hosts) {
                Write-Warning "skill '$skillName' has no supported_hosts - skipped"
                return
            }
            Write-Host "==> installing skill: $skillName"
            Install-Skill $skillDir $skillName $hosts
        }
}

function Install-StandaloneAgents {
    $agentsRoot = Join-Path $ToolkitRoot 'agents'
    if (-not (Test-Path -LiteralPath $agentsRoot -PathType Container)) { return }
    Get-ChildItem -LiteralPath $agentsRoot -Filter '*.md' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $agentMd = $_.FullName
            $agentName = $_.BaseName
            if (-not $ModeAll -and $Agent -and $Agent -ne $agentName) { return }
            $kind = Get-Field $agentMd 'kind'
            if ($kind -ne 'agent') {
                Write-Warning "$agentMd has kind '$kind' (expected 'agent') - skipped"
                return
            }
            $hosts = Get-Field $agentMd 'supported_hosts'
            if (-not $hosts) {
                Write-Warning "agent '$agentName' has no supported_hosts - skipped"
                return
            }
            Write-Host "==> installing agent: $agentName"
            Install-Agent $agentMd $agentName $hosts
        }
}

# ── run ───────────────────────────────────────────────────────────────────
if ($ModeAll -or $Bundle) {
    Install-Bundles
}
if ($ModeAll -or $Skill) {
    Install-StandaloneSkills
}
if ($ModeAll -or $Agent) {
    Install-StandaloneAgents
}

Write-Host '==> pre-push hook'
Install-PrePushHook

Write-Host ''
Write-Host 'agent-toolkit install: complete.'
