---
name: miki-rebase-reflect
description: Miki's rebase-and-reflect skill. Rebases the current branch onto the latest default branch, attempting to resolve conflicts mechanically and prompting Miki for judgment when a conflict requires a decision. After a clean rebase, reflects on what landed in the default branch — the nature of the changes and which incoming files intersect this branch's diff. Hands off only on unexpected git state (not on conflicts). Invoke when the user says "/miki-rebase-reflect", "rebase against main", "rebase against main and resolve conflicts", "pull main and reflect", "main moved, what changed", or similar.
user-invocable: true
disable-model-invocation: false
---

# miki-rebase-reflect

## What this does

Two phases:

1. **Rebase** the current branch onto the latest default branch (`main` /
   `master`). Resolve conflicts in-place: attempt mechanical resolutions
   directly, and prompt Miki for judgment when a conflict requires a
   decision. Hand off only on unexpected git state, not on conflicts.
2. **Reflect** on the commits that landed in the default branch since this
   branch forked — what kind of changes they are, plus which incoming
   files intersect this branch's own diff.

Symbol-level cross-referencing and concrete edit recommendations are
still out of scope — those belong in the follow-up conversation with full
repo context. The reflection stops at "here's what landed, and here are
the files where it overlaps your work."

## Preconditions

Before doing anything, verify in order:

1. **No rebase / merge / cherry-pick already in progress.** Check for
   `.git/rebase-merge`, `.git/rebase-apply`, `.git/MERGE_HEAD`, or
   `.git/CHERRY_PICK_HEAD`. If any exist, stop and tell Miki a git
   operation is already in progress — Miki needs to finish or abort it
   (`git rebase --continue` / `--abort`, `git merge --abort`,
   `git cherry-pick --abort`) before this skill can run. This is exactly
   the kind of "weird state" the skill is designed to hand off, not
   touch.
2. **Not on the default branch.** Current branch must not be `main` /
   `master`. If it is, stop.
3. **Clean working tree.** `git status --porcelain` must be empty. If not,
   stop and tell Miki to commit, stash, or discard.
