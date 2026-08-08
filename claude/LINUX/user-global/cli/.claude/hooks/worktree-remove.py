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
