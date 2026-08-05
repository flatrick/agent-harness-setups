# WorktreeRemove hook.
# stdin: {"hook_event_name":"WorktreeRemove","worktree_path":"<path>"}
#
# Counterpart to worktree-create.ps1. Succeeds when the path is already gone,
# so the second of two firing copies doesn't fail the event.

$ErrorActionPreference = 'Stop'

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$path = $payload.worktree_path
if ([string]::IsNullOrWhiteSpace($path)) {
    throw "WorktreeRemove: hook input had no 'worktree_path'."
}

if (-not (Test-Path -LiteralPath $path)) {
    git worktree prune *> $null
    exit 0
}

$out = git worktree remove --force $path 2>&1
if ($LASTEXITCODE -ne 0) {
    # Not a registered worktree (or already detached) — fall back to a plain
    # delete so the directory doesn't linger.
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $path) {
        throw "WorktreeRemove: could not remove '$path': $out"
    }
}

git worktree prune *> $null
