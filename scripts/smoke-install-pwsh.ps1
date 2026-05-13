# smoke-install-pwsh.ps1 — install agent-toolkit into a scratch dir and assert
# the expected tree under pwsh.
#
# Used by tests-windows.yml. Invoked from repo root:
#   pwsh -NoProfile -File scripts/smoke-install-pwsh.ps1

$ErrorActionPreference = 'Stop'

$ToolkitRoot = Split-Path -Parent $PSScriptRoot
$ToolkitRoot = (Resolve-Path -LiteralPath $ToolkitRoot).ProviderPath

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("toolkit-smoke-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

try {
    git -C $scratch init -q -b main | Out-Null

    Write-Host "==> fresh install into $scratch"
    pwsh -NoProfile -File (Join-Path $ToolkitRoot 'install.ps1') $scratch | Out-File (Join-Path $scratch '.install.log')
    if ($LASTEXITCODE -ne 0) { throw "install.ps1 returned non-zero ($LASTEXITCODE)" }

    # ── expected files ─────────────────────────────────────────────────────
    $expected = @(
        '.claude/skills/example-skill/SKILL.md',
        '.agent/skills/example-skill/SKILL.md',
        '.agents/skills/example-skill/SKILL.md',
        '.claude/skills/pii-scrubber/SKILL.md',
        '.agent/skills/pii-scrubber/SKILL.md',
        '.agents/skills/pii-scrubber/SKILL.md',
        # Standalone agent: _fixture-test-agent (temporary fixture for plan #3
        # task 1; replaced by evaluator in task 2). claude-code + gemini-cli
        # are single-file; antigravity wraps as a skill.
        '.claude/agents/_fixture-test-agent.md',
        '.agent/skills/_fixture-test-agent/SKILL.md',
        '.gemini/agents/_fixture-test-agent.md',
        '.git/hooks/pre-push'
    )
    $fail = $false
    foreach ($p in $expected) {
        $full = Join-Path $scratch $p
        if (-not (Test-Path -LiteralPath $full)) {
            Write-Error "MISSING: $p"
            $fail = $true
        }
    }

    # ── installer-boundary: leak check ─────────────────────────────────────
    $leaks = @(
        'scripts/smoke-install-bash.sh',
        'scripts/check-integrity-bash.sh',
        'scripts/check-syntax.sh',
        'scripts/check-lib-parity.sh',
        'scripts/check-no-pii.sh',
        'scripts/manifest-info.py',
        'scripts/validate-manifests.py',
        'lib/install/bash/primitives.sh',
        'lib/install/pwsh/primitives.ps1',
        '.github/workflows/tests-linux.yml',
        'CONTRIBUTING.md',
        'CHANGELOG.md',
        '.gitleaks.toml'
    )
    foreach ($p in $leaks) {
        $full = Join-Path $scratch $p
        if (Test-Path -LiteralPath $full) {
            Write-Error "LEAK: $p should not be in scratch install (installer boundary)"
            $fail = $true
        }
    }

    if ($fail) { throw 'expected-files or leak check failed' }

    # ── idempotent re-run ──────────────────────────────────────────────────
    Write-Host '==> idempotent re-run'
    pwsh -NoProfile -File (Join-Path $ToolkitRoot 'install.ps1') $scratch | Out-File (Join-Path $scratch '.rerun.log')
    $rerun = Get-Content (Join-Path $scratch '.rerun.log') -Raw
    if ($rerun -match 'created .claude/skills/(example-skill|pii-scrubber)') {
        throw 're-run recreated a skill (should be kept)'
    }
    if ($rerun -match 'created .claude/agents/_fixture-test-agent') {
        throw 're-run recreated the fixture agent (should be kept)'
    }

    # ── --update ───────────────────────────────────────────────────────────
    Write-Host '==> --update wipe + recreate'
    pwsh -NoProfile -File (Join-Path $ToolkitRoot 'install.ps1') -Update $scratch | Out-File (Join-Path $scratch '.update.log')
    $update = Get-Content (Join-Path $scratch '.update.log') -Raw
    if ($update -notmatch 'removed .claude/skills/') {
        throw '-Update did not run sync wipe'
    }
    foreach ($p in $expected) {
        if (-not (Test-Path -LiteralPath (Join-Path $scratch $p))) {
            throw "-Update did not recreate $p"
        }
    }

    # ── -NoPrePushHook ─────────────────────────────────────────────────────
    Write-Host '==> -NoPrePushHook'
    $nohook = Join-Path ([System.IO.Path]::GetTempPath()) ("toolkit-nohook-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $nohook -Force | Out-Null
    try {
        git -C $nohook init -q -b main | Out-Null
        pwsh -NoProfile -File (Join-Path $ToolkitRoot 'install.ps1') -NoPrePushHook $nohook | Out-File (Join-Path $nohook '.install.log')
        if (Test-Path -LiteralPath (Join-Path $nohook '.git/hooks/pre-push')) {
            throw '-NoPrePushHook installed the hook anyway'
        }
    } finally {
        Remove-Item -LiteralPath $nohook -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── post-install integrity ─────────────────────────────────────────────
    Write-Host '==> post-install integrity'
    pwsh -NoProfile -File (Join-Path $ToolkitRoot 'scripts/check-integrity-pwsh.ps1') $scratch
    if ($LASTEXITCODE -ne 0) { throw 'check-integrity-pwsh failed' }

    Write-Host '==> smoke-install-pwsh: OK'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
