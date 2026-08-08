# Port claude/LINUX/ off PowerShell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every PowerShell script and PowerShell-specific reference under `claude/LINUX/` with Python (hooks/statusline) and bash/CLAUDE.md updates, so the folder is an actually-Linux setup instead of an unmodified copy of `claude/WINDOWS/`.

**Architecture:** Three standalone Python 3 scripts (two worktree hooks, one statusline renderer) replace their `.ps1` counterparts one-for-one, invoked directly via `python3 <path>` from `settings.json` hook/statusLine commands. No new dependencies, no shared library between the scripts — each is a self-contained file matching its own `.ps1` predecessor's behavior.

**Tech Stack:** Python 3 standard library only (`json`, `subprocess`, `pathlib`, `shutil`, `sys`) — no third-party packages. Bash only where `settings.json` needs `$()` command substitution before invoking `python3`.

## Global Constraints

- Every new path in `settings.json`/hook commands uses `~` or `$HOME`, never a hardcoded absolute home directory — the repo is meant to work as-is for anyone who clones it.
- `worktree-create.py` and `worktree-remove.py` are byte-identical between `project-unique/.claude/hooks/` and `user-global/cli/.claude/hooks/` (verified the `.ps1` originals are identical; the Python ports must stay identical too).
- No third-party Python packages — stdlib only (`json`, `subprocess`, `pathlib`, `shutil`, `sys`).
- `claude/WINDOWS/` is never touched by this work.
- `.mcp.json` and `.claude.json` are not modified (already cross-platform).
- Verification is manual (per the design spec, section F) — this is a dotfiles/config repo with no existing test framework, so no pytest suite is introduced. Each task's verification steps are run once during implementation, not committed as test files.

---

### Task 1: `worktree-create.py`

**Files:**
- Create: `project-unique/.claude/hooks/worktree-create.py`
- Create: `user-global/cli/.claude/hooks/worktree-create.py` (identical content to the above)

**Interfaces:**
- Consumes: JSON on stdin `{"hook_event_name":"WorktreeCreate","name":"<name>"}`.
- Produces: absolute worktree path as the last line of stdout; non-zero exit + message on stderr on failure. No other task depends on this file's internals.

- [ ] **Step 1: Write `project-unique/.claude/hooks/worktree-create.py`**

