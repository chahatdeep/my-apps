# Claude Sessions

A small card that sits at the **top right of the Claude desktop app** and shows, at a glance:

- **Upcoming reminders**: your scheduled Claude tasks, with the date and a countdown
- **Working now**: which Claude sessions are busy right now
- **Recently active**: sessions from the last 24 hours, with their sidebar group, and sessions started from another session nested under it

Click a session to jump to it. Right-click a recent session to hide it from the list (it comes back when you use it again).

| Dark | Light | Minimized |
| --- | --- | --- |
| ![Dark](screenshots/dark.png) | ![Light](screenshots/light.png) | ![Minimized](screenshots/minimized.png) |

- Follows Claude's theme (light or dark; "System" follows Windows) and switches live.
- Stays attached to the Claude window: it moves with it, sits above Claude only (not above other apps), and hides when Claude is minimized.
- **–** shrinks it to a slim pill with the three counts; each section folds with its ▾.
- If you close it, it comes back the next time you open a Claude session, with `/sessions`, or from the Start menu ("Claude Sessions").

## Install: paste this into Claude

Needs Windows 10/11 and the Claude desktop app (Code tab). Paste this into a Claude Code session:

```text
Install "Claude Sessions" for me from https://github.com/chahatdeep/my-apps/tree/main/claude-sessions.
Download https://github.com/chahatdeep/my-apps/archive/refs/heads/main.zip into a new empty folder and extract it.
Read claude-sessions/README.md, claude-sessions/install.ps1 and the files it installs so you know what they do,
then run it with: powershell -ExecutionPolicy Bypass -File "<that folder>\my-apps-main\claude-sessions\install.ps1"
Tell me when it's done and what it changed.
```

Then open a **new** Claude session. The card fills in once a session that loads the add-on is open.

### Or install by hand

Download the repository (Code → Download ZIP), extract it, and in PowerShell run:

```powershell
powershell -ExecutionPolicy Bypass -File .\my-apps-main\claude-sessions\install.ps1
```

## What it installs

| What | Where |
| --- | --- |
| The card (one PowerShell + WPF script) | `%USERPROFILE%\.claude\session-board\SessionBoard.ps1` |
| A Claude Code mod that writes the card's data every 20 s | `%USERPROFILE%\.claude\mods\session-board\` |
| One setting so every Claude session loads that mod | `env.CLAUDE_CODE_PLUGIN_DIRS` in `%USERPROFILE%\.claude\settings.json` (a backup is saved as `settings.json.bak-claude-sessions`) |
| A Start menu shortcut | "Claude Sessions" |

How it works: in each Claude session, the mod asks Claude's own session and scheduled-task tools for the list of sessions and reminders, and writes it to `board.json` next to the card. The card reads that file. Everything stays on your computer; nothing is sent anywhere, and nothing runs as administrator.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\my-apps-main\claude-sessions\uninstall.ps1
```

It stops the card, removes both folders and the shortcut, and takes the mod back out of `settings.json`.

## Notes

- Claude only reports whether a session is running or not, so a session waiting for your answer shows under **Recently active**, not as a separate state.
- Sessions that were already open when you installed don't load the mod. New ones do.

## License

[MIT](LICENSE). This license covers the `claude-sessions` folder only.
