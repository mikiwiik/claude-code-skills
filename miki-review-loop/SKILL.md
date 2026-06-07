---
name: miki-review-loop
description: Miki's personal pre-self-review loop. Iteratively runs /review on the current PR and addresses obvious issues until only minor nits remain or 3 iterations have run. Surfaces judgment calls back to the user, makes atomic commits per project convention, pushes once at the end. Invoke when the user says "/miki-review-loop", "loop the review", "iterate on the review", or similar after a PR has been created.
argument-hint: "Optional PR number; if omitted, derived from current branch"
user-invocable: true
disable-model-invocation: false
---

# miki-review-loop

## What this does

Runs `/review` → addresses issues → re-runs, up to 3 iterations. Exits when only nits remain, a judgment call surfaces, or the cap is hit. Ends with a written summary of every change and commit.

## Preconditions

Verify in order; stop and report on first failure:

1. **PR identification.**
   - **Argument given** (bare `84`, `#84`, `PR 84`, `PR #84`, or full PR URL): normalize to a bare number, run `gh pr view <n> --json number,title,headRefName,baseRefName,state`, announce `Processing PR #N — "<title>" on <head> → <base>`, proceed.
   - **No argument**: derive from current branch via `gh pr view --json number,title,headRefName,baseRefName,state`. Announce `Detected PR #N — ...` and **ask to confirm**. If ambiguous, list candidates and ask.
   - **No PR or not OPEN**: stop.
2. **Clean working tree** (`git status --porcelain` empty).
3. **Not on `main` / `master`.**
4. **Verification command available** (see below). If not, follow the prompt-to-create flow before iteration 1.

## Verification command

The loop runs the repo's verification command between iterations to confirm fixes don't break the build. Detect on each run:

1. **`package.json` scripts** — try in order: `check`, `verify`, `validate`, `ci`, `test`. For each, prefer the `:ci` variant when present (e.g. `check:ci` over `check`) — tuned for non-interactive runs. First match wins.
2. **Other stacks** — `Cargo.toml` → `cargo check && cargo test`; `Makefile` with `check` target → `make check`; `pyproject.toml` with `[tool.<runner>]` → obvious `check`/`test` task.
3. **`CLAUDE.md`** — grep for a documented verification command. If present, use it.

One candidate found → use it, tell the user. Multiple plausible → list and ask.

### If none can be found

Stop before iteration 1 and tell the user:

> I couldn't find a verification command for this repo. The loop runs one between iterations to catch broken intermediate commits before they compound.
>
> Options:
> (a) **Add a `check` script** to `package.json` aggregating lint + typecheck + test.
> (b) **Document the command in CLAUDE.md** under a "Verification" section.
> (c) **Give me the command now** — for this run only, won't persist.
> (d) **Skip verification** — not recommended; risky on iteration 2+.

For (a) or (b), draft the addition first; persist as a separate atomic commit via the user's normal flow.

## Severity bands

Classify each `/review` finding:

- **Blocker** — breaks correctness, security, or build. Fix.
- **Major** — clear defect or convention violation, single right answer (e.g. missing null check on documented-non-null field). Fix.
- **Minor** — single obvious right answer, no behavior change (e.g. unused import, typo). Fix.
- **Nit** — style/preference, multiple valid choices. **Skip.**
- **Judgment call** — depends on intent, tradeoffs, or info not in the diff (architecture, naming, public-API contracts, behavior changes, anything needing a new test). **Stop and ask.**

When in doubt between Minor and Judgment call, treat as judgment.

## The loop

For iteration `i` in `1..3`:

1. Run `/review`.
2. Classify findings; show the grouped list to the user before acting.
3. **Any judgment calls** → stop, ask one by one. Don't silently skip.
4. **No Blocker/Major/Minor remain** → exit successfully (only nits, or nothing).
5. Address Blocker + Major + Minor. If a finding turns out more ambiguous while fixing it, stop and ask.
6. Run the verification command. If it fails, fix the failure and re-verify before committing. If you can't fix cleanly within the same logical change, surface as a judgment call.
7. Commit atomically (see below).
8. Track every change (file path + one-line) and commit (sha + message) in a running log.

If iteration 3 finishes with non-nit issues remaining, stop and report.

## Commit and push cadence

- **Atomic commits per project convention** (Conventional Commits in most projects — check `git log` or CLAUDE.md). Two unrelated findings = two commits.
- **Amend** only when the new edit is part of the same atomic change as the previous commit — verification fix-the-fix, a follow-up iteration completing an incomplete fix. Never across two separate findings.
- **Never amend a commit already pushed** (prior loop run or anything not made by this loop). Treat existing history as immutable.
- **Push once, at the end** of the loop. Single `git push`, no matter how the loop terminates. Never force-push.

## Final message format

```
## Review loop summary

**PR**: #<number> — <title>
**Iterations run**: <n>/3
**Exit reason**: <clean (only nits remain) | iteration cap reached | judgment call surfaced | precondition failed | build verification failed | no verification command>

### Changes made
- <file:line> — <one-line description>
- ...

### Commits in this review cycle
- <sha> — <commit message>          (new | amended)
- ...

### Remaining issues
- **Nits** (skipped): <count + one-line list>
- **Judgment calls** (need input): <list with the question, or "none">
- **Unaddressed non-nits** (only if cap hit): <list>

### Pushed
- <yes / no — if no, why>
```

List every commit produced, including ones later amended (mark as amended). If no changes were made, say so plainly rather than printing empty lists.

## Operating rules

- **Never resolve findings** by deleting tests, weakening assertions, or adding `eslint-disable` / `@ts-ignore`. Those are judgment calls.
- **Never broaden scope.** If `/review` flags untouched code, surface as a judgment call ("fix here, separate PR, or skip?") rather than silently expanding the diff.
- **Stay in the diff.** Clean up what this PR introduced, not the surrounding area.
- **If `/review` fails** or returns nothing parseable, stop and report.
