# Removes Claude Sessions: stops the card, deletes its two folders and the Start menu
# shortcut, and takes the mod folder back out of CLAUDE_CODE_PLUGIN_DIRS in settings.json.
# Run:  powershell -ExecutionPolicy Bypass -File .\uninstall.ps1

$ErrorActionPreference = 'Stop'
$claudeHome = Join-Path $env:USERPROFILE '.claude'
$appDir = Join-Path $claudeHome 'session-board'
$modDir = Join-Path $claudeHome 'mods\session-board'
$settingsPath = Join-Path $claudeHome 'settings.json'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*SessionBoard.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

foreach ($d in $appDir, $modDir) { if (Test-Path $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
$lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Claude Sessions.lnk'
if (Test-Path $lnk) { Remove-Item -LiteralPath $lnk -Force }

if (Test-Path $settingsPath) {
  $settings = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
  if ($settings.env -and ($settings.env.PSObject.Properties.Name -contains 'CLAUDE_CODE_PLUGIN_DIRS')) {
    $dirs = @($settings.env.CLAUDE_CODE_PLUGIN_DIRS -split ';' | Where-Object { $_ -and $_ -ne $modDir })
    if ($dirs.Count) { $settings.env.CLAUDE_CODE_PLUGIN_DIRS = $dirs -join ';' }
    else { $settings.env.PSObject.Properties.Remove('CLAUDE_CODE_PLUGIN_DIRS') }
    if (-not @($settings.env.PSObject.Properties).Count) { $settings.PSObject.Properties.Remove('env') }
    [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 50), (New-Object System.Text.UTF8Encoding $false))
  }
}
Write-Host 'Claude Sessions removed. Claude sessions started from now on no longer load the mod.'