```python
#!/usr/bin/env python3
"""WorktreeCreate hook.
stdin:  {"hook_event_name":"WorktreeCreate","name":"<name>"}
stdout: absolute path of the created worktree, as the last line.

Places worktrees at <repo>/.worktrees/<name> instead of the built-in
<repo>/.claude/worktrees/<name>. Idempotent: an existing worktree at the
target path is reported as-is rather than recreated, so it stays correct
when both the user-level and project-level copies of this hook fire.
"""
import json
import subprocess
import sys
from pathlib import Path


def run(*args):
    return subprocess.run(args, capture_output=True, text=True)


def main():
    payload = json.load(sys.stdin)
    name = (payload.get("name") or "").strip()
    if not name:
        raise SystemExit("WorktreeCreate: hook input had no 'name'.")

    root = run("git", "rev-parse", "--show-toplevel")
    if root.returncode != 0:
        raise SystemExit(f"WorktreeCreate: not inside a git repository ({root.stderr.strip()}).")

    target = (Path(root.stdout.strip()) / ".worktrees" / name).resolve()

    # Already present (re-entry, or the other copy of this hook won the race).
    if target.exists():
        print(target)
        return

    # Replicate worktree.baseRef = "fresh": branch from origin/<default-branch>.
    # The built-in creation path honors that setting; once a hook owns creation,
    # reproducing it is on us.
    base = None
    origin_head = run("git", "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    if origin_head.returncode == 0 and origin_head.stdout.strip():
        base = origin_head.stdout.strip().removeprefix("refs/remotes/")
    if not base:
        for candidate in ("origin/main", "origin/master"):
            if run("git", "rev-parse", "--verify", "--quiet", candidate).returncode == 0:
                base = candidate
                break
    if not base:
        base = "HEAD"

    branch_exists = run("git", "show-ref", "--verify", "--quiet", f"refs/heads/{name}").returncode == 0

    if branch_exists:
        add = run("git", "worktree", "add", str(target), name)
    else:
        add = run("git", "worktree", "add", "-b", name, str(target), base)
    if add.returncode != 0:
        raise SystemExit(f"WorktreeCreate: git worktree add failed for '{target}': {add.stderr.strip()}")

    print(target)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Copy it to the user-global location**

```bash
cp project-unique/.claude/hooks/worktree-create.py user-global/cli/.claude/hooks/worktree-create.py
diff project-unique/.claude/hooks/worktree-create.py user-global/cli/.claude/hooks/worktree-create.py
```
Expected: no diff output (files identical).

- [ ] **Step 3: Verify syntax**

```bash
python3 -m py_compile project-unique/.claude/hooks/worktree-create.py
```
Expected: exits 0, no output.

- [ ] **Step 4: Verify behavior against a scratch git repo**

```bash
set -e
SCRATCH=$(mktemp -d)
git init -q "$SCRATCH"
git -C "$SCRATCH" commit -q --allow-empty -m "init"
OUT=$(echo '{"hook_event_name":"WorktreeCreate","name":"feature-x"}' | (cd "$SCRATCH" && python3 "$OLDPWD/project-unique/.claude/hooks/worktree-create.py"))
echo "Created at: $OUT"
test -d "$OUT"
git -C "$SCRATCH" -C "$OUT" rev-parse --abbrev-ref HEAD
# Re-run with the same name: must be idempotent (same path, no error)
OUT2=$(echo '{"hook_event_name":"WorktreeCreate","name":"feature-x"}' | (cd "$SCRATCH" && python3 "$OLDPWD/project-unique/.claude/hooks/worktree-create.py"))
test "$OUT" = "$OUT2"
echo "Idempotent re-run OK"
rm -rf "$SCRATCH"
```
Expected: prints `Created at: <scratch>/.worktrees/feature-x`, the `test -d` passes, `rev-parse --abbrev-ref HEAD` prints `feature-x`, and `Idempotent re-run OK` prints with no errors.

- [ ] **Step 5: Commit**

```bash
git add project-unique/.claude/hooks/worktree-create.py user-global/cli/.claude/hooks/worktree-create.py
git commit -m "feat: port worktree-create hook to Python"
```

---

### Task 2: `worktree-remove.py`

**Files:**
- Create: `project-unique/.claude/hooks/worktree-remove.py`
- Create: `user-global/cli/.claude/hooks/worktree-remove.py` (identical content to the above)

**Interfaces:**
- Consumes: JSON on stdin `{"hook_event_name":"WorktreeRemove","worktree_path":"<path>"}`.
- Produces: no stdout contract; non-zero exit + message on stderr on failure. No other task depends on this file's internals.

- [ ] **Step 1: Write `project-unique/.claude/hooks/worktree-remove.py`**

```python
#!/usr/bin/env python3
"""WorktreeRemove hook.
stdin: {"hook_event_name":"WorktreeRemove","worktree_path":"<path>"}

Counterpart to worktree-create.py. Succeeds when the path is already gone,
so the second of two firing copies doesn't fail the event.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path


def run(*args):
    return subprocess.run(args, capture_output=True, text=True)


def main():
    payload = json.load(sys.stdin)
    path = (payload.get("worktree_path") or "").strip()
    if not path:
        raise SystemExit("WorktreeRemove: hook input had no 'worktree_path'.")

    if not Path(path).exists():
        run("git", "worktree", "prune")
        return

    removed = run("git", "worktree", "remove", "--force", path)
    if removed.returncode != 0:
        # Not a registered worktree (or already detached) — fall back to a plain
        # delete so the directory doesn't linger.
        shutil.rmtree(path, ignore_errors=True)
        if Path(path).exists():
            raise SystemExit(f"WorktreeRemove: could not remove '{path}': {removed.stderr.strip()}")

    run("git", "worktree", "prune")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Copy it to the user-global location**

```bash
cp project-unique/.claude/hooks/worktree-remove.py user-global/cli/.claude/hooks/worktree-remove.py
diff project-unique/.claude/hooks/worktree-remove.py user-global/cli/.claude/hooks/worktree-remove.py
```
Expected: no diff output.

- [ ] **Step 3: Verify syntax**

```bash
python3 -m py_compile project-unique/.claude/hooks/worktree-remove.py
```
Expected: exits 0, no output.

- [ ] **Step 4: Verify behavior against a scratch git repo**

```bash
set -e
SCRATCH=$(mktemp -d)
git init -q "$SCRATCH"
git -C "$SCRATCH" commit -q --allow-empty -m "init"
git -C "$SCRATCH" worktree add -q -b feature-y "$SCRATCH/.worktrees/feature-y" HEAD
test -d "$SCRATCH/.worktrees/feature-y"
echo "{\"hook_event_name\":\"WorktreeRemove\",\"worktree_path\":\"$SCRATCH/.worktrees/feature-y\"}" | python3 project-unique/.claude/hooks/worktree-remove.py
test ! -d "$SCRATCH/.worktrees/feature-y"
echo "Removed OK"
# Already-gone path must succeed, not error
echo "{\"hook_event_name\":\"WorktreeRemove\",\"worktree_path\":\"$SCRATCH/.worktrees/feature-y\"}" | python3 project-unique/.claude/hooks/worktree-remove.py
echo "Already-gone path OK"
rm -rf "$SCRATCH"
```
Expected: `test -d` passes before removal, `Removed OK` prints, the directory is gone, and the second (already-gone) invocation exits 0 and prints `Already-gone path OK` with no errors.

- [ ] **Step 5: Commit**

```bash
git add project-unique/.claude/hooks/worktree-remove.py user-global/cli/.claude/hooks/worktree-remove.py
git commit -m "feat: port worktree-remove hook to Python"
```

---

### Task 3: `statusline.py`

**Files:**
- Create: `user-global/cli/.claude/statusline.py`

**Interfaces:**
- Consumes: statusline JSON payload on stdin (fields: `workspace.current_dir` or `cwd`, `model.display_name`, `context_window.{used_percentage,remaining_percentage,total_input_tokens,context_window_size}`, `rate_limits.{five_hour,seven_day}.used_percentage`).
- Produces: a single-line ANSI-colored string written to stdout (no trailing newline, matching the original). No other task depends on this file's internals.

- [ ] **Step 1: Write `user-global/cli/.claude/statusline.py`**

```python
#!/usr/bin/env python3
"""Statusline renderer.

