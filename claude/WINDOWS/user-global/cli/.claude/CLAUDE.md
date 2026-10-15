# Working with me

## Language: ASD-STE100

Write all text in ASD-STE100 Simplified Technical English.
This rule applies to replies to me, files (docs, specs, openspec, plans), commit messages, PR text, and code comments.

- Write instructions as short sentences: 20 words maximum.
- Write descriptions as short sentences: 25 words maximum.
- Write one instruction in one sentence.
- Use the imperative for instructions.
- Use the active voice.
- Use the simple tenses: present, past, and future.
- Use one word for one meaning. Use the same term for the same thing each time.
- Do not use idioms, slang, or phrasal verbs. Write "start", not "kick off".
- Keep "a", "the", and "that". Do not remove them to make text shorter.
- Write a paragraph with 6 sentences maximum.
- Put a warning or caution before the step that it applies to.
- Do not change code, commands, identifiers, paths, product names, error messages, or quoted text. These are exempt.

## Asking questions

Hard rule: when you have 2 or more questions, use `AskUserQuestion`. There are no exceptions.

- Do not put many questions in prose and expect a free-form reply.
- If you have more than 4 questions, use more than one call. Do not use text instead.
- If you already have alternatives, show them as options. Do this also for a single question.
  - Put the recommended option first. Add "(Recommended)" to its label.
  - If the options are not mutually exclusive, set `multiSelect: true`.
- The form always has an "Other" option. Thus I can always give a custom answer.
- You can ask a single open question with no options in plain text.

## How to talk to me

- **Show your level of confidence correctly.**
  - Write "I think", "likely", or "unverified" when that is true.
  - Do not write a guess as a fact. I will act on it, and it will break.
  - Tell me which type it is: verified, guessed, or inferred. These are 3 different types.
- **Give evidence, not claims.**
  - Do not call something "working", "fixed", or "passing" until you run it and show the output.
  - List failures that existed before your change separately. Do not mix them with new failures.
- **A question is not an instruction.**
  - "Should we keep X?" and "Is Y needed?" are requests for discussion.
  - Do not delete, refactor, or rewrite because of a question. Wait for an instruction.
- **Disagree with me when necessary.** If a simpler or safer approach exists, tell me before you implement.
  Disagreement is more useful to me than fast agreement.

## Working agreements

- **Keep the diff traceable.**
  - Each changed line must come from my request.
  - Do not reformat, rename, or tidy code that is not part of the task.
  - Do not let a formatter rewrite files that you changed only partially.
  - If adjacent code blocks the task, make the minimum fix. Tell me about it clearly. Do not do it silently.
- **Did you find a problem that is out of scope?**
  - If it is material to the task, ask me before you change it.
  - If not, write it in your summary and continue.
  - Do not delete things on your own decision. Report dead code, unused fields, and commented-out blocks. Do not remove them.
- Put agreed cleanups in a separate commit. Do not mix them with the feature change.
- Do not write docs that I did not request. This includes READMEs, summaries, and migration documents.
- Do not write explanatory comments, unless I request them or the code is not clear without them.
- When possible, edit an existing file. Do not create a new file instead.
- Use the same style as the surrounding code.
- Markdown: use semantic line breaks. Write one sentence on each line. Do not use a fixed column width.
  A change to one sentence must give a one-line diff.

## Verification before "done"

1. Build it.
2. Run the tests.
3. Read the last ~20 lines of the log file and paste them.

- **Do not pipe a command through `tail`, `head`, or `Select-Object -First`.**
  - A pipe discards the output, and the error is almost always above the tail.
  - To get the output back, you must do one more full build or test cycle. This problem has wasted real time.
- **Send the full output to a log file.**
  - PowerShell: `<command> *> .scratch/<name>-<timestamp>.log`. The `*>` captures stdout *and* stderr.
  - `.scratch/` is at the repo root and must be gitignored.
    Check this one time for each repo with `git check-ignore -q .scratch/probe.log`.
    Test a path *in* the folder. When the directory does not exist, a `.scratch/` pattern does not match the bare directory name.
    If it is not ignored, tell me before you write there.
  - Name the files `<what>-<yyyyMMdd-HHmm>.log`, for example `build-20260805-1432.log`.
    Get the timestamp with `Get-Date -Format yyyyMMdd-HHmm`.
- **If a command fails, search the log file. Do not run the command again to see output that you already have.**
  The full output is on disk. Use `rg` to search it.
- **Keep all logs. Delete logs only to get disk space.**
  - Delete the oldest logs first when `.scratch/` is larger than 500 MB.
    Do the same when its drive has less than 5 GB free.
  - You can delete `.scratch/` logs without asking me. This is the only exception.
- If you skipped a step, or something blocked it, tell me clearly.
  Do not mark the item as done with caveats. Leave it unchecked.

## Environment

- Windows. When you write a script, select the language in this order:
  1. **Single-file C#** (.NET 10 file-based apps): preferred, because then there is one less language to know.
     Configure it inline with `#:package`, `#:property`, `#:project`.
     **Always run it as `dotnet run --file script.cs`.**
     Do not use the bare `dotnet run script.cs` or `dotnet script.cs`.
     Without `--file`, a directory with a project file runs *the project*. The filename goes to the project as an argument.
     `--file` is not ambiguous in any location. Use it each time, with no exceptions.
  2. **PowerShell**: when a program is too much, or the task is really a shell task.
  3. No other language. **Do not use CMD or BAT.**
- Do not write `.sh` or bash scripts, unless git itself requires them (hooks, tooling from git).
- **Scope of the rules above.**
  - They apply to *new* scripts. Do not migrate existing `.ps1` tooling, unless I tell you to.
  - A one-off command is not a script. Run it directly in PowerShell.
- Microsoft/.NET APIs: use the Microsoft Learn MCP to verify signatures and behavior.
  Do not answer from memory. Your memory was wrong about this before.
- C#/VB.NET symbol lookup, call sites, and type hierarchies: use dotnet-mcp, not text search.
  Use text search only for text patterns.
- **Text search: use `rg` (ripgrep). Do not use `grep`.**
  - **Always add `--hidden`.** Without it, `rg` silently skips dot-files and dot-directories: `.git`, `.agent`, `.claude`, `.github`.
  - Add `--no-ignore` when gitignored files are important.
  - The same defaults apply to the `Grep` tool, because it uses ripgrep.

## Git

- **Do not push or open a PR** until I tell you to. Local commits are permitted.
- **Do not** rewrite history or change remotes or config, unless I tell you to.
- **Put branches in git worktrees.**
  - Use `EnterWorktree` for each feature or fix branch.
  - Keep the base checkout on `main`.
- On a branch that is not `main` or `release`: commit after each completed task.
  Commit only after you verify that the change works.
- **`.claude/settings.local.json` must be gitignored.**
  - It contains the overrides of one user for one project. Do not commit it.
  - Look in the repo-root `.gitignore` and in `.claude/.gitignore`. If neither has the entry, add it.
  - Do not edit it. Shared project settings go in `.claude/settings.json`.

@~/.claude/pstack-models.md
