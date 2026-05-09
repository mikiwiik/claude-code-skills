---
name: miki-rebase-reflect
description: Miki's rebase-and-impact-analyze skill. Pulls latest `main` into the current branch via rebase, then analyzes how the incoming changes interact with the in-progress work on this branch and surfaces concrete, actionable follow-ups. Invoke when the user says "/miki-rebase-reflect", "rebase against main", "pull main and check impact", "main moved, check my branch", or similar — typically when the user knows something landed in main that may affect this branch / PR.
user-invocable: true
disable-model-invocation: false
---

# miki-rebase-reflect

## What this does

Runs when something has landed in `main` that the user thinks may affect the
current branch. Two phases:

1. **Rebase** the current branch onto the latest `main`.
2. **Reflect** — analyze the incoming `main` commits *against the in-progress
   diff on this branch* and produce a short, actionable list of follow-ups.

The reflection step is scoped impact analysis, not a changelog of `main`.
Anything in the incoming commits that doesn't touch files, symbols, configs,
or conventions used by this branch is rolled up into a single tail line and
not narrated.

## Preconditions

Before starting, verify in order:

1. **Not on `main` / `master`.** The current branch must be a feature branch.
   If on the default branch, stop.
2. **Clean working tree.** `git status --porcelain` must be empty. If not,
   stop — don't mix the rebase with unrelated in-flight edits. Tell the user
   to commit, stash, or discard.
3. **Default branch identified.** Detect via `git symbolic-ref
   refs/remotes/origin/HEAD` (typically `main`, sometimes `master`). If
   ambiguous, ask the user.
4. **Branch has commits ahead of the default.** `git rev-list --count
   origin/<default>..HEAD` must be > 0. If the branch has no commits of its
   own, there's nothing to impact-analyze; offer to just `git pull --rebase`
   and exit.

If any precondition fails, report which one and exit before fetching.

## Pull strategy: always rebase

This skill **always rebases**. It does not detect or offer a merge
alternative. Rationale: the user almost exclusively rebases feature branches
against `main`; the rare cases where merge would be appropriate (history is
already shared, rebase is genuinely too painful) are human judgment calls
that fall outside the loop.

If rebase produces conflicts that aren't trivially resolvable, **stop and
hand back to the user** (see "Conflict handling" below). That is the moment
the user decides whether to push through, abort, or switch strategies.

## The rebase phase

1. **Capture the pre-rebase fork point.** Run `git merge-base HEAD
   origin/<default>` and save the SHA. This is the boundary between "your
   branch's work" (Diff B) and "what main gained" (Diff A) used in the
   reflection phase.
2. **Capture the branch's diff against the fork point** (Diff B):
   - Files changed: `git diff --name-only <fork-point>..HEAD`
   - Full diff held in memory for symbol-level analysis.
3. **Fetch.** `git fetch origin <default>`.
4. **Capture the incoming commits and diff** (Diff A):
   - Commit list: `git log --oneline <fork-point>..origin/<default>`
   - Files changed in main: `git diff --name-only
     <fork-point>..origin/<default>`
   - Full diff held in memory.
   - If the list is empty, tell the user the branch is already up to date
     and exit before rebasing — there's nothing to reflect on.
5. **Rebase.** `git rebase origin/<default>`.
6. **On success**, proceed to the reflection phase.
7. **On conflict**, see "Conflict handling".

## Conflict handling

If `git rebase` stops on conflicts:

1. **Do not auto-resolve.** Conflict resolution is judgment-heavy and
   silently choosing a side is worse than handing back.
2. Report:
   - Which files conflict (`git diff --name-only --diff-filter=U`).
   - Which incoming commit triggered the stop (`git rebase
     --show-current-patch --stat` or equivalent).
   - The current rebase state so the user can resume.
3. Tell the user the options:
   - Resolve manually, then `git rebase --continue` (the user can re-invoke
     this skill afterwards to run the reflection phase against the
     just-rebased state).
   - `git rebase --abort` to back out.
4. Exit. Do not attempt the reflection phase on a half-rebased tree.

## The reflection phase

The agent has two diffs in memory:

- **Diff A** — what `main` gained since the fork point (incoming commits).
- **Diff B** — what this branch changed vs. the fork point (in-progress
  work).

The reflection answers a single question: **for each thing in A, does it
interact with anything in B?** Anything that doesn't interact is noise.

### Impact rubric

Walk Diff A and classify each change into one of these categories. Each
category has a defined output shape so findings are concrete.

