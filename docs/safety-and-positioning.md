# Safety and positioning

Use direct claims that describe what the project does without implying abuse.

## Approved wording

- Stack your own workspaces. Keep opencode moving.
- Add up to four of your own authenticated ChatGPT workspaces.
- Get up to 4x more opencode headroom.
- Automatic fallback when one workspace hits a usage limit.
- Works with personal, Plus, Pro, Business, or Team workspaces you are allowed to use.
- Availability and usage limits vary by account and region.

## Avoid wording

- Unlimited GPT.
- Bypass OpenAI limits.
- Free GPT forever.
- Share one account with everyone.

## Public framing

The useful story is simple: some people have multiple legitimate ChatGPT workspaces, but opencode stops at the first workspace that hits a limit. This repo routes across the workspaces the user owns.

Keep repeating the ownership qualifier: your own authenticated workspaces.

## Security notes

- Never publish `auth.json`.
- Never publish `opencode.db`.
- Never paste OAuth refresh tokens into issues, screenshots, posts, or docs.
- Re-login on each machine instead of copying tokens.
- Use `scripts/verify-no-secrets.ps1` before publishing.
