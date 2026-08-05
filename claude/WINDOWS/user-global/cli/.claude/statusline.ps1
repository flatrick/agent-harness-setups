$ErrorActionPreference = 'SilentlyContinue'

$stdinRaw = [Console]::In.ReadToEnd()
$json = $null
if ($stdinRaw) {
    try { $json = $stdinRaw | ConvertFrom-Json } catch { $json = $null }
}

$dirRaw = $null
if ($json -and $json.workspace -and $json.workspace.current_dir) { $dirRaw = $json.workspace.current_dir }
elseif ($json -and $json.cwd) { $dirRaw = $json.cwd }
if (-not $dirRaw) { $dirRaw = (Get-Location).Path }

# The JSON payload's cwd/current_dir arrives with forward slashes even on Windows.
# Every downstream consumer (Format-Dir's backslash split, the worktree-root prefix
# comparison, the home-dir substitution) assumes backslash-separated Windows paths,
# so normalize once here rather than at each call site.
if ($dirRaw) {
    $dirRaw = $dirRaw -replace '/', '\'
    if ($dirRaw.Length -gt 3) { $dirRaw = $dirRaw.TrimEnd('\') }
}

$modelName = 'Claude'
if ($json -and $json.model -and $json.model.display_name) { $modelName = $json.model.display_name }

function Format-TokenCount([double]$n) {
    if ($n -ge 1000) { return "{0:N0}K" -f ($n / 1000) }
    return "{0:N0}" -f $n
}

$hasBudget = $false
$budgetText = $null
if ($json -and $json.context_window) {
    $cw = $json.context_window
    $usedPct = $null
    $remainingPct = $null
    if ($null -ne $cw.used_percentage -and $cw.used_percentage -ne '') { $usedPct = [double]$cw.used_percentage }
    if ($null -ne $cw.remaining_percentage -and $cw.remaining_percentage -ne '') { $remainingPct = [double]$cw.remaining_percentage }
    if ($null -ne $usedPct -or $null -ne $remainingPct) {
        $hasBudget = $true
        $tokensPart = ''
        if ($null -ne $cw.total_input_tokens -and $null -ne $cw.context_window_size -and [double]$cw.context_window_size -gt 0) {
            $tokensPart = "$(Format-TokenCount ([double]$cw.total_input_tokens))/$(Format-TokenCount ([double]$cw.context_window_size)) "
        }
        $pctPart = if ($null -ne $remainingPct) { "$([math]::Round($remainingPct))% left" } elseif ($null -ne $usedPct) { "$([math]::Round($usedPct))% used" } else { '' }
        $budgetText = ("$tokensPart$pctPart").Trim()
    }
}

$hasRateLimits = $false
$limitsText = $null
if ($json -and $json.rate_limits) {
    $rl = $json.rate_limits
    $limitParts = @()
    if ($rl.five_hour -and $null -ne $rl.five_hour.used_percentage -and $rl.five_hour.used_percentage -ne '') {
        $limitParts += "5h $([math]::Round([double]$rl.five_hour.used_percentage))%"
    }
    if ($rl.seven_day -and $null -ne $rl.seven_day.used_percentage -and $rl.seven_day.used_percentage -ne '') {
        $limitParts += "7d $([math]::Round([double]$rl.seven_day.used_percentage))%"
    }
    if ($limitParts.Count -gt 0) {
        $hasRateLimits = $true
        $limitsText = ($limitParts -join ' · ')
    }
}

$gitSegment = $false
$branch = $null
$isWorktree = $false
$worktreeSlug = $null
$repoToplevel = $null
try {
    $isRepo = git -C "$dirRaw" --no-optional-locks rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and $isRepo -eq 'true') {
        $gitSegment = $true

        # Branch identity only - no status/porcelain call. The user's git client already
        # covers status detail; this avoids a per-render subprocess against large submodules.
        $branchName = git -C "$dirRaw" --no-optional-locks rev-parse --abbrev-ref HEAD 2>$null
        if (-not $branchName -or $branchName -eq 'HEAD') {
            $shortSha = git -C "$dirRaw" --no-optional-locks rev-parse --short HEAD 2>$null
            $branchName = if ($shortSha) { $shortSha } else { '?' }
        }
        $branch = $branchName

        # Checkout identity: git-dir and git-common-dir differ only inside a linked worktree.
        $repoToplevel = git -C "$dirRaw" --no-optional-locks rev-parse --show-toplevel 2>$null
        if ($repoToplevel) { $repoToplevel = ($repoToplevel -replace '/', '\').TrimEnd('\') }

        function Resolve-GitPath([string]$base, [string]$raw) {
            if (-not $raw) { return $null }
            $candidate = if ([System.IO.Path]::IsPathRooted($raw)) { $raw } else { Join-Path $base $raw }
            $resolved = Resolve-Path -LiteralPath $candidate -ErrorAction SilentlyContinue
            if ($resolved) { return $resolved.Path }
            return $null
        }

        $gitDirRaw = git -C "$dirRaw" --no-optional-locks rev-parse --git-dir 2>$null
        $gitCommonDirRaw = git -C "$dirRaw" --no-optional-locks rev-parse --git-common-dir 2>$null
        $gitDirFull = Resolve-GitPath $dirRaw $gitDirRaw
        $gitCommonDirFull = Resolve-GitPath $dirRaw $gitCommonDirRaw
        if ($gitDirFull -and $gitCommonDirFull -and $gitDirFull -ne $gitCommonDirFull) {
            $isWorktree = $true
            if ($repoToplevel) { $worktreeSlug = Split-Path -Leaf $repoToplevel }
        }
    }
} catch {
    $gitSegment = $false
}

function Format-Dir([string]$path) {
    $homeDir = $env:USERPROFILE
    $normalized = $path
    if ($homeDir) {
        if ($normalized -ieq $homeDir) {
            $normalized = '~'
        } elseif ($normalized.ToLower().StartsWith(($homeDir.ToLower() + '\'))) {
            $normalized = '~' + $normalized.Substring($homeDir.Length)
        }
    }
    # Internal splitting stays on backslash (the normalized form); joins use '/' because
    # this is the final display string, matching the '…/' truncation symbol and the
    # forward-slash form the JSON payload itself uses.
    $parts = $normalized -split '\\' | Where-Object { $_ -ne '' }
    if ($parts.Count -gt 3) {
        $last = $parts[-3..-1]
        return '…/' + ($last -join '/')
    }
    return ($parts -join '/')
}

# Truncates the path *below* a worktree root without ever dropping the worktree
# slug itself - the caller prefixes the slug separately, outside this truncation.
function Format-WorktreeTail([string]$dirRawPath, [string]$toplevel) {
    if (-not $dirRawPath -or -not $toplevel) { return '' }
    if ($dirRawPath.Length -lt $toplevel.Length -or -not $dirRawPath.ToLower().StartsWith($toplevel.ToLower())) { return '' }
    $rel = $dirRawPath.Substring($toplevel.Length).TrimStart('\')
    if (-not $rel) { return '' }
    # Internal splitting stays on backslash; join with '/' for display, same reasoning as Format-Dir.
    $parts = $rel -split '\\' | Where-Object { $_ -ne '' }
    if ($parts.Count -gt 3) {
        return '…/' + ($parts[-3..-1] -join '/')
    }
    return ($parts -join '/')
}

if ($gitSegment -and $isWorktree -and $worktreeSlug -and $repoToplevel) {
    $worktreeTail = Format-WorktreeTail $dirRaw $repoToplevel
    $dirDisplay = if ($worktreeTail) { "wt:$worktreeSlug/$worktreeTail" } else { "wt:$worktreeSlug" }
} elseif ($gitSegment) {
    $dirDisplay = "root: " + (Format-Dir $dirRaw)
} else {
    $dirDisplay = Format-Dir $dirRaw
}

$ESC = [char]27
function AnsiFg([int[]]$c) { "$ESC[38;2;$($c[0]);$($c[1]);$($c[2])m" }
function AnsiBg([int[]]$c) { "$ESC[48;2;$($c[0]);$($c[1]);$($c[2])m" }
$RESET = "$ESC[0m"
$BGRESET = "$ESC[49m"

$crust    = 17,17,27
$red      = 243,139,168
$peach    = 250,179,135
$yellow   = 249,226,175
$green    = 166,227,161
$mauve    = 203,166,247
$teal     = 148,226,213

$TRIANGLE   = [char]0xE0B0
$GITSYM     = [char]0xE0A0
$BUDGETICON = [char]0xF080
$LIMITICON  = [char]0xF0E4

# Budget segment background shifts with remaining context so it reads
# peripherally: comfortable (mauve) -> caution (yellow) -> critical (red).
$budgetBg = $mauve
if ($hasBudget) {
    $remainingForColor = $null
    if ($null -ne $remainingPct) { $remainingForColor = $remainingPct }
    elseif ($null -ne $usedPct) { $remainingForColor = 100 - $usedPct }
    if ($null -ne $remainingForColor) {
        if ($remainingForColor -lt 15) { $budgetBg = $red }
        elseif ($remainingForColor -lt 30) { $budgetBg = $yellow }
        else { $budgetBg = $mauve }
    }
}

$sb = New-Object System.Text.StringBuilder

[void]$sb.Append((AnsiBg $peach))
[void]$sb.Append((AnsiFg $crust))
[void]$sb.Append(" $dirDisplay ")
$prevBg = $peach

if ($gitSegment) {
    [void]$sb.Append((AnsiBg $yellow))
    [void]$sb.Append((AnsiFg $prevBg))
    [void]$sb.Append($TRIANGLE)
    [void]$sb.Append((AnsiFg $crust))
    [void]$sb.Append(" $GITSYM $branch ")
    $prevBg = $yellow
}

[void]$sb.Append((AnsiBg $green))
[void]$sb.Append((AnsiFg $prevBg))
[void]$sb.Append($TRIANGLE)
[void]$sb.Append((AnsiFg $crust))
[void]$sb.Append(" $modelName ")
$prevBg = $green

if ($hasBudget) {
    [void]$sb.Append((AnsiBg $budgetBg))
    [void]$sb.Append((AnsiFg $prevBg))
    [void]$sb.Append($TRIANGLE)
    [void]$sb.Append((AnsiFg $crust))
    [void]$sb.Append(" $BUDGETICON $budgetText ")
    $prevBg = $budgetBg
}

if ($hasRateLimits) {
    [void]$sb.Append((AnsiBg $teal))
    [void]$sb.Append((AnsiFg $prevBg))
    [void]$sb.Append($TRIANGLE)
    [void]$sb.Append((AnsiFg $crust))
    [void]$sb.Append(" $LIMITICON $limitsText ")
    $prevBg = $teal
}

[void]$sb.Append($BGRESET)
[void]$sb.Append((AnsiFg $prevBg))
[void]$sb.Append($TRIANGLE)
[void]$sb.Append($RESET)

[Console]::Out.Write($sb.ToString())
