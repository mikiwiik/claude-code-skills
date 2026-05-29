---
name: miki-wrap-up
description: Miki's session wrap-up check. Surveys the current conversation and working tree for anything outstanding before ending the session — open todos, uncommitted changes, unpushed commits, open PRs that haven't merged, background agents still running, follow-ups the conversation flagged but never closed, and stale references noticed but not fixed. Produces a short punch list, or confirms there's nothing left. Recommends only; never acts. Invoke when the user says "/miki-wrap-up", "did we have anything else to do in this conversation?", "anything else to do?", "are we done?", "what's left?", or similar end-of-session checks.
user-invocable: true
disable-model-invocation: false
---

# miki-wrap-up

## What this does

Reviews the current conversation and the working tree for outstanding work — the things that should reasonably be closed before this session ends. Produces a structured punch list, or confirms that nothing's left.

This skill **recommends, never acts.** If something needs doing, the user (or the next conversational turn) does it. The skill's job is to surface what's left, not to clear it.

## The sweep

Six categories. For each: a short check, then a one-line conclusion. **Skip empty categories silently** — they only appear when they have content. The goal is a quick scannable answer, not a filled-in template.

### 1. Task list

If `TaskList` has any tasks not in `completed` status, surface them. Distinguish `in_progress` (something is mid-flight) from `pending` (queued but not started). If the task list is empty or everything is completed, skip the section.

### 2. Working tree

Run `git status --porcelain` and `git status -sb` (the latter for ahead/behind counts). Surface:

- Uncommitted changes (staged or unstaged) that relate to work done this session.
- Untracked files that look like in-flight work — files mentioned in the conversation, not random editor / OS artifacts.
- Current branch ahead of its remote (unpushed commits).
- Current branch behind its remote (someone else pushed; may want to pull).

If the tree is clean and the branch is in sync: skip the section.

### 3. PRs touched this session

For any PR number that came up in the conversation (created, reviewed, or commented on), check current state with `gh pr view <n> --json number,title,state,mergeable,mergeStateStatus`. Surface anything still actionable:

- `OPEN` + `CONFLICTING` → user action needed.
- `OPEN` + `BLOCKED` or awaiting approval → waiting on review.
- `OPEN` + `MERGEABLE` without `--auto` enabled → could enable auto-merge.

PRs that merged or closed during the session are not loose ends — skip them.

### 4. Background agents and processes

If any `Agent` runs or background `Bash` invocations from this session are still running, surface them with their description and how long they've been running. The user may want to wait for them, kill them, or follow up on their results.

### 5. Flagged follow-ups in the conversation

This is the qualitative one. Re-read the conversation for things either party flagged as *"out of scope for this PR"*, *"follow-up"*, *"later"*, *"I'll do that next"*, *"worth a separate PR"*, etc. — that were **not** subsequently closed in the same session.

List them as a short bullet list with enough context to know what each is — what the follow-up actually is, plus a pointer to the exchange that flagged it. Skip if nothing was flagged.

### 6. Stale references noticed but not fixed

If the conversation discovered stale references that weren't fixed — CLAUDE.md describing an outdated workflow, TODO.md entries that should have been closed, comments pointing at moved code, docs lagging behind code changes — surface them. Skip if none came up.

## Output format

Lead with a one-line headline:

- *"Nothing outstanding."* if every category is empty.
- *"N loose end(s):"* otherwise, where N is the total count across all fired categories.

Then only the categories that have content. Keep each entry to one line where possible.

```
## Wrap-up sweep

<one-line headline>

### <Category that fired>
- <one-line entry>
- <one-line entry>

### <Next category that fired>
- ...
```

If nothing's outstanding, the entire response is one sentence. **Do not** fill the page with *"no tasks, clean tree, no PRs, no background work, nothing flagged, no stale refs"* — that defeats the point of a quick check.

## Operating rules

- **Never act.** Don't commit, push, edit files, kill agents, or merge PRs. The skill reports; the user decides.
- **Quick over thorough.** This is a wrap-up check, not an audit. If checking a category would take more than a few seconds (e.g. fetching ten PRs), summarize what'd need to be checked rather than checking all of it.
- **Conversation context is authoritative for "flagged follow-ups".** Don't grep `TODO.md` for the whole repo — only flag items the conversation itself raised and didn't close.
- **Skip empty categories silently.** Sections only appear when they have content.
- **One-shot.** This skill produces one report per invocation. Don't loop, don't ask follow-up questions. If the user wants to act on a loose end, they'll say so in the next turn.
