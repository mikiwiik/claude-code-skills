---
name: miki-rebase-reflect
description: Miki's rebase-and-reflect skill. Rebases the current branch onto the latest default branch, attempting to resolve conflicts mechanically and prompting the user for judgment when a conflict requires a decision. After a clean rebase, reflects on what landed in the default branch — the nature of the changes and which incoming files intersect this branch's diff. Hands off only on unexpected git state (not on conflicts). Invoke when the user says "/miki-rebase-reflect", "rebase against main", "rebase against main and resolve conflicts", "pull main and reflect", "main moved, what changed", or similar.
user-invocable: true
disable-model-invocation: false
---

# miki-rebase-reflect

## What this does

1. **Rebase** the current branch onto the latest default branch (`main` / `master`), resolving conflicts in-place: mechanical fixes directly, judgment calls escalated to the user. Hand off only on unexpected git state, not on conflicts.
2. **Reflect** on what landed in the default branch since this branch forked — nature of the changes plus which incoming files intersect this branch's diff.

Symbol-level cross-referencing and concrete edit recommendations stay out of scope — those belong in the follow-up turn with full repo context.

## Preconditions

Verify in order; stop and report on first failure:

1. **No rebase / merge / cherry-pick in progress** — no `.git/rebase-merge`, `.git/rebase-apply`, `.git/MERGE_HEAD`, or `.git/CHERRY_PICK_HEAD`. If one exists, tell the user to finish or abort it first (this is the kind of state we hand off, not touch).
2. **Not on the default branch.**
3. **Clean working tree** (`git status --porcelain` empty).
4. **Default branch identified.** Try `git symbolic-ref refs/remotes/origin/HEAD`, then `git remote show origin | sed -n 's/^.*HEAD branch: //p'`. If both fail or disagree, ask the user.

## Rebase phase

Always rebase (never merge — merge cases are human judgment calls).

1. Capture fork point before fetching: `git merge-base HEAD origin/<default>`. Save the SHA.
2. `git fetch origin <default>`.
3. List incoming: `git log --oneline <fork-point>..origin/<default>`. If empty, branch is up to date — say so and exit.
4. `git rebase origin/<default>`.
5. On clean success → reflection phase. On conflicts → resolve in-skill (below). On any other interruption → hand off.

## Conflict resolution

When `git rebase` stops with conflicts, work through them in place:

1. `git status` for the conflict list.
2. For each conflicted file, classify as **mechanical** (resolve) or **judgment** (ask the user), per the rules below.
3. Resolve or escalate, then `git add <file>`.
4. When all conflicts in this rebase step are staged, `git rebase --continue`. If the next step conflicts, repeat from 1.

**Mechanical (resolve directly):** non-overlapping additions (keep both); import/use/require ordering (combine, let standard order apply); lockfiles (take one side, re-run the package manager / build tool to regenerate — escalate if the tool isn't available or regeneration fails); other generated files reproducible from sources (regenerate); pure whitespace/formatting; strict-superset textual overlaps.

**Judgment (ask the user):** same function/block changed differently on both sides; one side deletes what the other modified; behavior change vs. refactor of the same region; config/schema/infra where intent isn't visible in the diff; anything you'd hesitate on.

When escalating, present tersely: filename, both sides labelled in plain language ("incoming from `<default>`" vs. "this branch's commit"), one-line read on the difference. Ask which to take or how to combine; apply the answer; continue.

Avoid `--ours` / `--theirs`: under rebase they're swapped relative to merge (`ours` = upstream you're replaying onto, `theirs` = commit being replayed). Resolve by editing + `git add`, never via `git checkout --ours/--theirs`.

If a resolution attempt produces something broken — verification command fails (if one exists), or visual check shows unclosed brackets, orphaned conflict markers, malformed frontmatter, half-merged hunks — stop and hand off.

## Hand-off (unexpected git state only)

For non-conflict interruptions — `.git/MERGE_HEAD` appearing unexpectedly, the rebase aborting itself, detached HEAD, unexplained refusals — stop and report:

- Current state (`git status` output).
- Resume / abort commands (`git rebase --continue` / `--abort`).
- The fork-point SHA from step 1, so the user (or next model turn) can reflect on the incoming range later.

If the user finishes the rebase manually after hand-off, don't suggest re-invoking this skill — post-manual-rebase the incoming range is empty. Point them at the fork-point SHA and suggest *"reflect on what main gained since `<fork-point-sha>`"*.

## Reflection phase

Once clean (conflict-free or resolved in-skill), produce a short read for the user (or the next model turn):

1. **Incoming commits** — abbreviated SHAs + subjects.
2. **Nature of the changes** — a few sentences on the theme (refactor, deps, infra, docs, etc.). Call out high-blast-radius items: lockfile churn, build/lint config, schema migrations.
3. **Intersections with this branch** — files touched by both the incoming range and this branch's diff against the new base. One line per file noting the overlap. If none, say so.

Compute the intersection:

- Incoming: `git log --name-only --pretty=format: <fork-point>..origin/<default> | grep -v '^$' | sort -u`
- This branch: `git diff --name-only origin/<default>..HEAD | sort -u`

Stop short of symbol-level cross-ref, per-file impact analysis beyond the one-line note, edit recommendations, and walking every file in every incoming commit. The reflection is priming, not a report.

## Final message format

```
## Rebase + reflect

**Branch**: <branch-name>
**Rebased onto**: origin/<default> @ <short-sha>
**Exit reason**: <clean | clean after resolving conflicts | already up to date | handed off | precondition failed>
**Conflicts resolved**: <e.g. "3 mechanical" or "1 mechanical, 2 with user input">

### Incoming commits
- <sha> <subject>
- ...

### Nature of the changes
<2–4 sentences. If nothing worth flagging: say so plainly.>

### Intersections with this branch
- `path/to/file.ext` — <one-line note>
- ...
<Or: "No files touched by both incoming commits and this branch's diff.">
```

List only nonzero categories in **Conflicts resolved**; omit the line if zero. On hand-off, replace everything from "Incoming commits" downward with resume/abort instructions and the fork-point SHA. On no-incoming-commits, one line and exit.

## Operating rules

- **Resolve conflicts in-skill.** Don't hand back partway through.
- **Edit files only when resolving conflicts** — that's the one exception; otherwise this skill never edits.
- **Never push.** Never force-push. Recovery from a bad rebase is `git rebase --abort` or `git reflog`.
- **Hand off only on unexpected git state**, not on conflicts.
