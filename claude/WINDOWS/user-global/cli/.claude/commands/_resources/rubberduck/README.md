# Rubber-duck findings

Stored output of the `/rubberduck` command — an adversarial-by-default brainstorming partner that
disagrees, hunts holes in an idea, then suggests improvements. These files are **not** designs, specs,
plans, tickets, or a commitment to build anything; they only record what was found.

## Layout

`<topic-slug>/<YYYY-MM-DD-HHMMSS>.md` — a topic is a directory, a session is one file inside it.

One file per session, never appended to. That is what keeps parallel work merge-clean: two sessions on
the same topic in different git branches write *different* files, so git merges them without conflict.
The only way to collide is two saves in the same clock second under the same slug, which human-paced use
makes negligible.

Read a topic's thread by reading its directory's files in filename (chronological) order. Each file is
self-contained — no cross-file titles, no continuation.

## Slugs are labels, not identifiers

The same topic can legitimately end up under two slugs. A session can only see the topic directories in
its own checkout, so a matching topic worked on in another git branch is invisible until merge, and
`cache-design/` and `caching-layer/` both get created. A case-only difference (`cache-design` vs
`Cache-Design`) is a separate directory in git but collides on Windows and macOS filesystems.

So: **find a topic's material by searching file contents, not by trusting the directory name.**

To reconcile duplicate directories, move the files on a quiet branch — a concurrent session still writing
to the old directory will resurrect it and need a second pass.
