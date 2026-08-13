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
