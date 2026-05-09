---
name: miki-review-loop
description: Miki's personal pre-self-review loop. Iteratively runs /review on the current PR and addresses obvious issues until only minor nits remain or 3 iterations have run. Surfaces judgment calls back to the user, makes atomic commits per project convention, pushes once at the end. Invoke when the user says "/miki-review-loop", "loop the review", "iterate on the review", or similar after a PR has been created.
argument-hint: "Optional PR number; if omitted, derived from current branch"
user-invocable: true
disable-model-invocation: false
---

# miki-review-loop

## What this does

Automates the "review → address → re-review" cycle Miki runs on his own PRs before reading them himself. The loop terminates when no actionable non-nit issues remain, when 3 iterations have run, or when a judgment call surfaces. Always ends with a written summary listing every change made and every commit produced.

## Preconditions

Before starting, verify in order:

1. **PR identification.**
   - **If the user passed a PR number as an argument** (e.g. `/miki-review-loop 84`): use that number directly. Run `gh pr view <number> --json number,title,headRefName,baseRefName,state` to fetch its details, then **announce** the PR being processed in a single line — e.g. `Processing PR #84 — "<title>" on <head> → <base>` — and proceed without asking for confirmation. The user already named the PR; re-asking is friction.
   - **If no PR number was given**: derive it from the current branch via `gh pr view --json number,title,headRefName,baseRefName,state`. Echo the PR number and title back and **ask the user to confirm** before proceeding. Do not start the loop on an unconfirmed PR. If multiple PRs match or detection is ambiguous, list candidates and ask which one.
   - **If no PR exists or it's not OPEN** (in either case): stop and tell the user.
2. **Clean working tree.** `git status --porcelain` must be empty. If not, stop — don't mix the loop's commits with unrelated work.
3. **Not on main.** Current branch must not be `main` / `master`. If it is, stop.
4. **Verification command available** (see "Verification command" section below). If not, follow the prompt-to-create flow before starting iteration 1.

If any precondition fails, report which one and exit without running `/review`.

## Verification command (per repo)

Between iterations, before committing fixes, the loop runs the repo's verification command to confirm the build still passes. Different repos use different commands, so detect on each run.

### Detection (in order)

1. **`package.json` scripts** — try, in priority order: `check`, `verify`, `validate`, `ci`, `test`. The first one that exists wins (`check` typically aggregates lint+typecheck+test, hence top priority).
2. **Other stacks** — if the repo isn't Node:
   - `Cargo.toml` present → `cargo check && cargo test`
   - `Makefile` with a `check` target → `make check`
   - `pyproject.toml` with a `[tool.<runner>]` section → look for an obvious `check`/`test` task
3. **CLAUDE.md** — grep for a documented verification or build-check command (e.g. a "Verification" section or a fenced block tagged as the canonical check). If present, use it.

If exactly one candidate is found, use it and tell the user which one. If multiple plausible candidates exist (e.g. both `check` and `test`), list them and ask which one.

### If no verification command can be found

Stop before starting iteration 1 and tell the user:

> I couldn't find a verification command for this repo. The loop runs one between iterations to confirm fixes don't break the build before committing.
>
> Options:
> (a) **Add a `check` script to `package.json`** that aggregates lint + typecheck + test. I can suggest the exact line based on what's installed and what scripts already exist.
> (b) **Document the command in CLAUDE.md** under a "Verification" section, if you already have a command but it's not discoverable.
> (c) **Give me the command now** — I'll use it for this run only and won't persist it.
> (d) **Skip verification this run** — not recommended; risky on iteration 2+ because broken intermediate commits compound.

If (a), draft the script line and show it to the user before writing it. If (b), draft the CLAUDE.md addition and show it before writing. Either way, persist via the user's normal commit flow — that addition is its own atomic commit, separate from the review loop.

## Severity bands

Classify every finding `/review` produces into one of:

- **Blocker** — breaks correctness, security, or build (e.g. wrong logic, leaked secret, type error). Fix.
- **Major** — clear defect or violation of an established project convention with a single right answer (e.g. missing null check on a documented-non-null field, wrong import path). Fix.
- **Minor** — improvement with a single obvious right answer that doesn't change behavior (e.g. unused import, dead variable, obvious typo in a comment). Fix.
- **Nit** — style/preference/polish where reasonable people disagree, or where the suggestion is one of several valid choices. **Skip.**
- **Judgment call** — anything where the right fix depends on intent, tradeoffs, or information not in the diff (architecture decisions, "should this be extracted?", "is this naming clearer?", behavior changes, anything touching public API contracts, anything that would require a new test to validate). **Stop the loop and ask the user.**

