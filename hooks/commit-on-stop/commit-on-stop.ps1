# commit-on-stop — safety-branch commit at session end (Windows / pwsh).
# Mirrors commit-on-stop.sh.
#
# See hook.md in this directory for full documentation.

$ErrorActionPreference = 'Stop'

# Skip if git unavailable.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    exit 0
}

# Skip if not in a git work tree.
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    exit 0
}

# Skip if working tree clean — nothing to save.
$porcelain = git status --porcelain
if (-not $porcelain) {
    exit 0
}

$ts = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$origBranch = git symbolic-ref --short HEAD 2>$null
if (-not $origBranch) {
    $origBranch = git rev-parse --short HEAD
}
$safetyBranch = "auto-save/$ts"
$msg = "auto-save: stop at $ts on branch $origBranch"

[Console]::Error.WriteLine("commit-on-stop: saving dirty tree on '$origBranch' -> $safetyBranch")

# Stash everything; create safety branch; switch; restore changes; commit; switch back.
git stash push --include-untracked --quiet -m "commit-on-stop-$ts" | Out-Null
git branch $safetyBranch | Out-Null
git checkout --quiet $safetyBranch | Out-Null
git stash pop --quiet | Out-Null
git add -A | Out-Null
git -c commit.gpgsign=false `
    -c user.email='commit-on-stop@agent-toolkit.local' `
    -c user.name='commit-on-stop hook' `
    commit --quiet -m $msg | Out-Null
git checkout --quiet $origBranch | Out-Null

[Console]::Error.WriteLine("commit-on-stop: saved -> $safetyBranch. Recover: git checkout $safetyBranch")
exit 0
