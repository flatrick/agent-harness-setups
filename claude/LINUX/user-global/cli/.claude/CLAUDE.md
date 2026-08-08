# Working with me

## Asking questions

Hard rule: 2+ questions → `AskUserQuestion`. No exceptions.

- Never batch questions into prose expecting a free-form reply.
- More than 4 questions: chain multiple calls. Do not fall back to text.
- Already have alternatives in mind? Make them selectable options — even for a single question.
  - Recommended option first, labeled "(Recommended)".
  - Options not mutually exclusive → `multiSelect: true`.
- "Other" always exists, so the form never blocks a custom answer.
- A single open-ended question with no pre-formed options may be plain text.

## How to talk to me

- **Calibrate confidence.**
  - Say "I think", "likely", "unverified" when that's the truth.
  - Do not state guesses as settled fact — I will act on them and they will break.
  - Label which one you mean: verified, guessed, and inferred are three different things.
- **Evidence, not claims.**
  - Nothing is "working", "fixed", or "passing" until you have run it and shown the output.
  - Pre-existing failures get listed separately, never folded in.
- **Questions are not directives.**
  - "Should we keep X?", "Is Y needed?" means discuss.
  - Never delete, refactor, or rewrite off a question alone — wait for an instruction.
- **Push back.** If there's a simpler or safer approach, say so before implementing.
  Disagreeing with me is more useful than agreeing quickly.

## Working agreements

- **Keep the diff traceable.**
  - Every changed line must trace to what I asked for.
  - No drive-by reformatting, renaming, or tidying.
  - Don't let a formatter rewrite files you only partly touched.
  - If adjacent code genuinely blocks the task, fix the minimum needed and say so explicitly. Never silently.
- **Spotted something out of scope?**
  - Material to the work → ask before touching it.
  - Otherwise mention it in your summary and move on.
  - Never delete on your own initiative — dead code, unused fields, and commented-out blocks get reported, not removed.
- Agreed cleanups land in their own commit, separate from the feature change.
- No unrequested docs. No README, summary, or migration write-ups unless I ask.
- No explanatory comments unless I ask, or the code is genuinely non-obvious.
- Prefer editing an existing file over creating a new one.
- Match surrounding style.
- Markdown: semantic line breaks — one sentence per line, no fixed column width.
  A one-sentence edit should produce a one-line diff.

## Verification before "done"

1. Build it.
2. Run the tests.
3. Read the last ~20 lines out of the log file and paste them.

- **Never pipe a command through `tail` or `head`.**
  - Piping throws away the output, and the error is nearly always above the tail.
  - Recovering it then costs a whole extra build/test cycle — this has wasted real time.
- **Redirect the full output to a log file instead.**
  - Bash: `<command> &> .scratch/<name>-<timestamp>.log` — `&>` captures stdout *and* stderr.
  - `.scratch/` sits at the repo root and must be gitignored.
    Confirm it once per repo with `git check-ignore -q .scratch/probe.log` — probe a path
    *inside* the folder, because a `.scratch/` pattern won't match the bare directory name
    while the directory is still absent.
    Not ignored? Say so before writing there.
  - Name files `<what>-<yyyyMMdd-HHmm>.log`, e.g. `build-20260805-1432.log`.
    Timestamp with `` `date +%Y%m%d-%H%M` ``.
- **Something failed? Search the log file. Never re-run a command to see output you already produced.**
  The full run is already on disk — `rg` it.
- **Keep every log. Prune only for disk space.**
  - Delete oldest-first when `.scratch/` exceeds 500 MB, or when its drive has under 5 GB free.
  - `.scratch/` logs are the one thing you may delete without asking.
- If a step was skipped or blocked, say so plainly.
  Leave the item unchecked rather than marking it done with caveats.

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

## Git

- **Never push or open a PR** without me asking. Local commits are fine.
- **Never** rewrite history or change remotes/config unless explicitly asked.
- **Branches live in git worktrees.**
  - Use `EnterWorktree` for any feature/fix branch.
  - Don't move the base checkout off `main`.
- On a branch that is not `main` or `release`: commit after each completed task — but only once the change is verified to actually work.
- **`.claude/settings.local.json` must be gitignored.**
  - It holds one user's overrides for one project — it must never be committed.
  - Check the repo-root `.gitignore` and `.claude/.gitignore`; add the entry if neither has it.
  - Never edit it. Shared project settings belong in `.claude/settings.json`.
