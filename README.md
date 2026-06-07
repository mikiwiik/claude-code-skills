# miki-claude-code-skills

Personal Claude Code skills, version-controlled so they follow me across machines.

Each skill lives in its own `miki-*` directory at the repo root. The `miki-`
prefix marks them as personal (vs. project-level skills committed inside a
specific repo, or skills installed by plugins) and makes them safe to
`miki-*`-glob from `~/.claude/skills/` without touching anything else.

## Install

Clone, then run the install script:

```bash
git clone git@github.com:mikiwiik/claude-code-skills.git ~/repos/miki-claude-code-skills
~/repos/miki-claude-code-skills/install.sh
```

The script symlinks every `miki-*` directory in this repo into
`~/.claude/skills/`. It's idempotent — re-run it after pulling new skills.
It refuses to overwrite a real (non-symlink) entry already at the target path,
so it's safe to run on a machine that already has personal skills set up.

To uninstall a skill: `rm ~/.claude/skills/miki-<name>` (only removes the
symlink; the source in this repo is untouched).

## Skills

- **`miki-review-loop`** — pre-self-review loop. Iteratively runs `/review`
  on the current PR and addresses obvious issues until only minor nits
  remain (max 3 iterations). Surfaces judgment calls; atomic commits;
  pushes once at the end.
- **`miki-rebase-reflect`** — rebase the current branch onto the latest
  default branch, resolving conflicts in-place (mechanical fixes
  directly, judgment calls escalated to Miki). After the rebase, reflects
  on the nature of what landed and which incoming files intersect this
  branch's diff. Always rebases (never merges); hands off only on
  unexpected git state; never pushes.
- **`miki-wrap-up`** — end-of-session sweep. Surfaces anything outstanding
  in the current conversation and working tree (todos, uncommitted /
  unpushed work, open PRs, background agents, conversational follow-ups,
  stale refs noticed) or confirms there's nothing left. Recommends only;
  never acts.

## Adding a new skill

1. Create `miki-<name>/SKILL.md` in this repo with the standard skill
   frontmatter (`name: miki-<name>`, `description:`, `user-invocable:`).
2. Run `./install.sh` — it'll add the symlink for the new skill.
3. Commit and push.

## Why a separate repo (vs. dotfiles)

Keeps the install footprint small for machines that don't need everything
in a full dotfiles repo (e.g. a fresh dev box). One-line install, opt-in
per machine.

## License

Released under the [MIT License](LICENSE) — use freely, no warranty,
keep the copyright notice.
