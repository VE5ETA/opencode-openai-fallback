# Troubleshooting

## Plugin does not load

Run:

```powershell
opencode debug config
```

Check that `./plugin/openai-auto-fallback.mjs` appears in the plugin list.

If it does not, rerun:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Quit and restart opencode after changing config.

## Wrong browser account during login

OpenAI's browser flow may reuse the currently signed-in ChatGPT account.

Fixes:

- Sign out of ChatGPT in that browser.
- Use a private browser window.
- Switch browser profiles temporarily.
- Rerun the matching command, such as `ocai login ps`.

## Session history looks split

The helper should force all profiles to share:

```text
~/.local/share/opencode/opencode.db
```

Check paths with:

```powershell
ocpp debug paths
ocps debug paths
```

Both should report the same `OPENCODE_DB` value.

## Fallback does not trigger

Fallback only triggers on limit-like failures, such as HTTP 429, `usage limit`, `rate limit`, `too many requests`, or quota messages.

It does not hide normal provider failures, malformed requests, network problems, or auth failures.

For the TUI, restart opencode after installing. For `run` commands, use plain `opencode run ...` or `ocai run ...`; explicit profile commands like `ocps run ...` stay on that profile.

## PowerShell functions are missing

Open a new PowerShell window. If they are still missing, check your profile path:

```powershell
$PROFILE.CurrentUserCurrentHost
```

Rerun the installer if needed.

## Disable fallback temporarily

Set this environment variable before starting opencode:

```powershell
$env:OPENCODE_OPENAI_AUTO_FALLBACK = "0"
opencode
```

Remove the variable or open a fresh shell to enable fallback again.