4. **Default branch identified.** Try in order:
   1. `git symbolic-ref refs/remotes/origin/HEAD` (strip the
      `refs/remotes/origin/` prefix).
   2. If that exits non-zero (common on CI clones and some shallow
      clones where the symbolic ref isn't set), fall back to
      `git remote show origin | sed -n 's/^.*HEAD branch: //p'`.
   3. If both fail or disagree, ask Miki.

If any precondition fails, report which one and exit before fetching.

## Pull strategy: always rebase

This skill **always rebases**. Merge is out of scope; the rare cases where
merge would be appropriate are human judgment calls.

## The rebase phase

1. **Capture the fork point** before fetching: `git merge-base HEAD
   origin/<default>`. Save the SHA.
2. **Fetch.** `git fetch origin <default>`.
3. **List the incoming commits** for the reflection phase: `git log
   --oneline <fork-point>..origin/<default>`. If the list is empty, the
   branch is already up to date — say so and exit before rebasing.
4. **Rebase.** `git rebase origin/<default>`.
5. **On clean success**, proceed to the reflection phase.
6. **On conflicts**, enter the conflict-resolution loop below. Do **not**
   hand off — conflict resolution is in-scope.
7. **On any other rebase interruption** (unexpected state, not a conflict),
   hand off (see "Hand-off" below).

## Conflict resolution

When `git rebase` stops with conflicts, work through them in-place rather
than handing back to Miki. The loop:

1. Run `git status` to see which files conflict.
2. For each conflicted file, open it and examine the conflict hunks.
3. Decide: is this **mechanical** (resolve it) or **judgment** (ask Miki)?
4. Resolve or escalate per the rules below, then `git add <file>`.
5. When all conflicts in this step are staged, `git rebase --continue`.
6. If the next step in the rebase produces more conflicts, repeat from 1.
7. If `git rebase --continue` finishes cleanly, proceed to reflection.

### What counts as mechanical (resolve directly)

- **Non-overlapping additions** in the same region — both sides add new
  lines in different places; keep both.
- **Import / use / require ordering** — combine both sides' additions and
  let the language's standard ordering apply.
- **Lockfiles** (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`,
  `Cargo.lock`, `Gemfile.lock`, `poetry.lock`, `uv.lock`, etc.) — take
  one side and regenerate by re-running the relevant package manager or
  build tool. If that tool isn't available locally or regeneration
  fails, escalate.
- **Generated files** that are reproducible from sources in the repo —
  regenerate rather than merging by hand.
- **Pure formatting / whitespace** differences with no semantic change.
- **Trivial textual conflicts** where one side is clearly a strict
  superset / earlier version of the other.

### What counts as judgment (ask Miki)

- The same function or block changed differently on both sides, with
  overlapping logic.
- One side **deletes** code the other side **modified** (intent is
  ambiguous).
- A behavior change vs. a refactor of the same region — both look valid
  in isolation but produce different runtime behavior.
- Conflicts in config, schema, or infra files where the right answer
  depends on intent the diff can't reveal.
- Anything you'd hesitate on if a teammate asked "are you sure?"

When escalating, present the conflict tersely: filename, the two sides
labelled in plain language — "incoming from `<default>`" vs. "this branch's
commit" — and a one-line read on the difference. Ask Miki which to take,
or how to combine. Apply the answer and continue.

Avoid the `--ours` / `--theirs` git flags in this skill. Under `git
rebase` they're swapped relative to `git merge` (during rebase, `ours` is
the upstream you're replaying onto, `theirs` is the commit being
replayed), which is a footgun. Resolve by editing the file directly and
`git add`-ing, never via `git checkout --ours/--theirs`.

### When resolution itself goes wrong

If a resolution attempt produces something broken, **stop and hand off**,
treating it like unexpected state. To detect broken:

- If the repo has a verification command (test, build, typecheck — same
  detection as the miki-review-loop verification step), run it after the
  resolution and treat failure as broken.
- Otherwise, read the file and look for obvious syntactic damage —
  unclosed brackets, orphaned conflict markers, malformed frontmatter,
  half-merged hunks. If you can't read the resulting file and tell what
  it's supposed to be, that counts as broken.

## Hand-off (unexpected state only)

For things that aren't conflicts — `.git/MERGE_HEAD` appearing
unexpectedly, the rebase aborting itself, a detached HEAD, a refusal you
can't explain — stop and hand off. Do not attempt to fix git state.

Report:

- What state the repo is in (`git status` output is enough).
- The resume / abort commands (`git rebase --continue`,
  `git rebase --abort`).
- The fork-point SHA captured in step 1, so Miki (or the next model
  turn) can reflect on the incoming range later.

Then exit. Miki (or the surrounding model) takes it from there.

If Miki ends up finishing the rebase manually after a hand-off, don't
suggest re-invoking this skill for the reflection — it won't work
(post-manual-rebase the fork point equals `origin/<default>` and the
incoming-commits list is empty). Instead, point Miki at the captured
fork-point SHA and suggest asking the model directly: *"reflect on what
main gained since `<fork-point-sha>`"*.

## The reflection phase

Once the rebase is clean (whether the rebase itself was conflict-free or
the conflicts were resolved in-skill), produce a short read on **what
landed in the default branch since the fork point**. The audience is
Miki (or the next model turn) about to keep working on this branch.

### What to produce

1. **Incoming commits** — one-line list (subjects only, abbreviated SHAs).
2. **Nature of the changes** — a few sentences characterizing the
   *theme* of what landed: refactor, dep bumps, new feature area, infra,
   docs, etc. Call out anything obviously high-blast-radius (lockfile
   churn, build/lint config, schema migrations).
3. **Intersections with this branch's work** — list the files that
   appear in **both** the incoming range and this branch's own diff
   against the new base. Group by file; for each, note in one short line
   why it overlaps (e.g. "both sides touched the auth middleware",
   "incoming refactored the schema this branch is extending"). If
   nothing intersects, say so in one line.

### How to compute the intersection

- Incoming files: `git log --name-only --pretty=format: <fork-point>..origin/<default> | grep -v '^$' | sort -u`
- This branch's files: `git diff --name-only origin/<default>..HEAD | sort -u`
- Intersection: files present in both sets.

The `<fork-point>` is the SHA captured before the fetch in step 1 of the
rebase phase. `origin/<default>` after the rebase is the new base.

### Stop short of

- Symbol-level cross-referencing (which functions / classes / exports
  collide). That's the next conversational turn's job.
- Per-file impact assessment beyond a one-line overlap note.
- Recommending specific edits or follow-up commits.
- Walking every file in every incoming commit.

The reflection is conversational priming with a sharper pointer than
before — "here's what landed, and these are the files where it touches
your work" — not a full impact report.

## Final message format

End with a short summary. Keep it tight.

```
## Rebase + reflect

**Branch**: <branch-name>
**Rebased onto**: origin/<default> @ <short-sha>
**Exit reason**: <clean | clean after resolving conflicts | already up to date | handed off | precondition failed>
**Conflicts resolved**: <e.g. "3 mechanical" or "1 mechanical, 2 with Miki's input">

### Incoming commits
- <sha> <subject>
- <sha> <subject>
- ...

### Nature of the changes
<2–4 sentences on the theme of what landed and any high-blast-radius
heads-up. If nothing worth flagging: say so plainly.>

### Intersections with this branch
- `path/to/file.ext` — <one-line note on the overlap>
- ...
<Or: "No files touched by both incoming commits and this branch's diff.">
```

For the "Conflicts resolved" line: list only nonzero categories; omit
the whole line if zero conflicts.

If the rebase was handed off (unexpected state), replace everything from
"Incoming commits" downward with the resume / abort instructions and the
fork-point SHA.

If there were no incoming commits, say so in one line and exit.

## Operating rules

- **Resolve conflicts in-skill.** Mechanical conflicts: resolve and
  stage. Judgment-call conflicts: ask Miki, apply the answer, continue.
  Don't hand back partway through a conflict round.
- **Do edit files when resolving conflicts.** That's the one source-file
  exception; outside of conflict resolution this skill never edits.
- **Never push.** Pushing a rebased branch is Miki's call.
- **Never force-push, never `--force`.** Recovery from a bad rebase is
  `git rebase --abort` or `git reflog` — surface those, don't act on them.
- **Hand off only on unexpected git state**, not on conflicts. Conflicts
  are what this skill is here for.
