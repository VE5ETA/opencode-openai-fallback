# opencode-openai-fallback

Stack your own workspaces. Keep opencode moving.

![opencode-openai-fallback social card](assets/social-card.svg)

Connect up to four of your own authenticated ChatGPT personal, Plus, Pro, Business, or Team workspaces and get up to 4x more opencode headroom when one workspace hits `usage limit reached`.

This is for people who already use opencode with OpenAI ChatGPT auth and have more than one legitimate workspace available. It does not create accounts, share tokens, remove OpenAI limits, or promise unlimited usage.

## One-command install

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/VE5ETA/opencode-openai-fallback/main/install.ps1 | iex
```

The installer also installs opencode if it is missing. It tries `npm install -g opencode-ai` first, then Scoop, then Chocolatey.

If you do not want plain `opencode` to call the fallback wrapper, use this version:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/VE5ETA/opencode-openai-fallback/main/install.ps1))) -NoOpencodeFunction
```

## Why this exists

opencode sessions are easy to interrupt when a single OpenAI workspace hits a usage limit. The usual fix is manual: stop, switch accounts or workspaces, restart, and hope your session history still lines up.

This repo packages a cleaner setup:

- Separate OpenAI auth stores for four workspace profiles.
- One shared opencode session database so `resume` stays useful.
- Automatic fallback order: `pp -> ps -> sp -> ss`.
- In-process fallback for the interactive opencode TUI.
- CLI fallback for `opencode run ...`.

If you have more than one legitimate ChatGPT workspace, this helps opencode use those workspaces without manual switching. Availability, limits, and account eligibility vary by account and region.

## Quick start

If you cloned this repo, run:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

If you do not want the installer to make plain `opencode` call the wrapper, run:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoOpencodeFunction
```

Open a new PowerShell window, then login to each workspace you want to use:

```powershell
ocai login pp
ocai login ps
ocai login sp
ocai login ss
```

Use opencode normally:

```powershell
opencode
opencode run "fix the tests"
```

Profile shortcuts:

```powershell
ocpp  # primary personal
ocps  # primary shared
ocsp  # secondary personal
ocss  # secondary shared
ocraw # raw opencode.cmd without the wrapper
```

Quit and restart opencode after installing. opencode loads config and plugins at startup.

## How it works

The PowerShell helper sets one auth directory per profile:

```text
pp = primary personal
ps = primary shared
sp = secondary personal
ss = secondary shared
```

Each profile gets its own OpenAI OAuth login. Sessions stay shared through one `opencode.db`, so switching profiles does not split your opencode history.

The plugin watches OpenAI OAuth requests inside opencode. If a response is a clear usage-limit, rate-limit, or quota response, it retries the same request with the next authenticated profile.

## Safety boundaries

Use this with your own accounts and workspaces.

Do not publish tokens. Do not copy `auth.json` between machines you do not control. Do not use this to share access with other people. Do not describe this as unlimited usage or a way to bypass limits.

Good public wording:

- "up to 4x more opencode headroom"
- "your own authenticated workspaces"
- "automatic fallback when one workspace hits a limit"
- "availability and limits vary"

Bad public wording:

- "unlimited GPT"
- "bypass OpenAI limits"
- "free exploit"

## Verify

```powershell
node .\tests\test-openai-auto-fallback.mjs
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\test-openai-wrapper.ps1
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\test-install.ps1
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-no-secrets.ps1
```

## Docs

- `docs/setup.md`: installation and login flow.
- `docs/troubleshooting.md`: common failures and fixes.
- `docs/safety-and-positioning.md`: launch wording and boundaries.

## License

MIT
