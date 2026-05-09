# TODO

Central prioritized list of work for this repo. Anything worth doing but
not yet done lives here.

We don't currently use GitHub Issues — this file is the single source of
truth for the backlog.

## What goes here

- **New skills / new capabilities** — skills not yet written, or features
  to add to existing skills.
- **Bugs** — broken behavior in shipped skills.
- **Chores** — maintenance: dependency bumps, doc cleanups, repo
  scaffolding.
- **Ideas** — half-formed thoughts worth not losing. Move to one of the
  sections above when they firm up.

Items live under the heading for the skill they affect. Repo-wide items
(install script, README, conventions) go under **Repo**. Order within a
section is rough priority — nudge up or down as priorities shift.

## miki-review-loop

- **Skill body caching at session start.** Edits to `SKILL.md` body don't
  take effect on the next invocation in the same session. Claude Code
  appears to snapshot SKILL.md at session start, so the in-session prompt
  goes stale even though the on-disk file (via the symlink) is current.
  Workaround: restart the session. Worth documenting in the README, or
  revisiting if Claude Code's behavior changes. Frontmatter `description`
  changes have always required a restart; this finding extends that to
  the SKILL.md body too.

- **Cross-repo invocation isn't handled.** When the skill is invoked from
  a session whose cwd is repo A but with a PR number that lives in repo
  B, the preconditions (clean working tree, not on main, verification
  command lookup) all run against the wrong repo. The skill should
  either derive the target repo from the PR's GitHub metadata and
  switch to its local checkout, or reject cross-repo invocation
  explicitly.

- **Push cadence vs `/review` needing current state.** The skill says
  "push once at the end of the loop", but `/review` reads from GitHub
  via `gh pr diff`. Iteration 2's `/review` therefore can't see
  iteration 1's unpushed commits, forcing a push between iterations.
  Either drop "push once" (each iteration's commits are already meant
  to be reviewable atomic units, so pushing them mid-loop isn't
  worse), or find a way to run `/review` against a local diff
  (`git diff <base>...HEAD`) instead of through `gh`.
