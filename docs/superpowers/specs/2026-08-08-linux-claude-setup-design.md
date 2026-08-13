# Port claude/LINUX/ from PowerShell to bash/Python

## Context

`claude/LINUX/` is currently a byte-for-byte copy of `claude/WINDOWS/`.
It still ships `.ps1` hooks, a `pwsh`-invoked statusline, `"deaultShell": "powershell"` (a pre-existing typo carried over from Windows — should be `defaultShell`), and a `CLAUDE.md` written entirely around PowerShell and .NET conventions.

This spec ports it to an actual Linux setup: Python for hooks/statusline, a Python-first/bash-for-glue/C#-for-.NET scripting priority, and generic `~`/`$HOME` paths so the checked-in config stays directly usable by anyone browsing the repo for inspiration (per the repo README's stated goal).

## Scope

In scope: everything under `claude/LINUX/`. `claude/WINDOWS/` is untouched.

`.mcp.json` (dotnet-mcp, dotnet-knowledge) and `.claude.json` (Serena) are cross-platform already and are **not** modified.

## A. File layout

| Windows | Linux |
|---|---|
| `project-unique/.claude/hooks/worktree-create.ps1` | `worktree-create.py` |
| `project-unique/.claude/hooks/worktree-remove.ps1` | `worktree-remove.py` |
| `user-global/cli/.claude/hooks/worktree-create.ps1` | `worktree-create.py` |
| `user-global/cli/.claude/hooks/worktree-remove.ps1` | `worktree-remove.py` |
| `user-global/cli/.claude/statusline.ps1` | `statusline.py` |

Bug fixed along the way: `user-global/cli/.claude/settings.json` currently points hooks at `~/.claude/.claude/hooks/...` (doubled `.claude`). The corrected paths are the single-level `~/.claude/hooks/...` and `~/.claude/statusline.py`.

## B. `worktree-create.py` / `worktree-remove.py`

Faithful behavioral port of the PowerShell logic, using `subprocess` for git calls and `json`/`sys.stdin` for the hook payload.

**worktree-create.py**
1. Read `name` from the stdin JSON payload (`{"hook_event_name":"WorktreeCreate","name":"<name>"}`).
2. Resolve repo root via `git rev-parse --show-toplevel`.
3. `target = <root>/.worktrees/<name>`.
4. If `target` already exists, print it and exit 0 (idempotent — covers re-entry or the other copy of this hook winning the race).
5. Otherwise determine the base ref: `origin/HEAD` symbolic-ref → `origin/main` → `origin/master` → `HEAD`.
6. If a local branch `<name>` already exists: `git worktree add <target> <name>`. Otherwise: `git worktree add -b <name> <target> <base>`.
7. Print `target` as the last line of stdout.
8. Any failure raises `SystemExit("WorktreeCreate: ...")` (non-zero exit fails the hook, message on stderr) — matching the PowerShell `throw` behavior.

**worktree-remove.py**
1. Read `worktree_path` from the stdin JSON payload.
2. If the path doesn't exist, run `git worktree prune` and exit 0.
3. Otherwise `git worktree remove --force <path>`; on failure, fall back to `shutil.rmtree(path, ignore_errors=True)`, then raise `SystemExit` only if the path still exists afterward.
4. Always finish with `git worktree prune`.

Path handling is simpler than the PowerShell version: Linux paths are already `/`-separated, so there's no backslash-normalization step to port.

## C. `statusline.py`

Same visual output as `statusline.ps1` — Catppuccin-Mocha powerline segments for: working directory (or `wt:<slug>/<tail>` inside a worktree), git branch, model name, context-budget (colored mauve/yellow/red at 30%/15% remaining), and rate limits.

- `json.load(sys.stdin)` replaces `ConvertFrom-Json`.
- Home-dir collapsing uses `Path.home()` instead of `$env:USERPROFILE`.
- Drop the Windows-only backslash-normalization block; path splitting uses `/` directly (the JSON payload's `cwd`/`current_dir` and Linux's native paths already agree).
- `subprocess.run(["git", "-C", dir, "--no-optional-locks", ...])` for the three checks: is-inside-work-tree, branch name (falling back to short SHA), and git-dir vs. git-common-dir (to detect a linked worktree and derive its slug).
- Same ANSI truecolor escapes (`\x1b[38;2;r;g;bm` / `\x1b[48;2;r;g;bm`), same `` / `` powerline glyphs, same three-segment path truncation (`…/last/three/parts`).

## D. `settings.json` edits

**project-unique/.claude/settings.json**
- `"defaultShell": "bash"` (was `"powershell"`).
- Hook commands become `python3 "$(git rev-parse --show-toplevel)/.claude/hooks/worktree-create.py"` and the `-remove.py` counterpart, each still under `"shell": "bash"` so the `$()` substitution resolves before `python3` runs.

**user-global/cli/.claude/settings.json**
- Fix the typo and value: `"deaultShell"` → `"defaultShell": "bash"`.
- Hook commands → `python3 ~/.claude/hooks/worktree-create.py` / `python3 ~/.claude/hooks/worktree-remove.py`.
- `statusLine.command` → `python3 ~/.claude/statusline.py` (drops `pwsh -NoProfile -NoLogo -File` and the doubled `.claude/.claude` path).
- Everything else (`permissions`, `worktree.baseRef`, `enabledPlugins`, `model`, notification flags, etc.) is unchanged — none of it is OS-specific.

## E. `CLAUDE.md` rewrite

Only the **Environment** and **Verification before "done"** sections are Windows/PowerShell-specific. **Asking questions**, **How to talk to me**, **Working agreements**, and **Git** are already OS-agnostic and stay untouched.

**Environment**, new priority order for one-off scripts:
1. **Python** — default for anything with real logic or data handling.
2. **Bash** — pure shell-glue / one-liners only; drop the old "no `.sh`/bash scripts unless git requires it" line since bash is now explicitly allowed for this tier.
3. **Single-file C#** (.NET 10 file-based apps, `dotnet run --file`) — for tasks tied to the dotnet-mcp/dotnet-knowledge MCP servers or an actual .NET codebase. Kept at full detail, same prominence as the Windows version: the `--file`-not-bare-`dotnet run` warning, the Microsoft Learn MCP verification requirement, and "prefer dotnet-mcp over text search for C#/VB.NET symbols" all carry over verbatim.

`rg`-not-`grep` guidance is unchanged (already portable).

**Verification / logging syntax**: PowerShell `<command> *> .scratch/<name>-<timestamp>.log` becomes bash `<command> &> .scratch/<name>-<timestamp>.log`. `Get-Date -Format yyyyMMdd-HHmm` becomes `` `date +%Y%m%d-%H%M` ``. All other rules are unchanged: never pipe through `tail`/`head`, redirect full output to `.scratch/`, search the log with `rg` instead of re-running, prune oldest-first only for disk space.

## F. Verification plan

- `python3 -m py_compile` on all three new scripts.
- Manual dry run of `worktree-create.py` / `worktree-remove.py` against a scratch git repo: create → verify path and branch → remove → verify cleanup and prune, including the idempotent-recreate and already-gone-path cases.
- Manual run of `statusline.py` with a handful of sample JSON payloads piped via stdin (with/without git, with/without worktree, with/without budget and rate-limit fields) to confirm each segment renders correctly.