Reads the Claude Code statusline JSON payload from stdin and prints a
Catppuccin-Mocha powerline status line: working directory (or worktree
slug), git branch, model name, context budget, and rate limits.
"""
import json
import subprocess
import sys
from pathlib import Path

ESC = "\x1b"
RESET = f"{ESC}[0m"
BGRESET = f"{ESC}[49m"
TRIANGLE = ""
GITSYM = ""
BUDGETICON = ""
LIMITICON = ""

CRUST = (17, 17, 27)
RED = (243, 139, 168)
PEACH = (250, 179, 135)
YELLOW = (249, 226, 175)
GREEN = (166, 227, 161)
MAUVE = (203, 166, 247)
TEAL = (148, 226, 213)


def fg(c):
    return f"{ESC}[38;2;{c[0]};{c[1]};{c[2]}m"


def bg(c):
    return f"{ESC}[48;2;{c[0]};{c[1]};{c[2]}m"


def format_token_count(n):
    if n >= 1000:
        return f"{n / 1000:,.0f}K"
    return f"{n:,.0f}"


def run_git(cwd, *args):
    result = subprocess.run(
        ["git", "-C", cwd, "--no-optional-locks", *args],
        capture_output=True, text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def format_dir(path):
    home = str(Path.home())
    normalized = path
    if home:
        if normalized == home:
            normalized = "~"
        elif normalized.startswith(home + "/"):
            normalized = "~" + normalized[len(home):]
    parts = [p for p in normalized.split("/") if p]
    if len(parts) > 3:
        return "…/" + "/".join(parts[-3:])
    return "/".join(parts)


def format_worktree_tail(dir_path, toplevel):
    if not dir_path or not toplevel:
        return ""
    if len(dir_path) < len(toplevel) or not dir_path.startswith(toplevel):
        return ""
    rel = dir_path[len(toplevel):].lstrip("/")
    if not rel:
        return ""
    parts = [p for p in rel.split("/") if p]
    if len(parts) > 3:
        return "…/" + "/".join(parts[-3:])
    return "/".join(parts)


def resolve_git_path(base, raw_path):
    if not raw_path:
        return None
    candidate = Path(raw_path) if raw_path.startswith("/") else Path(base) / raw_path
    if not candidate.exists():
        return None
    return str(candidate.resolve())


def main():
    raw = sys.stdin.read()
    payload = None
    if raw:
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = None

    dir_raw = None
    if payload:
        workspace = payload.get("workspace") or {}
        dir_raw = workspace.get("current_dir") or payload.get("cwd")
    if not dir_raw:
        dir_raw = str(Path.cwd())
    if len(dir_raw) > 1:
        dir_raw = dir_raw.rstrip("/")

    model_name = "Claude"
    if payload and (payload.get("model") or {}).get("display_name"):
        model_name = payload["model"]["display_name"]

    has_budget = False
    budget_text = None
    used_pct = None
    remaining_pct = None
    if payload and payload.get("context_window"):
        cw = payload["context_window"]
        raw_used = cw.get("used_percentage")
        raw_remaining = cw.get("remaining_percentage")
        used_pct = float(raw_used) if raw_used not in (None, "") else None
        remaining_pct = float(raw_remaining) if raw_remaining not in (None, "") else None
        if used_pct is not None or remaining_pct is not None:
            has_budget = True
            tokens_part = ""
            total_input = cw.get("total_input_tokens")
            window_size = cw.get("context_window_size")
            if total_input is not None and window_size not in (None, "") and float(window_size) > 0:
                tokens_part = f"{format_token_count(float(total_input))}/{format_token_count(float(window_size))} "
            if remaining_pct is not None:
                pct_part = f"{round(remaining_pct)}% left"
            elif used_pct is not None:
                pct_part = f"{round(used_pct)}% used"
            else:
                pct_part = ""
            budget_text = f"{tokens_part}{pct_part}".strip()

    has_rate_limits = False
    limits_text = None
    if payload and payload.get("rate_limits"):
        rl = payload["rate_limits"]
        limit_parts = []
        five_hour = rl.get("five_hour") or {}
        if five_hour.get("used_percentage") not in (None, ""):
            limit_parts.append(f"5h {round(float(five_hour['used_percentage']))}%")
        seven_day = rl.get("seven_day") or {}
        if seven_day.get("used_percentage") not in (None, ""):
            limit_parts.append(f"7d {round(float(seven_day['used_percentage']))}%")
        if limit_parts:
            has_rate_limits = True
            limits_text = " · ".join(limit_parts)

    git_segment = False
    branch = None
    is_worktree = False
    worktree_slug = None
    repo_toplevel = None

    if run_git(dir_raw, "rev-parse", "--is-inside-work-tree") == "true":
        git_segment = True

        # Branch identity only - no status/porcelain call. The user's git client already
        # covers status detail; this avoids a per-render subprocess against large submodules.
        branch = run_git(dir_raw, "rev-parse", "--abbrev-ref", "HEAD")
        if not branch or branch == "HEAD":
            branch = run_git(dir_raw, "rev-parse", "--short", "HEAD") or "?"

        # Checkout identity: git-dir and git-common-dir differ only inside a linked worktree.
        repo_toplevel = run_git(dir_raw, "rev-parse", "--show-toplevel")
        if repo_toplevel:
            repo_toplevel = repo_toplevel.rstrip("/")

        git_dir_raw = run_git(dir_raw, "rev-parse", "--git-dir")
        git_common_dir_raw = run_git(dir_raw, "rev-parse", "--git-common-dir")
        git_dir_full = resolve_git_path(dir_raw, git_dir_raw)
        git_common_dir_full = resolve_git_path(dir_raw, git_common_dir_raw)
        if git_dir_full and git_common_dir_full and git_dir_full != git_common_dir_full:
            is_worktree = True
            if repo_toplevel:
                worktree_slug = repo_toplevel.rsplit("/", 1)[-1]

    if git_segment and is_worktree and worktree_slug and repo_toplevel:
        worktree_tail = format_worktree_tail(dir_raw, repo_toplevel)
        dir_display = f"wt:{worktree_slug}/{worktree_tail}" if worktree_tail else f"wt:{worktree_slug}"
    elif git_segment:
        dir_display = "root: " + format_dir(dir_raw)
    else:
        dir_display = format_dir(dir_raw)

    # Budget segment background shifts with remaining context so it reads
    # peripherally: comfortable (mauve) -> caution (yellow) -> critical (red).
    budget_bg = MAUVE
    if has_budget:
        remaining_for_color = remaining_pct if remaining_pct is not None else (
            100 - used_pct if used_pct is not None else None
        )
        if remaining_for_color is not None:
            if remaining_for_color < 15:
                budget_bg = RED
            elif remaining_for_color < 30:
                budget_bg = YELLOW
            else:
                budget_bg = MAUVE

    out = [bg(PEACH), fg(CRUST), f" {dir_display} "]
    prev_bg = PEACH

    if git_segment:
        out += [bg(YELLOW), fg(prev_bg), TRIANGLE, fg(CRUST), f" {GITSYM} {branch} "]
        prev_bg = YELLOW

    out += [bg(GREEN), fg(prev_bg), TRIANGLE, fg(CRUST), f" {model_name} "]
    prev_bg = GREEN

    if has_budget:
        out += [bg(budget_bg), fg(prev_bg), TRIANGLE, fg(CRUST), f" {BUDGETICON} {budget_text} "]
        prev_bg = budget_bg

    if has_rate_limits:
        out += [bg(TEAL), fg(prev_bg), TRIANGLE, fg(CRUST), f" {LIMITICON} {limits_text} "]
        prev_bg = TEAL

    out += [BGRESET, fg(prev_bg), TRIANGLE, RESET]

    sys.stdout.write("".join(out))


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify syntax**

```bash
python3 -m py_compile user-global/cli/.claude/statusline.py
```
Expected: exits 0, no output.

- [ ] **Step 3: Verify with a no-git, minimal payload**

```bash
printf '{"workspace":{"current_dir":"/tmp/no-git-dir"},"model":{"display_name":"Claude Sonnet 5"}}' \
  | python3 user-global/cli/.claude/statusline.py | cat -v
```
Expected: output contains `tmp/no-git-dir` and `Claude Sonnet 5`, with no git-branch segment (no ``-equivalent `^[` glyph sequence for git) since `/tmp/no-git-dir` is not a git repo.

- [ ] **Step 4: Verify with a git repo, budget, and rate-limit fields**

```bash
set -e
SCRATCH=$(mktemp -d)
git init -q "$SCRATCH"
git -C "$SCRATCH" commit -q --allow-empty -m "init"
PAYLOAD=$(cat <<JSON
{"workspace":{"current_dir":"$SCRATCH"},"model":{"display_name":"Claude Sonnet 5"},
"context_window":{"used_percentage":42,"remaining_percentage":58,"total_input_tokens":42000,"context_window_size":100000},
"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":25}}}
JSON
)
echo "$PAYLOAD" | python3 user-global/cli/.claude/statusline.py | cat -v
rm -rf "$SCRATCH"
```
Expected: output contains the repo dir, a branch segment (`master` or `main`), `Claude Sonnet 5`, `58% left`, and `5h 10% · 7d 25%` — all four segments present, joined by the `` triangle glyph (shown as `M-b M-^` or similar escaped form under `cat -v`).

- [ ] **Step 5: Verify with a git worktree payload**

```bash
set -e
SCRATCH=$(mktemp -d)
git init -q "$SCRATCH"
git -C "$SCRATCH" commit -q --allow-empty -m "init"
git -C "$SCRATCH" worktree add -q -b feature-z "$SCRATCH/.worktrees/feature-z" HEAD
printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Claude Sonnet 5"}}' "$SCRATCH/.worktrees/feature-z" \
  | python3 user-global/cli/.claude/statusline.py | cat -v
rm -rf "$SCRATCH"
```
Expected: output's directory segment starts with `wt:` followed by the scratch dir's basename (e.g. `wt:tmp.XXXXXX`), not `root: ...`.

- [ ] **Step 6: Commit**

```bash
git add user-global/cli/.claude/statusline.py
git commit -m "feat: port statusline renderer to Python"
```

---

### Task 4: `settings.json` updates

**Files:**
- Modify: `project-unique/.claude/settings.json`
- Modify: `user-global/cli/.claude/settings.json`

**Interfaces:**
- Consumes: file paths produced by Tasks 1–3 (`worktree-create.py`, `worktree-remove.py`, `statusline.py`) at the paths those tasks created them.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Update `project-unique/.claude/settings.json`**

Replace the full file contents with:

```json
{
  "defaultShell": "bash",
  "showThinkingSummaries": true,
  "showTurnDuration": true,
  "worktree.baseRef": "head",
  "permissions": {
    "defaultMode": "auto"
  },
  "hooks": {
    "WorktreeCreate": [
      {
        "hooks": [
          {
            "type": "command",
            "shell": "bash",
            "command": "python3 \"$(git rev-parse --show-toplevel)/.claude/hooks/worktree-create.py\""
          }
        ]
      }
    ],
    "WorktreeRemove": [
      {
        "hooks": [
          {
            "type": "command",
            "shell": "bash",
            "command": "python3 \"$(git rev-parse --show-toplevel)/.claude/hooks/worktree-remove.py\""
          }
        ]
      }
    ]
  },
  "worktree": {
    "baseRef": "fresh"
  },
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  },
  "verbose": true,
  "preferredNotifChannel": "auto"
}
```

Note: the `statusLine` entry here already referenced `~/.claude/statusline-command.sh` (a separate, pre-existing script outside this port's scope) rather than the per-user `statusline.ps1`/`statusline.py` — left as-is, unrelated to this task.

- [ ] **Step 2: Update `user-global/cli/.claude/settings.json`**

Replace the full file contents with:

```json
{
  "permissions": {
    "defaultMode": "auto"
  },
  "showThinkingSummaries": true,
  "showTurnDuration": true,
  "defaultShell": "bash",
  "worktree.baseRef": "head",
    "hooks": {
    "SessionStart": [
      {
        "hooks": []
      }
    ],
    "WorktreeCreate": [
      {
        "hooks": [
          {
            "type": "command",
            "shell": "bash",
            "command": "python3 ~/.claude/hooks/worktree-create.py"
          }
        ]
      }
    ],
    "WorktreeRemove": [
      {
        "hooks": [
          {
            "type": "command",
            "shell": "bash",
            "command": "python3 ~/.claude/hooks/worktree-remove.py"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "python3 ~/.claude/statusline.py"
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  },
  "skipWorkflowUsageWarning": true,
  "remoteControlAtStartup": true,
  "inputNeededNotifEnabled": true,
  "agentPushNotifEnabled": true,
  "model": "claude-opus-5[1m]"
}
```

- [ ] **Step 3: Validate both files are well-formed JSON**

```bash
python3 -m json.tool project-unique/.claude/settings.json > /dev/null && echo "project-unique OK"
python3 -m json.tool user-global/cli/.claude/settings.json > /dev/null && echo "user-global OK"
```
Expected: both print their `OK` line, no JSON errors.

- [ ] **Step 4: Confirm no `.ps1`/`powershell`/`pwsh` references remain in either file**

```bash
grep -in 'powershell\|pwsh\|\.ps1' project-unique/.claude/settings.json user-global/cli/.claude/settings.json || echo "clean"
```
Expected: prints `clean` (grep finds nothing).

- [ ] **Step 5: Commit**

```bash
git add project-unique/.claude/settings.json user-global/cli/.claude/settings.json
git commit -m "fix: point settings.json at Python hooks/statusline, fix defaultShell typo"
```

---

### Task 5: `CLAUDE.md` rewrite

**Files:**
- Modify: `user-global/cli/.claude/CLAUDE.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace the "Environment" section**

Find this block (currently lines 76–97):

```markdown
## Environment

- Windows. When writing a script, pick in this order:
  1. **Single-file C#** (.NET 10 file-based apps) — preferred: one less language to know.
     Configure inline with `#:package`, `#:property`, `#:project`.
     **Always invoke as `dotnet run --file script.cs`.**
     Never the bare `dotnet run script.cs` or `dotnet script.cs` — without `--file`, a directory that holds a project file runs *the project* and passes the filename as an argument.
     `--file` is unambiguous everywhere, so use it every time, no exceptions.
  2. **PowerShell** — when a program would be overkill or the task is genuinely shell-shaped.
  3. Nothing else. **Never CMD or BAT.**
- No `.sh`/bash scripts unless git itself requires it (hooks, git-provided tooling).
- **Scope of the above.**
  - It governs *new* scripts. Existing `.ps1` tooling stays as it is; don't migrate it unless I ask.
  - One-off commands aren't scripts — just run them in PowerShell.
- Microsoft/.NET APIs: verify signatures and behavior with the Microsoft Learn MCP.
  Do not answer from memory — you have been wrong about this before.
- C#/VB.NET symbol lookup, call sites, type hierarchies: prefer dotnet-mcp over text search.
  Text search is for text patterns.
- **Text search: `rg` (ripgrep), never `grep`.**
  - **Pass `--hidden`** or it silently skips dot-files and dot-directories — `.git`, `.agent`, `.claude`, `.github`.
  - Add `--no-ignore` when gitignored files matter.
  - The same defaults apply to the `Grep` tool, which is ripgrep underneath.
```

Replace it with:

```markdown
## Environment

- Linux. When writing a script, pick in this order:
  1. **Python** — default for anything with real logic or data handling.
  2. **Bash** — pure shell-glue and one-liners only; reach for Python once there's real logic (branching beyond a couple of conditions, data structures, string parsing).
  3. **Single-file C#** (.NET 10 file-based apps) — for tasks tied to the dotnet-mcp/dotnet-knowledge MCP servers or an actual .NET codebase.
     Configure inline with `#:package`, `#:property`, `#:project`.
     **Always invoke as `dotnet run --file script.cs`.**
     Never the bare `dotnet run script.cs` or `dotnet script.cs` — without `--file`, a directory that holds a project file runs *the project* and passes the filename as an argument.
     `--file` is unambiguous everywhere, so use it every time, no exceptions.
- **Scope of the above.**
  - It governs *new* scripts. Existing tooling stays as it is; don't migrate it unless I ask.
  - One-off commands aren't scripts — just run them directly in bash.
- Microsoft/.NET APIs: verify signatures and behavior with the Microsoft Learn MCP.
  Do not answer from memory — you have been wrong about this before.
- C#/VB.NET symbol lookup, call sites, type hierarchies: prefer dotnet-mcp over text search.
  Text search is for text patterns.
- **Text search: `rg` (ripgrep), never `grep`.**
  - **Pass `--hidden`** or it silently skips dot-files and dot-directories — `.git`, `.agent`, `.claude`, `.github`.
  - Add `--no-ignore` when gitignored files matter.
  - The same defaults apply to the `Grep` tool, which is ripgrep underneath.
```

- [ ] **Step 2: Replace the logging-syntax lines in "Verification before \"done\""**

Find this block (currently lines 58–66):

```markdown
- **Redirect the full output to a log file instead.**
  - PowerShell: `<command> *> .scratch/<name>-<timestamp>.log` — `*>` captures stdout *and* stderr.
  - `.scratch/` sits at the repo root and must be gitignored.
    Confirm it once per repo with `git check-ignore -q .scratch/probe.log` — probe a path
    *inside* the folder, because a `.scratch/` pattern won't match the bare directory name
    while the directory is still absent.
    Not ignored? Say so before writing there.
  - Name files `<what>-<yyyyMMdd-HHmm>.log`, e.g. `build-20260805-1432.log`.
    Timestamp with `Get-Date -Format yyyyMMdd-HHmm`.
```

Replace it with:

```markdown
- **Redirect the full output to a log file instead.**
  - Bash: `<command> &> .scratch/<name>-<timestamp>.log` — `&>` captures stdout *and* stderr.
  - `.scratch/` sits at the repo root and must be gitignored.
    Confirm it once per repo with `git check-ignore -q .scratch/probe.log` — probe a path
    *inside* the folder, because a `.scratch/` pattern won't match the bare directory name
    while the directory is still absent.
    Not ignored? Say so before writing there.
  - Name files `<what>-<yyyyMMdd-HHmm>.log`, e.g. `build-20260805-1432.log`.
    Timestamp with `` `date +%Y%m%d-%H%M` ``.
```

- [ ] **Step 3: Confirm no PowerShell references remain**

```bash
grep -in 'powershell\|pwsh\|\.ps1\|cmd\.exe\|\.bat\b' user-global/cli/.claude/CLAUDE.md || echo "clean"
```
Expected: prints `clean`.

- [ ] **Step 4: Commit**

```bash
git add user-global/cli/.claude/CLAUDE.md
git commit -m "docs: rewrite CLAUDE.md Environment section for Linux/bash/Python"
```

---

## Final check (after all tasks)

- [ ] Confirm no `.ps1` files remain under `claude/LINUX/`:

```bash
find . -name '*.ps1'
```
Expected: no output.

- [ ] Confirm `claude/WINDOWS/` is untouched:

```bash
git status ../WINDOWS
```
Expected: `nothing to commit, working tree clean` (or no output if run from within `claude/LINUX/` with a scoped path — adjust the path to point at `claude/WINDOWS` from the repo root if needed).
