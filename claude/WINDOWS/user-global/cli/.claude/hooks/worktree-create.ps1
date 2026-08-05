# WorktreeCreate hook.
# stdin:  {"hook_event_name":"WorktreeCreate","name":"<name>"}
# stdout: absolute path of the created worktree, as the last line.
#
# Places worktrees at <repo>/.worktrees/<name> instead of the built-in
# <repo>/.claude/worktrees/<name>. Idempotent: an existing worktree at the
# target path is reported as-is rather than recreated, so it stays correct
# when both the user-level and project-level copies of this hook fire.

$ErrorActionPreference = 'Stop'

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$name = $payload.name
if ([string]::IsNullOrWhiteSpace($name)) {
    throw "WorktreeCreate: hook input had no 'name'."
}

$root = git rev-parse --show-toplevel 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "WorktreeCreate: not inside a git repository ($root)."
}
$target = [System.IO.Path]::GetFullPath((Join-Path $root.Trim() ".worktrees/$name"))

# Already present (re-entry, or the other copy of this hook won the race).
if (Test-Path -LiteralPath $target) {
    Write-Output $target
    exit 0
}

# Replicate worktree.baseRef = "fresh": branch from origin/<default-branch>.
# The built-in creation path honors that setting; once a hook owns creation,
# reproducing it is on us.
$base = $null
$originHead = git symbolic-ref --quiet refs/remotes/origin/HEAD 2>&1
if ($LASTEXITCODE -eq 0 -and $originHead) {
    $base = $originHead.Trim() -replace '^refs/remotes/', ''
}
if (-not $base) {
    foreach ($candidate in @('origin/main', 'origin/master')) {
        git rev-parse --verify --quiet $candidate *> $null
        if ($LASTEXITCODE -eq 0) { $base = $candidate; break }
    }
}
if (-not $base) { $base = 'HEAD' }

git show-ref --verify --quiet "refs/heads/$name"
$branchExists = ($LASTEXITCODE -eq 0)

if ($branchExists) {
    $out = git worktree add $target $name 2>&1
} else {
    $out = git worktree add -b $name $target $base 2>&1
}
if ($LASTEXITCODE -ne 0) {
    throw "WorktreeCreate: git worktree add failed for '$target': $out"
}

Write-Output $target
