---
name: miki-rebase-reflect
description: Miki's rebase-and-reflect skill. Rebases the current branch onto the latest default branch, then reflects on the nature of what landed in the default branch and what it might mean for this branch. If the rebase gets complex (non-trivial conflicts, unexpected git state), flags and hands off to the user or model. Invoke when the user says "/miki-rebase-reflect", "rebase against main", "pull main and reflect", "main moved, what changed", or similar.
user-invocable: true
disable-model-invocation: false
---

# miki-rebase-reflect

## What this does

Two phases:

1. **Rebase** the current branch onto the latest default branch (`main` /
   `master`).
2. **Reflect** on the nature of the commits that landed in the default
   branch since this branch forked — what kind of changes they are, and a
   short read on what they might mean for the in-progress work.

Deep impact analysis, symbol-level cross-referencing, conflict resolution
strategies — those are not this skill's job. A capable model handling the
follow-up conversation is better placed to do that with full repo context.
This skill exists to do the mechanical rebase and prime the conversation
with a useful summary of what just merged.

## Preconditions

Before doing anything, verify in order:

1. **No rebase / merge / cherry-pick already in progress.** Check for
   `.git/rebase-merge`, `.git/rebase-apply`, `.git/MERGE_HEAD`, or
   `.git/CHERRY_PICK_HEAD`. If any exist, stop and tell the user a git
   operation is already in progress — they need to finish or abort it
   (`git rebase --continue` / `--abort`, `git merge --abort`,
   `git cherry-pick --abort`) before this skill can run. This is exactly
   the kind of "weird state" the skill is designed to hand off, not
   touch.
2. **Not on the default branch.** Current branch must not be `main` /
   `master`. If it is, stop.
3. **Clean working tree.** `git status --porcelain` must be empty. If not,
   stop and tell the user to commit, stash, or discard.
4. **Default branch identified.** Try in order:
   1. `git symbolic-ref refs/remotes/origin/HEAD` (strip the
      `refs/remotes/origin/` prefix).
   2. If that exits non-zero (common on CI clones and some shallow
      clones where the symbolic ref isn't set), fall back to
      `git remote show origin | sed -n 's/^.*HEAD branch: //p'`.
   3. If both fail or disagree, ask the user.

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
6. **On conflict or any other rebase interruption**, hand off (see below).

## When the rebase gets complex: hand off

If `git rebase` stops for any reason — conflicts, unexpected state, an
operation that needs decisions this skill shouldn't make — **stop and hand
off.** Do not attempt automated resolution.

Report:

- What state the rebase is in (`git status` output is enough).
- Which files conflict, if any.
- The resume / abort commands (`git rebase --continue`,
  `git rebase --abort`).
- The fork-point SHA captured in step 1, so the user (or model) can
  reflect on the incoming range later.

Then exit. The user (or the surrounding model) takes it from there.

Once they finish the rebase manually, **do not** tell them to re-invoke
this skill for the reflection. Re-invoking won't work: after a manual
rebase the branch is up-to-date with `origin/<default>`, so the fork
point equals `origin/<default>` and the incoming-commits list comes back
empty. Instead, tell them they can ask the model directly — something
like *"reflect on what main gained since `<fork-point-sha>`"* — and pass
along the fork-point SHA captured in step 1 of the rebase phase so the
model has a precise range to look at.

## The reflection phase

Once the rebase is clean, produce a short read on **what landed in the
default branch since the fork point**. The audience is the user (or the
next model turn) about to keep working on this branch.

Aim for: a few sentences that characterize the *nature* of the incoming
changes, plus a one-line list of the incoming commits.

Useful things to surface, when relevant — not as a checklist to grind
through, but as cues:

- The general theme (refactor, dependency bumps, new feature area, infra,
  docs, etc.).
- Anything that *looks* like it could touch the area this branch is
  working in — mention it, don't analyze it deeply. Leave the actual
  impact assessment to the next conversational turn or to the user.
- Anything obviously high-blast-radius (lockfile churn, config or build
  changes, lint/format config, schema migrations) worth a heads-up.

Do **not**:

- Walk every file in every incoming commit.
- Cross-reference symbols against this branch's diff.
- Emit a structured rubric or per-finding action list.
- Recommend specific edits.

The reflection is conversational priming, not a report.

## Final message format

End with a short summary. Keep it tight.

```
## Rebase + reflect

**Branch**: <branch-name>
**Rebased onto**: origin/<default> @ <short-sha>
**Exit reason**: <clean | already up to date | rebase handed off | precondition failed>

### Incoming commits
- <sha> <subject>
- <sha> <subject>
- ...

### Reflection
<2–5 sentences on the nature of what landed and anything worth a heads-up
for this branch. If nothing worth flagging: say so plainly.>
```

If the rebase was handed off, replace the reflection with the resume /
abort instructions and skip the rest.

If there were no incoming commits, say so in one line and exit.

## Operating rules

- **Recommend, don't apply.** This skill never edits source files. It
  rebases (which rewrites this branch's history — expected) and reports.
- **Never push.** Pushing a rebased branch is the user's call.
- **Never force-push, never `--force`.** Recovery from a bad rebase is
  `git rebase --abort` or `git reflog` — surface those, don't act on them.
- **Hand off early.** Anything beyond a clean rebase + a short
  characterization belongs in the next turn of conversation, not in this
  skill.
