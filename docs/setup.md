# Setup

This setup is Windows-first. The plugin is JavaScript, but the installer and command shortcuts are PowerShell.

## Requirements

- opencode installed, or Node.js/Scoop/Chocolatey available so the installer can install opencode.
- Node.js available as `node` for the test script.
- Windows PowerShell 5.1 or newer.
- One or more ChatGPT workspaces you are allowed to use.

## Install

One-command install:

```powershell
irm https://raw.githubusercontent.com/VE5ETA/opencode-openai-fallback/main/install.ps1 | iex
```

The installer checks for opencode first. If opencode is missing, it tries `npm install -g opencode-ai`, then Scoop, then Chocolatey.

From a cloned repo:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

If you want to keep plain `opencode` untouched and use only `ocai`/`ocpp`/`ocps`/`ocsp`/`ocss`, run:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoOpencodeFunction
```

The installer copies:

- `plugin/openai-auto-fallback.mjs` to `~/.config/opencode/plugin/openai-auto-fallback.mjs`
- `scripts/opencode-openai.ps1` to `~/.config/opencode/opencode-openai.ps1`

It also registers the plugin in `~/.config/opencode/opencode.jsonc` and appends PowerShell functions if `ocai` is not already defined.

When an existing opencode config is updated, the installer writes a timestamped backup next to it first.

Open a new PowerShell window after installing.

## Additional machines

Run the same installer on each machine and log in normally on that machine. Do not copy OAuth tokens, `auth.json`, or `opencode.db` between machines.

## Login

Login only to the profiles you want to use:

```powershell
ocai login pp
ocai login ps
ocai login sp
ocai login ss
```

Use the matching browser account and workspace during each login.

If the browser keeps selecting the wrong account, sign out of ChatGPT in that browser, use a private window, or switch browser profiles for the login step.

## Daily use

Start opencode normally:

```powershell
opencode
```

Run one-shot prompts:

```powershell
opencode run "summarize this repo"
```

Use a specific profile when needed:

```powershell
ocpp
ocps run "fix the tests"
ocss run "review this branch"
```

Implicit `opencode run ...` uses fallback order:

```text
pp -> ps -> sp -> ss
```

The interactive TUI starts from `pp` by default. When the plugin sees a usage-limit response, it retries through the remaining authenticated profiles.

## Verify install

Check opencode config:

```powershell
opencode debug config
```

Look for:

```text
openai-auto-fallback.mjs
```

Run local tests from the repo:

```powershell
node .\tests\test-openai-auto-fallback.mjs
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\test-openai-wrapper.ps1
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\test-install.ps1
```
