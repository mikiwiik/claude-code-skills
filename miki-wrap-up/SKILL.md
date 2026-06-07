---
name: miki-wrap-up
description: Miki's session wrap-up check. Surveys the current conversation and working tree for anything outstanding before ending the session — open todos, uncommitted changes, unpushed commits, open PRs that haven't merged, background agents still running, follow-ups the conversation flagged but never closed, and stale references noticed but not fixed. Produces a short punch list, or confirms there's nothing left. Recommends only; never acts. Invoke when the user says "/miki-wrap-up", "did we have anything else to do in this conversation?", "anything else to do?", "are we done?", "what's left?", or similar end-of-session checks.
user-invocable: true
disable-model-invocation: false
---

# miki-wrap-up

## What this does

Reviews the conversation and working tree for outstanding work before the session ends. Produces a structured punch list, or confirms nothing's left. **Recommends, never acts** — if something needs doing, the user (or the next turn) does it.

## The sweep

Six categories. For each: a short check, then a one-line conclusion. **Skip empty categories silently** — they only appear when they have content.

### 1. Task list

`TaskList` items not in `completed` status. Distinguish `in_progress` (mid-flight) from `pending` (queued). Skip if empty.

### 2. Working tree

`git status --porcelain` and `git status -sb`. Surface uncommitted changes related to this session, untracked in-flight files (not random OS cruft), and ahead/behind counts vs. remote. Skip if clean and in sync.

### 3. PRs touched this session

For each PR mentioned in the conversation, `gh pr view <n> --json number,title,state,mergeable,mergeStateStatus`. Surface anything still actionable:

- `OPEN` + `CONFLICTING` → user action needed.
- `OPEN` + `BLOCKED` or awaiting approval → waiting on review.
- `OPEN` + `MERGEABLE` without `--auto` → could enable auto-merge.

PRs that merged or closed during the session aren't loose ends.

### 4. Background agents and processes

Any `Agent` runs or background `Bash` invocations still running — surface with description and runtime. The user may want to wait, kill, or follow up.

### 5. Flagged follow-ups in the conversation

Re-read the conversation for things either party flagged as *"out of scope for this PR"*, *"follow-up"*, *"later"*, *"I'll do that next"*, *"separate PR"*, etc. — that were not subsequently closed. List as bullets with enough context (what + pointer to the exchange). Skip if none.

### 6. Stale references noticed but not fixed

CLAUDE.md describing outdated workflow, TODO.md entries that should have been closed, comments pointing at moved code, docs lagging code — only if the conversation surfaced them. Skip if none.

## Output format

Lead with a headline:

- *"Nothing outstanding."* — every category empty.
- *"N loose end(s):"* — N is the total across fired categories.

Then only the fired categories. One line per entry where possible.

```
## Wrap-up sweep

<headline>

### <Category that fired>
- <entry>
- <entry>

### <Next category>
- ...
```

If nothing's outstanding, the whole response is one sentence. **Don't fill the page** with empty-category stubs — that defeats the point of a quick check.

## Operating rules

- **Never act.** No commits, pushes, edits, killing agents, merging PRs. Report only.
- **Quick over thorough.** A wrap-up check, not an audit. If a category would take more than a few seconds (e.g. ten PRs to fetch), summarize what'd need to be checked rather than checking all of it.
- **Conversation is authoritative for "flagged follow-ups".** Don't grep `TODO.md` whole-repo — only conversation-raised items.
- **One-shot.** One report per invocation. No loops, no follow-up questions.
