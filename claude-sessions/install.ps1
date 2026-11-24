# Installs Claude Sessions for the current Windows user.
#
#   1. Copies the card (app\SessionBoard.ps1) to   %USERPROFILE%\.claude\session-board\
#   2. Copies the Claude mod (mod\session-board) to %USERPROFILE%\.claude\mods\session-board\
#   3. Adds that mod folder to CLAUDE_CODE_PLUGIN_DIRS in %USERPROFILE%\.claude\settings.json
#      (a backup of settings.json is saved next to it first), so every Claude session loads it
#   4. Adds a "Claude Sessions" Start menu shortcut and starts the card
#
# Nothing is sent anywhere and nothing runs as administrator. Undo with uninstall.ps1.
# Run from the folder this file is in:  powershell -ExecutionPolicy Bypass -File .\install.ps1

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$claudeHome = Join-Path $env:USERPROFILE '.claude'
$appDir = Join-Path $claudeHome 'session-board'
$modDir = Join-Path $claudeHome 'mods\session-board'
$settingsPath = Join-Path $claudeHome 'settings.json'

if (-not (Test-Path (Join-Path $src 'app\SessionBoard.ps1')) -or -not (Test-Path (Join-Path $src 'mod\session-board\.claude-plugin\plugin.json'))) {
  throw "Run install.ps1 from the claude-sessions folder (it needs the app and mod folders next to it)."
}

Write-Host 'Installing Claude Sessions...'

# Stop a running copy so its file can be replaced.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*SessionBoard.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 1-2. Files.
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
Copy-Item -LiteralPath (Join-Path $src 'app\SessionBoard.ps1') -Destination $appDir -Force
if (Test-Path $modDir) { Remove-Item -LiteralPath $modDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Split-Path $modDir) | Out-Null
Copy-Item -LiteralPath (Join-Path $src 'mod\session-board') -Destination (Split-Path $modDir) -Recurse -Force
Write-Host "  card   -> $appDir"
Write-Host "  mod    -> $modDir"

# 3. settings.json: add the mod folder to env.CLAUDE_CODE_PLUGIN_DIRS, keeping everything else.
$settings = [pscustomobject]@{}
if (Test-Path $settingsPath) {
  $raw = [System.IO.File]::ReadAllText($settingsPath)
  if ($raw.Trim()) { $settings = $raw | ConvertFrom-Json }
  Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak-claude-sessions" -Force
}
if (-not ($settings.PSObject.Properties.Name -contains 'env')) {
  $settings | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{})
}
$dirs = @()
if ($settings.env.PSObject.Properties.Name -contains 'CLAUDE_CODE_PLUGIN_DIRS') {
  $dirs = @($settings.env.CLAUDE_CODE_PLUGIN_DIRS -split ';' | Where-Object { $_ })
}
if ($dirs -notcontains $modDir) { $dirs += $modDir }
$settings.env | Add-Member -NotePropertyName CLAUDE_CODE_PLUGIN_DIRS -NotePropertyValue ($dirs -join ';') -Force
$json = $settings | ConvertTo-Json -Depth 50
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding $false))
Write-Host "  settings.json: CLAUDE_CODE_PLUGIN_DIRS includes the mod (backup: settings.json.bak-claude-sessions)"

# 4. Start menu shortcut, with the Claude app's icon when it can be found.
$lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Claude Sessions.lnk'
$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($lnk)
$sc.TargetPath = 'powershell.exe'
$sc.Arguments = "-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$appDir\SessionBoard.ps1`""
$sc.WindowStyle = 7
$sc.Description = 'Show the Claude Sessions card on the Claude window'
$claudeExe = Get-Process -Name claude -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -like '*WindowsApps*Claude*' -or $_.MainWindowHandle -ne [IntPtr]::Zero } |
  Select-Object -First 1 -ExpandProperty Path
if ($claudeExe) { $sc.IconLocation = "$claudeExe,0" }
$sc.Save()
Write-Host '  Start menu: "Claude Sessions"'

Start-Process powershell.exe -ArgumentList '-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$appDir\SessionBoard.ps1`""

Write-Host ''
Write-Host 'Done. The card sits at the top right of the Claude desktop window.'
Write-Host 'It fills in once a NEW Claude session starts (sessions open now do not load the mod yet).'
Write-Host 'In any new session, /sessions brings the card back if you close it.'