When in doubt between Minor and Judgment call, treat it as a judgment call. The skill's job is to clear obvious work, not to make decisions on the user's behalf.

## The loop

For iteration `i` in `1..3`:

1. **Run `/review`** via the Skill tool.
2. **Classify** every finding into the bands above. Show the user the classification before doing anything: a short list grouped by band.
3. **If any judgment calls exist**: stop the loop. Ask the user how to proceed on each, one by one. Do not silently skip them and continue — the whole point of stopping is so the human can weigh in.
4. **If no Blocker / Major / Minor remain**: exit the loop successfully (only nits left, or nothing).
5. **Address Blocker + Major + Minor findings.** Make the edits. If a finding turns out to be more ambiguous than it looked once you start fixing it, stop and ask — don't force a fix.
6. **Verify the build still passes** by running the verification command. If it fails, fix the failure and re-verify before committing. If you can't fix it cleanly within the same logical change, surface it as a judgment call and stop.
7. **Commit atomically** per project convention (see "Commit and push cadence" below).
8. **Track** every change made in a running log (file path + one-line description of what changed and why) and every commit produced (sha + message).

If iteration 3 finishes and `/review` still finds non-nit issues, stop and report. Don't silently continue past the cap.

## Commit and push cadence

- **Atomic commits per project convention.** One logical change per commit, using the project's commit-message style (most projects in this account use Conventional Commits — check `git log` for recent style, or CLAUDE.md). If iteration 1 fixes two unrelated findings, that's two commits.
- **Amending is allowed when the new edit is clearly part of the same atomic change** as the previous commit. Examples:
  - Verification failed after the commit, and the follow-up edit is the fix-the-fix for the same finding → amend.
  - A second `/review` iteration flags an incomplete fix to a finding from iteration 1 → amend the iteration-1 commit.
  - Two separate findings, both addressed in iteration 2 → two new commits, no amending across them.
- **Never amend a commit that was already pushed** to the remote in a prior loop run or by something other than this loop. If the loop sees commits on the branch it didn't make, treat the existing history as immutable.
- **Push once, at the end of the loop**, regardless of how it terminates (clean exit, cap hit, judgment call surfaced). Single `git push` at the end. Do not push between iterations — the user is reviewing the final state, not intermediate ones.
- **Never force-push.** If history surgery seems needed for recovery, stop and surface it to the user.

## Final message format

Always end with a summary, regardless of how the loop terminated. Sections:

```
## Review loop summary

**PR**: #<number> — <title>
**Iterations run**: <n>/3
**Exit reason**: <one of: clean (only nits remain), iteration cap reached, judgment call surfaced, precondition failed, build verification failed, no verification command>

### Changes made
- <file:line> — <one-line description>
- <file:line> — <one-line description>
- ...

### Commits in this review cycle
- <sha> — <commit message>          (new)
- <sha> — <commit message>          (amended)
- ...

### Remaining issues
- **Nits** (skipped intentionally): <count, with a one-line list>
- **Judgment calls** (need your input): <list with the question for each, or "none">
- **Unaddressed non-nits** (only if cap was hit): <list>

### Pushed
- <yes / no — if no, why>
```

List **every** commit produced in this cycle, including ones that were later amended (mark them as amended). If no changes were made (e.g. clean on first iteration), say so explicitly rather than printing empty lists.

## Operating rules

- **Never resolve `/review` findings by deleting tests, weakening assertions, or adding eslint-disable / @ts-ignore.** Those are judgment calls — surface them.
- **Never broaden scope.** If `/review` flags a problem in code the PR didn't touch, note it as a judgment call ("review found <X> in untouched code — fix here, separate PR, or skip?") rather than silently expanding the diff.
- **Stay in the diff.** The loop's job is to clean up what this PR introduced, not to refactor the surrounding area.
- **If `/review` itself fails or returns nothing parseable**, stop and report — don't guess what it would have said.
