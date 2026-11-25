# Session Board: a small always-on-top card in the top-right corner of the screen
# showing which Claude sessions are working, recently active (nested by sidebar
# group and parent session), and upcoming reminders.
# Data comes from board.json, written every 20 s by the "session-board" Claude mod
# (%USERPROFILE%\.claude\mods\session-board), loaded in every Claude session.
# Run with: powershell.exe -STA -NoProfile -WindowStyle Hidden -File SessionBoard.ps1

param([string]$Snapshot = '', [switch]$SnapshotMinimized, [string]$SnapshotTheme = '', [double]$SnapshotZoom = 0)  # render the card to this PNG and exit (for checking the look)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace SessionBoard -Name Win32 -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct RECT { public int Left, Top, Right, Bottom; }
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out RECT r);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindow(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern System.IntPtr SetOwner(System.IntPtr h, int index, System.IntPtr owner);
'@

# One copy at a time.
$created = $false
$mutexName = $(if ($Snapshot) { 'Local\ClaudeSessionBoardSnapshot' } else { 'Local\ClaudeSessionBoard' })
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created)
if (-not $created) { return }

$DataFile = Join-Path $PSScriptRoot 'board.json'
$StateFile = Join-Path $PSScriptRoot 'window.json'
$Width = 312

# Two quiet palettes (neutral greys, one muted color per status); the card follows
# Claude's theme, or Windows' app mode when Claude is set to "System".
$Themes = @{
  Dark = @{
    Card = '#1C1C1E'; Ink = '#ECECEE'; Sub = '#A3A3A8'; Faint = '#7A7A80'
    Tile = '#001C1C1E'; TileHi = '#2A2A2D'; Line = '#4A4A4F'; Outline = '#2E2E31'; Divider = '#2A2A2D'
    Purple = '#8AA9CF'; Purple2 = '#C7C7CC'                 # link color; section titles
    Working = '#D9A441'; Done = '#7DA883'; Remind = '#8AA9CF'; RemindTile = '#001C1C1E'
    HeadTop = '#1C1C1E'; HeadBottom = '#1C1C1E'; HeadText = '#ECECEE'; HeadSub = '#7A7A80'
    Spark = '#ECECEE'; Pill = '#001C1C1E'; PillText = '#A3A3A8'
    Btn = '#001C1C1E'; BtnHi = '#2C2C2F'; BtnText = '#A3A3A8'; Edge = '#001C1C1E'
    ShadowOpacity = 0.30
  }
  Light = @{
    Card = '#FFFFFF'; Ink = '#1C1C1E'; Sub = '#5C5C62'; Faint = '#8A8A90'
    Tile = '#00FFFFFF'; TileHi = '#F0F0F2'; Line = '#C8C8CD'; Outline = '#E3E3E6'; Divider = '#EDEDEF'
    Purple = '#3F6A9E'; Purple2 = '#3A3A3F'
    Working = '#9A6A12'; Done = '#3F7148'; Remind = '#3F6A9E'; RemindTile = '#00FFFFFF'
    HeadTop = '#FFFFFF'; HeadBottom = '#FFFFFF'; HeadText = '#1C1C1E'; HeadSub = '#8A8A90'
    Spark = '#1C1C1E'; Pill = '#00FFFFFF'; PillText = '#5C5C62'
    Btn = '#00FFFFFF'; BtnHi = '#EDEDEF'; BtnText = '#5C5C62'; Edge = '#00FFFFFF'
    ShadowOpacity = 0.14
  }
}
$ChipSets = @{ Dark = @('x'); Light = @('x') }   # group tags are plain text now

# Match the Claude app's own theme (userThemeMode in its config.json: light, dark
# or system); for "system" or if it can't be read, follow Windows' app mode.
$ClaudeConfig = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Claude-Data') -Filter config.json -Recurse -Depth 1 -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty FullName

function Get-ThemeName {
  if ($SnapshotTheme) { return $(if ($SnapshotTheme -eq 'light') { 'Light' } else { 'Dark' }) }
  if ($ClaudeConfig) {
    try {
      $mode = ([System.IO.File]::ReadAllText($ClaudeConfig) | ConvertFrom-Json).userThemeMode
      if ($mode -eq 'light') { return 'Light' }
      if ($mode -eq 'dark') { return 'Dark' }
    } catch { }
  }
  try {
    $v = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme
    if ($v -eq 1) { 'Light' } else { 'Dark' }
  } catch { 'Dark' }
}
$script:themeName = Get-ThemeName
$C = $Themes[$script:themeName]
$Chips = $ChipSets[$script:themeName]

$Glyph = @{ # glyphs, as code points so the file's encoding can't garble them
  Dot = [string][char]0x00B7; Check = [string][char]0x2713; Bolt = [string][char]0x26A1
  Clock = [string][char]0x23F0; Down = [string][char]0x25BE; Right = [string][char]0x25B8
  Dash = [string][char]0x2013; Cross = [string][char]0x2715; Refresh = [string][char]0x21BB
  Elbow = [string][char]0x2570; Ring = [string][char]0x25CF; Ellipsis = [string][char]0x2026
}

