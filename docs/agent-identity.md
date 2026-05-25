# Agent Identity Setup

Use a separate GitHub account (e.g. `<your-handle>-agent`) for AI/automation activity, so its commits, PRs, and comments are visually distinct from yours and the credential has its own independent revocation path.

## Why a classic PAT, not fine-grained?

Fine-grained PATs can only access resources **owned by the token issuer's own account** (or organizations the issuer belongs to). If your agent account is a *collaborator* on a repo owned by your personal account, a fine-grained PAT issued by the agent cannot reach that repo — repository visibility (public/private) does not change this.

For personal-account repos with a separate agent collaborator, you need a **classic PAT**. Move the repo to an organization both accounts belong to if you later want fine-grained scoping.

## Setup

1. **Create the agent account** on GitHub with its own email address. Enable 2FA.
2. **Invite it as a collaborator** on the repo (Settings → Collaborators → Add people). Accept the invite from the agent account.
3. **(Optional) Make the repo public.** This lets you use the narrower `public_repo` scope in step 4. Audit history for secrets first — the change is effectively irreversible (forks may persist).
4. **Sign in as the agent account** and create a classic PAT at <https://github.com/settings/tokens>:
   - **Note**: `<repo-name> agent access`
   - **Expiration**: 90 days
   - **Scopes**:
     - `public_repo` if the repo is public, or `repo` if private
     - `workflow` only if the agent will edit files under `.github/workflows/`
     - Leave everything else unchecked
5. **Configure local auth** as the agent:
   ```bash
   gh auth login --hostname github.com --git-protocol https --with-token
   # paste the ghp_… token, then Ctrl-D
   gh auth setup-git
   ```

## Storing the token

- **Recommended**: keyring via `gh auth login --with-token`. No env var, no shell-history exposure.
- **Acceptable**: `GH_TOKEN` env var, but only via `direnv` (per-project `.envrc`) or a sourced secrets file with `chmod 600`. Avoid putting it in `~/.zshrc` — it overrides the keyring globally and appears in every process's environment.
- `GH_TOKEN` takes precedence over the keyring; set it only when you intentionally want to act as the agent in that shell.

## Rotation

- Rotate every 90 days; calendar a reminder.
- Revoke the old token at <https://github.com/settings/tokens> after rotation succeeds.
- If a token ever appears in logs, pasted output, or a public commit, revoke immediately and re-issue.