1. **File overlap** — the same file is modified in both A and B (even if
   git didn't conflict). Highest-signal category: semantics may have
   shifted even when textual merge succeeded.
2. **Symbol overlap** — a function, type, class, exported name, or public
   API that this branch *uses* (calls, imports, extends, implements) was
   modified in main. Includes signature changes, deprecations, removals,
   return-type changes, new required parameters.
3. **Dependency / lockfile changes** — `package.json`, `package-lock.json`,
   `pnpm-lock.yaml`, `yarn.lock`, `Cargo.toml`, `Cargo.lock`, `go.mod`,
   `go.sum`, `pyproject.toml`, `poetry.lock`, `requirements*.txt`,
   `Gemfile`, `Gemfile.lock`, etc. changed in main.
4. **Migration / schema changes** — new files under conventional migration
   directories (`migrations/`, `db/migrate/`, `prisma/migrations/`,
   `schema.sql`, `schema.prisma`, etc.) in main.
5. **Config / env / build changes** — `.env*`, `*.config.*`,
   `tsconfig*.json`, `vite.config.*`, `webpack.config.*`, `Dockerfile*`,
   `docker-compose*`, `Makefile`, build scripts, CI workflow files
   (`.github/workflows/*`). Includes new required env vars, changed
   defaults, changed build/test commands.
6. **Test infrastructure changes** — shared fixtures, test helpers, custom
   matchers, snapshot formats, or test config that this branch's tests
   depend on.
7. **Convention changes** — `.eslintrc*`, `.prettierrc*`,
   `eslint.config.*`, `biome.json`, `ruff.toml`, `.editorconfig`,
   formatter/linter config, or updates to `CLAUDE.md` / contributor docs
   that may contradict this branch.
8. **Other (rolled up)** — everything else in A. Not narrated individually;
   summarized as a single tail line ("N other commits in main not relevant
   to this branch").

### Required output shape per finding

Each finding emitted must include:

- **Category tag** (one of the eight above).
- **Where in main** — file path, and the symbol or specific change.
- **Where on this branch** — file:line where this branch interacts with
  it, when applicable.
- **What changed** — one sentence.
- **Action** — a concrete imperative the user can do or skip ("await the
  call", "re-run install", "re-baseline this snapshot", "re-format file
  X"). Not "consider", not "you may want to".

Example shape:

> **[symbol overlap]** `src/auth/jwt.ts:verifyToken()` — main changed the
> return type to `Promise<Result>`; your branch calls it at
> `src/api/login.ts:42` assuming sync. **Action:** await the call and
> handle the error variant.

### What the rubric explicitly rules out

- ❌ Narrating commits in main that don't touch this branch's files,
  symbols, deps, configs, or conventions. Roll them up.
- ❌ "You may want to consider..." without a specific file/line/action.
- ❌ Auto-applying any fixes. The skill **recommends only**; the user
  decides and edits. Same philosophy as `miki-review-loop` surfacing
  judgment calls.
- ❌ Generic summaries of what landed in main. If the user wanted that,
  they'd run `git log`.

### Cap the noise

If the rubric produces more than ~10 findings in a single category, group
them and surface the top examples plus a count, rather than listing every
one. The output is a to-do list, not a transcript.

## Final message format

Always end with a summary, regardless of how the skill terminated.

```
## Rebase + reflect summary

**Branch**: <branch-name>
**Rebased onto**: origin/<default> @ <short-sha>
**Incoming commits analyzed**: <n>
**Exit reason**: <one of: clean (rebased and analyzed), already up to date, conflict (handed back), precondition failed>

### Actionable findings (<count>)
- **[file overlap]** <path> — <what changed in main> — **Action:** <do this>
- **[symbol overlap]** <symbol at path> — <what changed> — used at <branch path:line> — **Action:** <do this>
- **[dependency]** <file> — <what changed> — **Action:** re-run install
- ...

### Summary by category
- File overlap: <n>
- Symbol overlap: <n>
- Dependency / lockfile: <n>
- Migration / schema: <n>
- Config / env / build: <n>
- Test infrastructure: <n>
- Convention: <n>
- Other (not relevant to this branch): <n> commits

### Rebase status
- <e.g. "Rebased cleanly. <n> commits replayed.">
- <or "Conflict in <files>; rebase paused. Resume with `git rebase --continue` or abort with `git rebase --abort`.">
```

Lead the summary with the actionable-findings count. If there are zero
findings, say so explicitly ("Rebased cleanly. No incoming changes interact
with this branch's diff.") rather than printing empty sections.

## Operating rules

- **Recommend, don't apply.** This skill never edits source files. It
  rebases (which rewrites this branch's history, expected) and then
  reports. All recommended actions are for the user to execute.
- **Never push.** Rebase rewrites history; pushing is the user's call (and
  typically requires `--force-with-lease`, which is a judgment call this
  skill won't make).
- **Never force-push, never `--force`.** If the rebase produces a state the
  user doesn't want, `git rebase --abort` or `git reflog` is the recovery
  path — surface those, don't act on them.
- **Stay scoped to Diff A ∩ Diff B.** The reflection phase is about
  interactions, not a general code review of `main`. If something in main
  looks broken but doesn't touch this branch, it's not this skill's job.
- **If `git fetch` or `git rebase` fails for non-conflict reasons**
  (network, permissions, detached HEAD, etc.), stop and report verbatim.
  Don't guess the recovery.
- **Don't second-guess the rebase choice.** The user has decided rebase is
  the strategy. If rebase becomes painful, hand back — don't suggest
  switching to merge.