function Brush([string]$hex) { [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) }
function Thk([double]$l, [double]$t, [double]$r, [double]$b) { [System.Windows.Thickness]::new($l, $t, $r, $b) }
function Rad([double]$a) { [System.Windows.CornerRadius]::new($a) }

function Chip([string]$name) {
  [uint32]$h = 0
  foreach ($ch in $name.ToCharArray()) { $h = [uint32](([uint64]$h * 31 + [int]$ch) % 4294967296) }
  $Chips[$h % $Chips.Count]
}

function Ago([double]$ms) {
  $s = [math]::Max(0, [math]::Round($ms / 1000))
  if ($s -lt 60) { return 'just now' }
  $m = [math]::Round($s / 60); if ($m -lt 60) { return "${m}m ago" }
  $h = [math]::Round($m / 60); if ($h -lt 48) { return "${h}h ago" }
  return "$([math]::Round($h / 24))d ago"
}

function Until([long]$atMs, [long]$nowMs) {
  $local = [DateTimeOffset]::FromUnixTimeMilliseconds($atMs).LocalDateTime
  $when = $local.ToString('ddd, MMM d ' + [char]0x00B7 + ' h:mm tt')
  $m = [math]::Round(($atMs - $nowMs) / 60000)
  if ($m -lt 0) { return "$when  (due)" }
  if ($m -lt 60) { return "$when  (in ${m}m)" }
  $h = [math]::Round($m / 60); if ($h -lt 48) { return "$when  (in ${h}h)" }
  return "$when  (in $([math]::Round($h / 24))d)"
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Sessions" Width="$Width" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="False" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        TextOptions.TextFormattingMode="Display">
  <Grid x:Name="Root" Margin="14">
    <Border x:Name="Card" CornerRadius="12" Background="$($C.Card)" BorderThickness="1">
      <Border.Effect>
        <DropShadowEffect BlurRadius="24" ShadowDepth="4" Direction="270" Opacity="0.35" Color="#000000"/>
      </Border.Effect>
      <StackPanel>
        <Border x:Name="Header" CornerRadius="12,12,0,0" Padding="12,5,5,5" BorderThickness="0,0,0,1">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
              <GradientStop Color="#2A2826" Offset="0"/>
              <GradientStop Color="#1E1D1B" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
          <StackPanel>
          <DockPanel LastChildFill="True">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top">
              <Button x:Name="ZoomOutBtn" Width="22" Height="22" ToolTip="Smaller (Ctrl + scroll also works)" Cursor="Hand" FontSize="10"/>
              <Button x:Name="ZoomInBtn" Width="22" Height="22" Margin="1,0,6,0" ToolTip="Larger (Ctrl + scroll also works)" Cursor="Hand"/>
              <Button x:Name="MinBtn" Width="22" Height="22" ToolTip="Minimize" Cursor="Hand"/>
              <Button x:Name="CloseBtn" Width="22" Height="22" Margin="3,0,0,0" ToolTip="Close" Cursor="Hand"/>
            </StackPanel>
            <TextBlock x:Name="Spark" DockPanel.Dock="Left" Text="" FontSize="1"
                       FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,8,0" Visibility="Collapsed"/>
            <StackPanel x:Name="TopHost" Orientation="Horizontal" VerticalAlignment="Center">
              <StackPanel x:Name="TitleBlock" VerticalAlignment="Center">
                <TextBlock x:Name="Title" FontSize="13.5" FontWeight="SemiBold" VerticalAlignment="Center"><Run x:Name="TitleSpark" Text=""/><Run x:Name="TitleText" Text="Claude Sessions"/><Run Text="  "/><Run x:Name="Subtitle" FontSize="11" FontWeight="Normal"/></TextBlock>
              </StackPanel>
            </StackPanel>
          </DockPanel>
          <StackPanel x:Name="BottomHost">
            <StackPanel x:Name="Pills" Orientation="Horizontal" Margin="0,3,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          </StackPanel>
        </Border>
        <StackPanel x:Name="Body" Margin="10,0,10,7"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
"@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$card = $window.FindName('Card')
$header = $window.FindName('Header')
$pills = $window.FindName('Pills')
$body = $window.FindName('Body')
$subtitle = $window.FindName('Subtitle')
$titleBlock = $window.FindName('TitleBlock')
$topHost = $window.FindName('TopHost')
$bottomHost = $window.FindName('BottomHost')
$spark = $window.FindName('Spark')
$minBtn = $window.FindName('MinBtn')
$closeBtn = $window.FindName('CloseBtn')
$zoomOutBtn = $window.FindName('ZoomOutBtn')
$zoomInBtn = $window.FindName('ZoomInBtn')
$root = $window.FindName('Root')

# Round, flat header buttons, styled from the current palette.
function Set-HeaderButtonStyle {
  $style = [Windows.Markup.XamlReader]::Parse(@"
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
  <Setter Property="Foreground" Value="$($C.BtnText)"/>
  <Setter Property="Background" Value="$($C.Btn)"/>
  <Setter Property="FontSize" Value="11"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="6">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="B" Property="Background" Value="$($C.BtnHi)"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
"@)
  $minBtn.Style = $style
  $closeBtn.Style = $style
  $zoomOutBtn.Style = $style
  $zoomInBtn.Style = $style
}

# Paint the parts drawn once (header, card, shadow); Render paints the rest.
function Set-ThemeChrome {
  $card.Background = Brush $C.Card
  $grad = New-Object System.Windows.Media.LinearGradientBrush
  $grad.StartPoint = [System.Windows.Point]::new(0, 0); $grad.EndPoint = [System.Windows.Point]::new(0, 1)
  $grad.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString($C.HeadTop), 0))
  $grad.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString($C.HeadBottom), 1))
  $header.Background = $grad
  $header.BorderBrush = Brush $C.Divider
  $card.BorderBrush = Brush $C.Outline
  $window.FindName('TitleSpark').Foreground = Brush $C.Spark
  $window.FindName('TitleText').Foreground = Brush $C.HeadText
  $subtitle.Foreground = Brush $C.HeadSub
  $spark.Foreground = Brush $C.Spark
  $fx = New-Object System.Windows.Media.Effects.DropShadowEffect
  $fx.BlurRadius = 18; $fx.ShadowDepth = 3; $fx.Direction = 270; $fx.Opacity = $C.ShadowOpacity
  $fx.Color = [System.Windows.Media.Colors]::Black
  $card.Effect = $fx
  Set-HeaderButtonStyle
}

