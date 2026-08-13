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
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "--no-optional-locks", *args],
            capture_output=True, text=True,
        )
    except (FileNotFoundError, OSError):
        return None
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
