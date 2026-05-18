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
        # Bundle: example-bundle -> example-skill across 2 hosts (claude-code + antigravity).
        # gemini-cli host removed in v0.9.0 (ROADMAP #15).
        '.claude/skills/example-skill/SKILL.md',
        '.agent/skills/example-skill/SKILL.md',
        '.claude/skills/pii-scrubber/SKILL.md',
        '.agent/skills/pii-scrubber/SKILL.md',
        # Standalone skill: design (scaffold only in v0.7.0+; bodies in tasks 2-4 of plan #6).
        '.claude/skills/design/SKILL.md',
        '.claude/skills/design/templates/design-doc.md',
        '.agent/skills/design/SKILL.md',
        '.agent/skills/design/templates/design-doc.md',
        # Standalone skill: memory (plan #7a part 1 task 1 ships scaffold;
        # task 2 of part 1 ships /memory save body + scripts/save.py;
        # task 3 of part 1 ships /memory evolve body + scripts/evolve.py;
        # task 4 of part 1 ships embed.py + vec_index.py).
        '.claude/skills/memory/SKILL.md',
        '.claude/skills/memory/scripts/save.py',
        '.claude/skills/memory/scripts/evolve.py',
        '.claude/skills/memory/scripts/embed.py',
        '.claude/skills/memory/scripts/vec_index.py',
        '.agent/skills/memory/SKILL.md',
        '.agent/skills/memory/scripts/save.py',
        '.agent/skills/memory/scripts/evolve.py',
        '.agent/skills/memory/scripts/embed.py',
        '.agent/skills/memory/scripts/vec_index.py',
        # Standalone agent: evaluator. claude-code is single-file;
        # antigravity wraps the agent as a skill. (gemini-cli destination
        # .gemini/agents/evaluator.md removed in v0.9.0.)
        '.claude/agents/evaluator.md',
        '.agent/skills/evaluator/SKILL.md',
        # Standalone hooks (claude-code only, v0.7.0).
        '.claude/hooks/kill-switch.ps1',
        '.claude/hooks/steer.ps1',
        '.claude/hooks/commit-on-stop.ps1',
        '.claude/settings.json',
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

    # ── negative-existence assertions (v0.9.0+ — gemini-cli removed) ───────────
    # These paths MUST NOT exist after install. Catches regressions if the
    # gemini-cli dispatch arms ever come back.
    $notExpected = @('.agents', '.gemini')
    foreach ($p in $notExpected) {
        $full = Join-Path $scratch $p
        if (Test-Path -LiteralPath $full) {
            Write-Error "UNEXPECTED (v0.9.0+ removed gemini-cli): $p exists at $full"
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
    if ($rerun -match 'created .claude/agents/evaluator') {
        throw 're-run recreated the evaluator agent (should be kept)'
    }
    if ($rerun -match 'created .claude/hooks/(kill-switch|steer|commit-on-stop)') {
        throw 're-run recreated a hook script (should be kept)'
    }
    if ($rerun -match 'merged  .claude/settings.json') {
        throw 're-run re-merged settings.json (should report kept)'
    }
    if ($rerun -notmatch 'kept    .claude/settings.json \(fragment entries already present\)') {
        throw 're-run did not emit kept message for .claude/settings.json'
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

    # ── -NoLegacyCleanup: suppresses the v0.9.0 legacy-cleanup prompt ──────
    Write-Host '==> -NoLegacyCleanup (v0.9.0)'
    $legacy = Join-Path ([System.IO.Path]::GetTempPath()) ("toolkit-legacy-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $legacy -Force | Out-Null
    try {
        git -C $legacy init -q -b main | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $legacy '.agents/skills/design') -Force | Out-Null
        'fake legacy skill' | Out-File -FilePath (Join-Path $legacy '.agents/skills/design/SKILL.md')
        pwsh -NoProfile -File (Join-Path $ToolkitRoot 'install.ps1') -NoLegacyCleanup $legacy | Out-File (Join-Path $legacy '.install.log')
        $log = Get-Content (Join-Path $legacy '.install.log') -Raw
        if ($log -match 'legacy gemini-cli cleanup') {
            throw '-NoLegacyCleanup did not suppress the cleanup prompt'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $legacy '.agents/skills/design/SKILL.md'))) {
            throw '-NoLegacyCleanup deleted/moved legacy .agents/skills/design/ (should leave untouched)'
        }
    } finally {
        Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── /memory save end-to-end test (plan #7a part 1 task 2) ──────────────
    Write-Host '==> /memory save end-to-end test (plan #7a part 1 task 2)'
    $msave = Join-Path ([System.IO.Path]::GetTempPath()) ("toolkit-msave-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $msave -Force | Out-Null
    try {
        $savePy = Join-Path $scratch '.claude/skills/memory/scripts/save.py'
        if (-not (Test-Path -LiteralPath $savePy)) {
            throw "save.py not installed at $savePy"
        }
        # Positive save
        $expected = Join-Path $msave 'personal-private/preferences/smoke-test-positive.md'
        $saveOut = 'Test entry body.' | python3 $savePy 'preferences' 'smoke-test-positive' '--vault-path' $msave '--tags' 'smoke,test' 2>$null
        $saveOut = ($saveOut -join '').Trim()
        if ($saveOut -ne $expected) {
            throw "save.py CLI returned '$saveOut', expected '$expected'"
        }
        if (-not (Test-Path -LiteralPath $expected)) {
            throw "save.py did not create $expected"
        }
        $content = Get-Content -LiteralPath $expected -Raw
        if ($content -notmatch '(?m)^kind: preferences$') { throw "save.py output missing 'kind: preferences' frontmatter" }
        if ($content -notmatch '(?m)^always_load: false$') { throw "save.py output missing 'always_load: false' frontmatter" }
        # --always-load routing
        'Always-load body.' | python3 $savePy 'preferences' 'smoke-test-al' '--vault-path' $msave '--always-load' | Out-Null
        $alPath = Join-Path $msave 'personal-private/_always-load/smoke-test-al.md'
        if (-not (Test-Path -LiteralPath $alPath)) {
            throw "--always-load did not route to _always-load/ (expected $alPath)"
        }
        $alContent = Get-Content -LiteralPath $alPath -Raw
        if ($alContent -notmatch '(?m)^always_load: true$') {
            throw "--always-load entry missing 'always_load: true' frontmatter"
        }
        # Collision negative
        'x' | python3 $savePy 'preferences' 'smoke-test-positive' '--vault-path' $msave 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            throw 'save.py allowed overwriting an existing entry (collision check broken)'
        }
        # Invalid slug negative
        'x' | python3 $savePy 'preferences' 'Bad_Slug' '--vault-path' $msave 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            throw 'save.py allowed non-kebab-case slug (validator broken)'
        }
    } finally {
        Remove-Item -LiteralPath $msave -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── /memory evolve end-to-end test (plan #7a part 1 task 3) ────────────
    Write-Host '==> /memory evolve end-to-end test (plan #7a part 1 task 3)'
    $mevol = Join-Path ([System.IO.Path]::GetTempPath()) ("toolkit-mevol-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $mevol -Force | Out-Null
    try {
        $savePy = Join-Path $scratch '.claude/skills/memory/scripts/save.py'
        $evolvePy = Join-Path $scratch '.claude/skills/memory/scripts/evolve.py'
        if (-not (Test-Path -LiteralPath $evolvePy)) {
            throw "evolve.py not installed at $evolvePy"
        }
        # Setup
        'Original body for in-place evolve.' | python3 $savePy 'preferences' 'smoke-evolve-ip' '--vault-path' $mevol | Out-Null
        # Test 1: in-place evolve
        $evolOut = 'Evolved body.' | python3 $evolvePy 'personal-private/preferences/smoke-evolve-ip.md' 'test in-place evolve' '--vault-path' $mevol 2>$null
        $evolOut = ($evolOut -join '').Trim()
        $parts = $evolOut -split "`t"
        $newPath = $parts[0]
        $archPath = $parts[1]
        if (-not (Test-Path -LiteralPath $newPath)) { throw "evolve.py did not create new entry at $newPath" }
        if (-not (Test-Path -LiteralPath $archPath)) { throw "evolve.py did not create archive at $archPath" }
        $newContent = Get-Content -LiteralPath $newPath -Raw
        if ($newContent -notmatch '(?m)^supersedes: personal-private/_archive/') {
            throw "active entry missing 'supersedes:' frontmatter pointing at archive"
        }
        if ($newContent -notmatch '(?m)^status: active$') {
            throw "active entry missing 'status: active'"
        }
        $archContent = Get-Content -LiteralPath $archPath -Raw
        if ($archContent -notmatch '(?m)^status: superseded$') {
            throw "archive missing 'status: superseded'"
        }
        if ($archContent -notmatch '(?m)^superseded_by: personal-private/preferences/smoke-evolve-ip') {
            throw "archive missing 'superseded_by:' cross-link"
        }
        if ($archContent -notmatch '(?m)^superseded_reason:') {
            throw "archive missing 'superseded_reason:'"
        }
        # Test 2: rename evolve
        'Original body for rename evolve.' | python3 $savePy 'preferences' 'smoke-evolve-rename' '--vault-path' $mevol | Out-Null
        'Renamed body.' | python3 $evolvePy 'personal-private/preferences/smoke-evolve-rename.md' 'test rename' '--new-slug' 'smoke-evolve-renamed' '--vault-path' $mevol | Out-Null
        if (Test-Path -LiteralPath (Join-Path $mevol 'personal-private/preferences/smoke-evolve-rename.md')) {
            throw "rename evolve left old entry at original path (should be unlinked)"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $mevol 'personal-private/preferences/smoke-evolve-renamed.md'))) {
            throw "rename evolve did not create new entry at new slug"
        }
        # Test 3: negative — missing entry
        'x' | python3 $evolvePy 'personal-private/preferences/nonexistent.md' 'test' '--vault-path' $mevol 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            throw 'evolve.py allowed missing entry (should error non-zero)'
        }
        # Test 4: negative — already-superseded
        $todayCompact = Get-Date -Format 'yyyyMMdd'
        $supersededPath = "personal-private/_archive/personal-private/preferences/smoke-evolve-ip.md.$todayCompact.md"
        'x' | python3 $evolvePy $supersededPath 'test' '--vault-path' $mevol 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            throw 'evolve.py allowed evolving already-superseded entry (status check broken)'
        }
        # Test 5: negative — empty reason
        'x' | python3 $evolvePy 'personal-private/preferences/smoke-evolve-ip.md' '' '--vault-path' $mevol 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            throw 'evolve.py allowed empty reason (reason check broken)'
        }
    } finally {
        Remove-Item -LiteralPath $mevol -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── embedding queue + vec-index wiring test (plan #7a part 1 task 4) ───
    Write-Host '==> embedding queue + vec-index wiring test (plan #7a part 1 task 4)'
    $mqueue = Join-Path ([System.IO.Path]::GetTempPath()) ("toolkit-mqueue-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $mqueue -Force | Out-Null
    try {
        $savePy = Join-Path $scratch '.claude/skills/memory/scripts/save.py'
        $embedPy = Join-Path $scratch '.claude/skills/memory/scripts/embed.py'
        $vecPy = Join-Path $scratch '.claude/skills/memory/scripts/vec_index.py'
        foreach ($f in @($embedPy, $vecPy)) {
            if (-not (Test-Path -LiteralPath $f)) {
                throw "$f not installed"
            }
        }
        # embed.py stub mode produces deterministic 384-d output
        $embedOut = python3 $embedPy 'smoke test text' '--mode' 'stub' 2>$null
        $embedOut = ($embedOut -join '').Trim()
        $parsed = $embedOut | ConvertFrom-Json
        if ($parsed.Count -ne 384) {
            throw "embed.py stub mode returned $($parsed.Count)-d output, expected 384"
        }
        # Save 3 entries; queue should grow by 3
        for ($i = 1; $i -le 3; $i++) {
            "Body $i for queue test." | python3 $savePy 'preferences' "queue-test-$i" '--vault-path' $mqueue 2>$null | Out-Null
        }
        $queueFile = Join-Path $mqueue '_meta/embedding-queue.jsonl'
        if (-not (Test-Path -LiteralPath $queueFile)) {
            throw 'embedding queue file not created after 3 saves'
        }
        $lines = (Get-Content -LiteralPath $queueFile | Measure-Object -Line).Lines
        if ($lines -ne 3) {
            throw "expected 3 queue entries after 3 saves, got $lines"
        }
        $queueContent = Get-Content -LiteralPath $queueFile -Raw
        if ($queueContent -notmatch '"op": "upsert"') {
            throw "queue entries missing 'op': 'upsert' field"
        }
        # Drain in stub mode — outcome depends on sqlite-vec availability
        $drainOut = python3 $vecPy '--vault-path' $mqueue 'drain' '--mode' 'stub' 2>$null
        $drainOut = ($drainOut -join '').Trim()
        $drainParsed = $drainOut | ConvertFrom-Json
        if ($drainParsed.errors -ne 0) {
            throw "drain reported $($drainParsed.errors) errors; should be 0 even when sqlite-vec absent (graceful-skip). Output: $drainOut"
        }
        if ($drainParsed.processed -eq 3) {
            # Full happy path
            $sizeOut = python3 $vecPy '--vault-path' $mqueue 'size' 2>$null
            $sizeOut = ($sizeOut -join '').Trim()
            $sizeParsed = $sizeOut | ConvertFrom-Json
            if ($sizeParsed.size -ne 3) {
                throw "drain processed 3 but index size is $($sizeParsed.size) (expected 3)"
            }
            if (Test-Path -LiteralPath $queueFile) {
                throw 'queue file still exists after full drain (should be removed when remaining==0)'
            }
            Write-Host '    (sqlite-vec available — verified full happy path)'
        } elseif ($drainParsed.skipped -eq 3) {
            # Graceful-skip path
            if (-not (Test-Path -LiteralPath $queueFile)) {
                throw 'queue file removed despite graceful-skip (should remain pending)'
            }
            Write-Host '    (sqlite-vec unavailable — verified graceful-skip)'
        } else {
            throw "drain produced unexpected outcome (processed=$($drainParsed.processed), skipped=$($drainParsed.skipped), errors=$($drainParsed.errors))"
        }
        # File write never blocked: no API key + no local model → save still succeeds
        Remove-Item -Path Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
        Remove-Item -Path Env:VOYAGE_API_KEY -ErrorAction SilentlyContinue
        Remove-Item -Path Env:MEMORY_USE_API_EMBEDDINGS -ErrorAction SilentlyContinue
        'No-API body.' | python3 $savePy 'preferences' 'no-api-test' '--vault-path' $mqueue 2>$null | Out-Null
        $noApiPath = Join-Path $mqueue 'personal-private/preferences/no-api-test.md'
        if (-not (Test-Path -LiteralPath $noApiPath)) {
            throw 'save failed when no embedding mode available (file write should NEVER be blocked)'
        }
    } finally {
        Remove-Item -LiteralPath $mqueue -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── validate-manifests negative test: gemini-cli rejected with v0.9.0 msg ─
    Write-Host '==> validate-manifests negative test (gemini-cli rejected)'
    $vneg = Join-Path ([System.IO.Path]::GetTempPath()) ("toolkit-vneg-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $vneg 'skills/test-gemini-cli-rejected') -Force | Out-Null
    $vnegManifest = @"
---
name: test-gemini-cli-rejected
description: Negative-test fixture - validate-manifests must reject this manifest because gemini-cli was removed in v0.9.0.
kind: skill
supported_hosts: [claude-code, antigravity, gemini-cli]
version: 0.1.0
install_scope: project
---
"@
    $vnegManifest | Out-File -FilePath (Join-Path $vneg 'skills/test-gemini-cli-rejected/SKILL.md') -Encoding utf8
    try {
        $vnegDriver = @"
import importlib.util
spec = importlib.util.spec_from_file_location('vm', r'$($ToolkitRoot -replace '\\', '/')/scripts/validate-manifests.py')
vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm)
from pathlib import Path
vm.ROOT = Path(r'$($vneg -replace '\\', '/')')
p = Path(r'$($vneg -replace '\\', '/')/skills/test-gemini-cli-rejected/SKILL.md')
fm = vm.parse_frontmatter(p)
vm.require_supported_hosts(p, fm)
print('ERRORS:', len(vm.errors))
for issue in vm.errors:
    print('MSG:', issue)
"@
        $vnegOut = python3 -c $vnegDriver 2>&1 | Out-String
        if ($vnegOut -notmatch "removed host 'gemini-cli'") {
            throw "validator did not emit 'removed host gemini-cli' message. Output:`n$vnegOut"
        }
        if ($vnegOut -notmatch 'v0\.9\.0') {
            throw "validator's error message does not mention v0.9.0 (no actionable next-step). Output:`n$vnegOut"
        }
    } finally {
        Remove-Item -LiteralPath $vneg -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── post-install integrity ─────────────────────────────────────────────
    Write-Host '==> post-install integrity'
    pwsh -NoProfile -File (Join-Path $ToolkitRoot 'scripts/check-integrity-pwsh.ps1') $scratch
    if ($LASTEXITCODE -ne 0) { throw 'check-integrity-pwsh failed' }

    Write-Host '==> smoke-install-pwsh: OK'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