function Update-Theme {
  $name = Get-ThemeName
  if ($name -eq $script:themeName) { return $false }
  $script:themeName = $name
  $script:C = $Themes[$name]; $script:Chips = $ChipSets[$name]
  Set-ThemeChrome
  $true
}

Set-ThemeChrome
$closeBtn.Content = $Glyph.Cross
$zoomOutBtn.Content = 'A'
$zoomInBtn.Content = 'A'
$zoomInBtn.FontSize = 14

$script:collapsed = $false
$script:zoom = 1.0   # whole-card scale: sizes and fonts together

# Scales the whole card (layout and text) and keeps the window wide enough for it.
function Set-Zoom([double]$z) {
  $z = [math]::Round([math]::Min(1.6, [math]::Max(0.8, $z)), 2)
  $script:zoom = $z
  $root.LayoutTransform = New-Object System.Windows.Media.ScaleTransform($z, $z)
  $window.Width = $Width * $z
  $zoomOutBtn.IsEnabled = $z -gt 0.8
  $zoomInBtn.IsEnabled = $z -lt 1.6
  Save-WindowState
}
$script:closedGroups = @{}
$script:hidden = @{}   # session id -> last activity (ms) when removed from Recent

function Save-WindowState {
  if ($Snapshot) { return }  # a snapshot run leaves the real window's state alone
  @{ collapsed = $script:collapsed; closedGroups = @($script:closedGroups.Keys); hidden = $script:hidden; zoom = $script:zoom } | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function New-Text([string]$text, [string]$color, [double]$size = 13, [string]$weight = 'Normal') {
  $t = New-Object System.Windows.Controls.TextBlock
  $t.Text = $text; $t.Foreground = Brush $color; $t.FontSize = $size; $t.FontWeight = $weight
  $t.TextTrimming = 'CharacterEllipsis'
  $t
}

# A count in the header: the number in its status color, the label in grey.
function New-Pill([string]$text, [string]$dotColor) {
  $t = New-Object System.Windows.Controls.TextBlock
  $t.FontSize = 11; $t.Margin = Thk 0 0 12 0; $t.VerticalAlignment = 'Center'
  $parts = $text -split ' ', 2
  $n = New-Object System.Windows.Documents.Run($parts[0]); $n.Foreground = Brush $dotColor; $n.FontWeight = 'SemiBold'
  [void]$t.Inlines.Add($n)
  if ($parts.Count -gt 1) { $l = New-Object System.Windows.Documents.Run(' ' + $parts[1]); $l.Foreground = Brush $C.PillText; [void]$t.Inlines.Add($l) }
  $t
}

# Status mark, a small vector: check = recent, filled dot = working,
# clock = reminder. No box around it.
function New-Box([string]$color, [string]$kind, [bool]$filled) {
  $mark = New-Object System.Windows.Shapes.Path
  $mark.Width = 12; $mark.Height = 12; $mark.VerticalAlignment = 'Center'; $mark.Margin = Thk 0 0 8 0
  $mark.Stroke = Brush $color; $mark.StrokeThickness = 1.5
  $mark.StrokeStartLineCap = 'Round'; $mark.StrokeEndLineCap = 'Round'; $mark.StrokeLineJoin = 'Round'
  switch ($kind) {
    { $_ -eq $Glyph.Clock } {
      $mark.Data = [System.Windows.Media.Geometry]::Parse('M 6,6 m -4.6,0 a 4.6,4.6 0 1,0 9.2,0 a 4.6,4.6 0 1,0 -9.2,0 M 6,3.6 L 6,6 L 7.7,7')
      $mark.VerticalAlignment = 'Top'; $mark.Margin = Thk 0 2 8 0
    }
    { $_ -eq $Glyph.Check } { $mark.Data = [System.Windows.Media.Geometry]::Parse('M 2.2,6.4 L 4.8,9 L 9.8,3.2') }
    default {
      $mark.Data = [System.Windows.Media.Geometry]::Parse('M 6,6 m -3,0 a 3,3 0 1,0 6,0 a 3,3 0 1,0 -6,0')
      $mark.Fill = Brush $color; $mark.StrokeThickness = 0
    }
  }
  $mark
}

# A section title; with a $key it collapses and expands on click (state kept).
function New-SectionTitle([string]$text, [string]$color, [int]$count, [string]$key = '') {
  $wrap = New-Object System.Windows.Controls.Border
  $wrap.Margin = Thk 0 8 0 2; $wrap.Padding = Thk 2 1 4 1; $wrap.CornerRadius = Rad 4
  $wrap.Background = Brush '#00000000'
  $p = New-Object System.Windows.Controls.StackPanel
  $p.Orientation = 'Horizontal'
  [void]$p.Children.Add((New-Text $text $C.Purple2 11.5 'SemiBold'))
  [void]$p.Children.Add((New-Text "  $count" $C.Faint 11))
  if ($key) {
    $open = -not $script:closedGroups.ContainsKey($key)
    $arrow = New-Text $(if ($open) { "  $($Glyph.Down)" } else { "  $($Glyph.Right)" }) $C.Faint 11 'Bold'
    $arrow.TextTrimming = 'None'
    [void]$p.Children.Add($arrow)
    $wrap.Cursor = 'Hand'; $wrap.Tag = $key
    $wrap.ToolTip = $(if ($open) { 'Collapse' } else { 'Expand' })
    $wrap.Add_MouseEnter({ $this.Background = Brush $C.TileHi })
    $wrap.Add_MouseLeave({ $this.Background = Brush '#00000000' })
    $wrap.Add_MouseLeftButtonUp({
        $k = [string]$this.Tag
        if ($script:closedGroups.ContainsKey($k)) { $script:closedGroups.Remove($k) } else { $script:closedGroups[$k] = $true }
        Save-WindowState; Render
      })
  }
  $wrap.Child = $p
  $wrap
}

function New-Empty([string]$text) {
  $t = New-Text $text $C.Faint 12
  $t.FontStyle = 'Italic'; $t.Margin = Thk 14 0 0 2
  $t
}

function New-GroupChip([string]$name) {
  $t = New-Text $name $C.Faint 10.5
  $t.Margin = Thk 0 0 8 0; $t.VerticalAlignment = 'Center'; $t.MaxWidth = 90
  $t
}

function New-SessionRow($s, [long]$now, [string]$state, [int]$depth, [bool]$showGroup) {
  $row = New-Object System.Windows.Controls.Border
  $row.CornerRadius = Rad 6
  $row.Padding = Thk 4 3 6 3
  $row.Margin = Thk (12 * $depth) 0 0 0
  $row.Background = Brush $C.Tile
  $row.Cursor = 'Hand'
  $row.ToolTip = "Open in Claude: $($s.title)"
  $row.Tag = [string]$s.link

  $dock = New-Object System.Windows.Controls.DockPanel
  $box = switch ($state) {
    'working' { New-Box $C.Working $Glyph.Ring $false }
    default { New-Box $C.Done $Glyph.Check $true }
  }
  [System.Windows.Controls.DockPanel]::SetDock($box, 'Left')
  [void]$dock.Children.Add($box)

  # One line: title (trimmed with ...) on the left, group tag and age on the right.
  $meta = New-Object System.Windows.Controls.StackPanel
  $meta.Orientation = 'Horizontal'; $meta.Margin = Thk 6 0 0 0; $meta.VerticalAlignment = 'Center'
  if ($showGroup -and $s.group) { [void]$meta.Children.Add((New-GroupChip $s.group)) }
  $age = Ago ($now - [double]$s.lastActivityAt)
  $age = $age -replace ' ago$', '' -replace '^just now$', 'now'
  $mt = New-Text $age $(if ($state -eq 'working') { $C.Working } else { $C.Faint }) 10.5
  $mt.VerticalAlignment = 'Center'; $mt.MinWidth = 22; $mt.TextAlignment = 'Right'
  [void]$meta.Children.Add($mt)
  [System.Windows.Controls.DockPanel]::SetDock($meta, 'Right')
  [void]$dock.Children.Add($meta)
  $col = New-Text $s.title $C.Ink 12
  $col.VerticalAlignment = 'Center'
  [void]$dock.Children.Add($col)
  $row.Child = $dock

  $row.Add_MouseEnter({ $this.Background = Brush $C.TileHi })
  $row.Add_MouseLeave({ $this.Background = Brush $C.Tile })
  $row.Add_MouseLeftButtonUp({ if ($this.Tag) { Start-Process $this.Tag } })

  # Right-click: open, or remove from Recent (it returns if the session is used again).
  $menu = New-Object System.Windows.Controls.ContextMenu
  $open = New-Object System.Windows.Controls.MenuItem
  $open.Header = 'Open session'; $open.Tag = [string]$s.link
  $open.Add_Click({ if ($this.Tag) { Start-Process $this.Tag } })
  [void]$menu.Items.Add($open)
  if ($state -ne 'working') {
    $rm = New-Object System.Windows.Controls.MenuItem
    $rm.Header = 'Remove from recent activity'
    $rm.Tag = @([string]$s.id, [double]$s.lastActivityAt)
    $rm.Add_Click({
        $script:hidden[[string]$this.Tag[0]] = [double]$this.Tag[1]
        Save-WindowState; Render
      })
    [void]$menu.Items.Add($rm)
  }
  # Hold the 5-second redraw while the menu is open, or it would vanish.
  $menu.Add_Opened({ $script:menuOpen = $true })
  $menu.Add_Closed({ $script:menuOpen = $false })
  $row.ContextMenu = $menu
  $row
}

# A child session sits under its parent with a curved elbow.
function New-ChildRow($s, [long]$now, [int]$depth) {
  $g = New-Object System.Windows.Controls.DockPanel
  $g.Margin = Thk (12 * $depth) 0 0 0
  # A curved connector: left and bottom edges of a box, its corner rounded.
  $elbow = New-Object System.Windows.Controls.Border
  $elbow.Width = 9; $elbow.Height = 12; $elbow.VerticalAlignment = 'Top'
  $elbow.BorderThickness = Thk 1 0 0 1; $elbow.BorderBrush = Brush $C.Line
  $elbow.CornerRadius = [System.Windows.CornerRadius]::new(0, 0, 0, 9)
  $elbow.Margin = Thk 9 0 2 0
  [System.Windows.Controls.DockPanel]::SetDock($elbow, 'Left')
  [void]$g.Children.Add($elbow)
  [void]$g.Children.Add((New-SessionRow $s $now $(if ($s.isRunning) { 'working' } else { 'done' }) 0 $true))
  $g
}

function New-GroupHeader([string]$name, [int]$count, [bool]$open) {
  $pair = Chip $name
  $h = New-Object System.Windows.Controls.Border
  $h.CornerRadius = Rad 8; $h.Padding = Thk 4 2 6 2; $h.Margin = Thk 0 1 0 2
  $h.Background = Brush '#00000000'; $h.Cursor = 'Hand'; $h.Tag = $name
  $h.ToolTip = $(if ($open) { 'Collapse' } else { 'Expand' })
  $p = New-Object System.Windows.Controls.StackPanel; $p.Orientation = 'Horizontal'
  $arrow = New-Text $(if ($open) { $Glyph.Down } else { $Glyph.Right }) $C.Purple 12 'Bold'
  $arrow.Width = 14; $arrow.TextTrimming = 'None'
  [void]$p.Children.Add($arrow)
  $sq = New-Object System.Windows.Controls.Border
  $sq.Width = 10; $sq.Height = 10; $sq.CornerRadius = Rad 3; $sq.Background = Brush $pair[1]
  $sq.Margin = Thk 2 0 8 0; $sq.VerticalAlignment = 'Center'
  [void]$p.Children.Add($sq)
  [void]$p.Children.Add((New-Text $name $C.Ink 11.5 'Bold'))
  [void]$p.Children.Add((New-Text "  $count" $C.Faint 11 'SemiBold'))
  $h.Child = $p
  $h.Add_MouseEnter({ $this.Background = Brush $C.Tile })
  $h.Add_MouseLeave({ $this.Background = Brush '#00000000' })
  $h.Add_MouseLeftButtonUp({
      $k = [string]$this.Tag
      if ($script:closedGroups.ContainsKey($k)) { $script:closedGroups.Remove($k) } else { $script:closedGroups[$k] = $true }
      Save-WindowState; Render
    })
  $h
}

function Render {
  $pills.Children.Clear(); $body.Children.Clear()
  $nowMs = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
  $subtitle.Text = $(if ($script:collapsed) { '' } else { (Get-Date).ToString('ddd, MMM d') })

  $data = $null
  if (Test-Path -LiteralPath $DataFile) {
    try { $data = [System.IO.File]::ReadAllText($DataFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { }
  }
  if (-not $data) {
    if (-not $script:collapsed) {
      $t = New-Text 'Waiting for data. Open any Claude session.' $C.Sub 12.5
      $t.TextWrapping = 'Wrap'; $t.TextTrimming = 'None'
      [void]$body.Children.Add($t)
    }
    return
  }

  $all = @($data.sessions)
  $byId = @{}; foreach ($s in $all) { $byId[[string]$s.id] = $s }
  $working = @($all | Where-Object { $_.isRunning } | Sort-Object { - [double]$_.lastActivityAt })
  # Forget removals of sessions that have been used since.
  foreach ($id in @($script:hidden.Keys)) {
    $x = $byId[$id]
    if (-not $x -or [double]$x.lastActivityAt -gt $script:hidden[$id]) { $script:hidden.Remove($id) }
  }
  $recent = @($all | Where-Object { -not $_.isRunning -and -not $script:hidden.ContainsKey([string]$_.id) -and ($nowMs - [double]$_.lastActivityAt) -lt 86400000 } |
      Sort-Object { - [double]$_.lastActivityAt } | Select-Object -First 12)
  $reminders = @($data.reminders | Where-Object { $_ } | Sort-Object { [double]$_.nextRunAt })

  if ($script:collapsed) {
    [void]$pills.Children.Add((New-Pill "$($working.Count) working" $C.Working))
    [void]$pills.Children.Add((New-Pill "$($recent.Count) recent" $C.Done))
  }
  # Expanded: no count row in the header; each section title already shows its count.

  if ($script:collapsed) { return }

  # Reminders.
  [void]$body.Children.Add((New-SectionTitle 'Reminders' $C.Remind $reminders.Count 'section:reminders'))
  $showReminders = -not $script:closedGroups.ContainsKey('section:reminders')
  if ($showReminders -and $reminders.Count -eq 0) { [void]$body.Children.Add((New-Empty 'Nothing scheduled.')) }
  foreach ($r in $(if ($showReminders) { $reminders } else { @() })) {
    $row = New-Object System.Windows.Controls.Border
    $row.CornerRadius = Rad 6; $row.Padding = Thk 4 3 6 3; $row.Margin = Thk 0 0 0 0
    $row.Background = Brush $C.RemindTile
    $dock = New-Object System.Windows.Controls.DockPanel
    $box = New-Box $C.Remind $Glyph.Clock $false
    [System.Windows.Controls.DockPanel]::SetDock($box, 'Left')
    [void]$dock.Children.Add($box)
    $col = New-Object System.Windows.Controls.StackPanel
    $tt = New-Text $r.title $C.Ink 12; $tt.TextWrapping = 'Wrap'; $tt.TextTrimming = 'None'
    [void]$col.Children.Add($tt)
    $wt = New-Text (Until ([long]$r.nextRunAt) $nowMs) $C.Faint 10.5; $wt.Margin = Thk 0 0 0 0
    [void]$col.Children.Add($wt)
    [void]$dock.Children.Add($col)
    $row.Child = $dock
    [void]$body.Children.Add($row)
  }

  # Working now: flat, each with its group chip.
  [void]$body.Children.Add((New-SectionTitle 'Working now' $C.Working $working.Count 'section:working'))
  $showWorking = -not $script:closedGroups.ContainsKey('section:working')
  if ($showWorking -and $working.Count -eq 0) { [void]$body.Children.Add((New-Empty 'Nothing running right now.')) }
  foreach ($s in $(if ($showWorking) { $working } else { @() })) { [void]$body.Children.Add((New-SessionRow $s $nowMs 'working' 0 $true)) }

  # Recently active: nested by sidebar group, then by parent session.
  [void]$body.Children.Add((New-SectionTitle 'Recent' $C.Done $recent.Count 'section:recent'))
  $showRecent = -not $script:closedGroups.ContainsKey('section:recent')
  if ($showRecent -and $recent.Count -eq 0) { [void]$body.Children.Add((New-Empty 'No sessions in the last day.')) }
  $recentIds = @{}; foreach ($s in $recent) { $recentIds[[string]$s.id] = $true }
  # Most recent first; a child session is drawn under its parent.
  foreach ($s in $(if ($showRecent) { $recent } else { @() })) {
    $parent = [string]$s.parentId
    if ($parent -and $recentIds.ContainsKey($parent)) { continue }
    [void]$body.Children.Add((New-SessionRow $s $nowMs 'done' 0 $true))
    foreach ($k in @($recent | Where-Object { [string]$_.parentId -eq [string]$s.id })) {
      [void]$body.Children.Add((New-ChildRow $k $nowMs 0))
    }
  }

  # Footer: freshness on the left, a round refresh button on the right.
  $foot = New-Object System.Windows.Controls.DockPanel
  $foot.Margin = Thk 2 4 0 0
  $btn = New-Object System.Windows.Controls.Border
  # Quiet round button, dark like the rows, with a vector refresh arrow in the accent color.
  $btn.Width = 26; $btn.Height = 26; $btn.CornerRadius = Rad 13
  $btn.Background = Brush '#00000000'; $btn.BorderThickness = Thk 0 0 0 0
  $btn.Cursor = 'Hand'; $btn.ToolTip = 'Refresh'
  # Bold arc plus a filled arrowhead, so it reads clearly at this size.
  $icon = New-Object System.Windows.Controls.Grid
  $icon.Width = 18; $icon.Height = 18; $icon.HorizontalAlignment = 'Center'; $icon.VerticalAlignment = 'Center'
  $arc = New-Object System.Windows.Shapes.Path
  $arc.Data = [System.Windows.Media.Geometry]::Parse('M 13.76,6.25 A 5.5,5.5 0 1 1 8.6,3.5')
  $arc.Stroke = Brush $C.Sub; $arc.StrokeThickness = 2; $arc.StrokeStartLineCap = 'Round'; $arc.StrokeEndLineCap = 'Flat'
  $head = New-Object System.Windows.Shapes.Path
  $head.Data = [System.Windows.Media.Geometry]::Parse('M 8.2,0.6 L 12.2,3.5 L 8.2,6.4 Z')
  $head.Fill = Brush $C.Sub
  [void]$icon.Children.Add($arc); [void]$icon.Children.Add($head)
  # Small button: the 18-unit icon scaled down to 12 px.
  $vb = New-Object System.Windows.Controls.Viewbox
  $vb.Width = 12; $vb.Height = 12; $vb.Child = $icon
  $btn.Width = 22; $btn.Height = 22; $btn.CornerRadius = Rad 6
  $btn.Child = $vb
  $btn.Add_MouseEnter({ $this.Background = Brush $C.TileHi })
  $btn.Add_MouseLeave({ $this.Background = Brush '#00000000' })
  $btn.Add_MouseLeftButtonUp({ Render })
  [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
  [void]$foot.Children.Add($btn)
  $age = $nowMs - [double]$data.updatedAt
  # One short line: freshness, plus an inline "Restore" link when rows were removed.
  $msg = $(if ($age -gt 120000) { "Paused $(Ago $age) $($Glyph.Dot) no Claude session open" } else { "Updated $(Ago $age)" })
  $ft = New-Object System.Windows.Controls.StackPanel
  $ft.Orientation = 'Horizontal'; $ft.VerticalAlignment = 'Center'
  [void]$ft.Children.Add((New-Text $msg $C.Faint 10))
  if ($script:hidden.Count -gt 0) {
    [void]$ft.Children.Add((New-Text "  $($Glyph.Dot)  " $C.Faint 10))
    $undo = New-Text "Restore $($script:hidden.Count) removed" $C.Purple 10
    $undo.Cursor = 'Hand'; $undo.TextDecorations = [System.Windows.TextDecorations]::Underline
    $undo.ToolTip = 'Show the sessions you removed from Recent'
    $undo.Add_MouseLeftButtonUp({ $script:hidden.Clear(); Save-WindowState; Render })
    [void]$ft.Children.Add($undo)
  }
  [void]$foot.Children.Add($ft)
  [void]$body.Children.Add($foot)
}

function Set-Collapsed([bool]$value) {
  $script:collapsed = $value
  # Same width and same header row in both states, so the - button never moves.
  # Minimized hides the body and shows the counts in place of the date.
  $body.Visibility = $(if ($value) { 'Collapsed' } else { 'Visible' })
  $header.CornerRadius = $(if ($value) { Rad 12 } else { [System.Windows.CornerRadius]::new(12, 12, 0, 0) })
  $card.CornerRadius = Rad 12
  $header.Padding = Thk 12 5 5 5
  $header.BorderThickness = $(if ($value) { Thk 0 0 0 0 } else { Thk 0 0 0 1 })
  $titleBlock.Visibility = 'Visible'
  $spark.Visibility = 'Collapsed'
  $closeBtn.Visibility = 'Visible'
  # Size buttons only when expanded, so the minimized bar has room for both counts
  # (- and x are right-aligned, so they keep their place).
  $zoomOutBtn.Visibility = $(if ($value) { 'Collapsed' } else { 'Visible' })
  $zoomInBtn.Visibility = $(if ($value) { 'Collapsed' } else { 'Visible' })
  $subtitle.Text = ''
  $pills.Margin = Thk 10 0 0 0
  if ($bottomHost.Children.Contains($pills)) { $bottomHost.Children.Remove($pills); [void]$topHost.Children.Add($pills) }
  $pills.Visibility = $(if ($value) { 'Visible' } else { 'Collapsed' })
  $bottomHost.Visibility = 'Collapsed'
  $window.SizeToContent = 'Height'; $window.Width = $Width * $script:zoom
  $minBtn.Content = $(if ($value) { $Glyph.Down } else { $Glyph.Dash })
  $minBtn.ToolTip = $(if ($value) { 'Expand' } else { 'Minimize' })
  Render
  Save-WindowState
}

$saved = $null
if (Test-Path -LiteralPath $StateFile) { try { $saved = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json } catch { } }
if ($saved -and $saved.closedGroups) { foreach ($g in @($saved.closedGroups)) { $script:closedGroups[[string]$g] = $true } }
if ($saved -and $saved.hidden) { foreach ($pr in $saved.hidden.PSObject.Properties) { $script:hidden[$pr.Name] = [double]$pr.Value } }

# Pin the card to the Claude desktop window: its top-right corner, owned by it
# (so it stays above Claude but not above other apps), hidden when Claude is
# minimized or closed.
$script:claudeHwnd = [IntPtr]::Zero
$script:ownedBy = [IntPtr]::Zero
$TopOffset = 52    # below Claude's title bar, in device pixels
$RightOffset = 18

function Find-Claude {
  $p = Get-Process -Name claude -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.Path -like '*WindowsApps*Claude*' } |
    Select-Object -First 1
  if ($p) { $p.MainWindowHandle } else { [IntPtr]::Zero }
}

function Update-Position {
  if ($script:claudeHwnd -eq [IntPtr]::Zero -or -not [SessionBoard.Win32]::IsWindow($script:claudeHwnd)) {
    $script:claudeHwnd = Find-Claude
  }
  $h = $script:claudeHwnd
  if ($h -eq [IntPtr]::Zero -or [SessionBoard.Win32]::IsIconic($h) -or -not [SessionBoard.Win32]::IsWindowVisible($h)) {
    if ($window.Visibility -ne 'Hidden') { $window.Visibility = 'Hidden' }
    return
  }
  $me = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
  if ($me -ne [IntPtr]::Zero -and $script:ownedBy -ne $h) {
    [void][SessionBoard.Win32]::SetOwner($me, -8, $h)   # GWLP_HWNDPARENT: owner window
    $script:ownedBy = $h
  }
  $r = New-Object SessionBoard.Win32+RECT
  if (-not [SessionBoard.Win32]::GetWindowRect($h, [ref]$r)) { return }
  $src = [System.Windows.PresentationSource]::FromVisual($window)
  $k = if ($src) { $src.CompositionTarget.TransformFromDevice.M11 } else { 1.0 }
  # The card sits inside a 14-DIP margin that holds its shadow.
  $left = ($r.Right - $RightOffset) * $k - $window.ActualWidth + 14
  $top = ($r.Top + $TopOffset) * $k - 14
  if ([math]::Abs($window.Left - $left) -gt 0.5) { $window.Left = $left }
  if ([math]::Abs($window.Top - $top) -gt 0.5) { $window.Top = $top }
  if ($window.Visibility -ne 'Visible') { $window.Visibility = 'Visible' }
}

$follow = New-Object System.Windows.Threading.DispatcherTimer
$follow.Interval = [TimeSpan]::FromMilliseconds(120)
$follow.Add_Tick({ try { Update-Position } catch { } })
if ($Snapshot) {
  $window.Left = -10000; $window.Top = 0; $window.ShowActivated = $false
  $window.Add_ContentRendered({
      $window.UpdateLayout()
      $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth, [int]$window.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
      $bmp.Render($window.Content)
      $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
      $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
      $fs = [System.IO.File]::Create($Snapshot); $enc.Save($fs); $fs.Close()
      $window.Close()
    })
} else {
  $window.Add_ContentRendered({ Update-Position; $follow.Start() })
}

$minBtn.Add_Click({ Set-Collapsed (-not $script:collapsed) })
$zoomOutBtn.Add_Click({ Set-Zoom ($script:zoom - 0.1) })
$zoomInBtn.Add_Click({ Set-Zoom ($script:zoom + 0.1) })
# Ctrl + mouse wheel over the card also changes the size.
$window.Add_PreviewMouseWheel({
    param($sender, $e)
    if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) {
      Set-Zoom ($script:zoom + $(if ($e.Delta -gt 0) { 0.1 } else { -0.1 }))
      $e.Handled = $true
    }
  })
$closeBtn.Add_Click({ $window.Close() })

# Closing fires only for a real close (the close button, Alt+F4, a snapshot).
# When Claude replaces or closes its main window, Windows destroys this owned
# window without Closing, and ShowDialog never returns: the process would linger
# with no window and hold the single-copy mutex, so nothing could reopen the card.
# So on Closed, always end the process; if nobody asked to close, start a fresh
# copy first, which finds Claude's new window (or waits for Claude to reopen).
$script:closeRequested = $false
$window.Add_Closing({ $script:closeRequested = $true })
$window.Add_Closed({
    try { $follow.Stop(); $timer.Stop() } catch { }
    try { $mutex.ReleaseMutex() } catch { }
    if (-not $Snapshot -and -not $script:closeRequested) {
      $vbs = Join-Path $PSScriptRoot 'SessionBoard.vbs'
      if (Test-Path -LiteralPath $vbs) { Start-Process wscript.exe -ArgumentList "`"$vbs`"" }
    }
    [Environment]::Exit(0)
  })

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$script:menuOpen = $false
$timer.Add_Tick({ if (-not $script:menuOpen) { try { [void](Update-Theme); Render } catch { } } })
$timer.Start()

Set-Zoom $(if ($SnapshotZoom -gt 0) { $SnapshotZoom } elseif ($saved -and $saved.zoom) { [double]$saved.zoom } else { 1.0 })
Set-Collapsed $(if ($Snapshot) { [bool]$SnapshotMinimized } else { [bool]($saved -and $saved.collapsed) })
[void]$window.ShowDialog()
try { $mutex.ReleaseMutex() } catch { }

