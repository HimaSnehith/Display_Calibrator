# ==============================================================================
# DisplayTune GUI - Studio Display Color Controller
# Direct Hardware GDI Pipeline with Studio Reference Presets
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "DisplayEngine.ps1")

# Create Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "DisplayTune - Studio Display Color Controller"
$form.Size = New-Object System.Drawing.Size(1000, 760)
$form.MinimumSize = New-Object System.Drawing.Size(920, 660)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$form.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 245)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true

# Header Bar
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Location = New-Object System.Drawing.Point(16, 12)
$headerPanel.Size = New-Object System.Drawing.Size(952, 60)
$headerPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(22, 25, 34)
$headerPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($headerPanel)

$info = Get-DisplayHardwareInfo
$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = ("Custom Color Controls | " + $info.PanelModel + " (" + $info.Resolution + " @ " + $info.RefreshRate + ")")
$lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(245, 75, 75)
$lblHeader.Location = New-Object System.Drawing.Point(15, 9)
$lblHeader.AutoSize = $true
$headerPanel.Controls.Add($lblHeader)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Direct Hardware LUT Pipeline | Type value or drag slider | Double-click label to reset item"
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(155, 165, 185)
$lblSub.Location = New-Object System.Drawing.Point(15, 32)
$lblSub.AutoSize = $true
$headerPanel.Controls.Add($lblSub)

# Reset Button in Header (Top Right)
$btnResetTop = New-Object System.Windows.Forms.Button
$btnResetTop.Text = "Reset to Default"
$btnResetTop.Location = New-Object System.Drawing.Point(795, 13)
$btnResetTop.Size = New-Object System.Drawing.Size(140, 34)
$btnResetTop.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnResetTop.BackColor = [System.Drawing.Color]::FromArgb(40, 44, 56)
$btnResetTop.ForeColor = [System.Drawing.Color]::White
$btnResetTop.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnResetTop.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 66, 82)
$btnResetTop.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnResetTop.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnResetTop.Add_Click({ Reset-AllToDefaults })
$headerPanel.Controls.Add($btnResetTop)

# Preset Bar (Quick Studio Reference Switchers)
$presetPanel = New-Object System.Windows.Forms.Panel
$presetPanel.Location = New-Object System.Drawing.Point(16, 78)
$presetPanel.Size = New-Object System.Drawing.Size(952, 44)
$presetPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$presetPanel.BackColor = [System.Drawing.Color]::FromArgb(18, 20, 28)
$presetPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($presetPanel)

$lblPresetTitle = New-Object System.Windows.Forms.Label
$lblPresetTitle.Text = "Studio Presets:"
$lblPresetTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblPresetTitle.ForeColor = [System.Drawing.Color]::FromArgb(160, 170, 195)
$lblPresetTitle.Location = New-Object System.Drawing.Point(12, 12)
$lblPresetTitle.AutoSize = $true
$presetPanel.Controls.Add($lblPresetTitle)

# Left Column: Sliders Container (Scrollable)
$panelScroll = New-Object System.Windows.Forms.Panel
$panelScroll.Location = New-Object System.Drawing.Point(16, 130)
$panelScroll.Size = New-Object System.Drawing.Size(630, 570)
$panelScroll.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$panelScroll.AutoScroll = $true
$form.Controls.Add($panelScroll)

# Right Column: Live Pattern Box
$grpPreview = New-Object System.Windows.Forms.GroupBox
$grpPreview.Text = " Live Calibration Pattern "
$grpPreview.Location = New-Object System.Drawing.Point(660, 130)
$grpPreview.Size = New-Object System.Drawing.Size(308, 570)
$grpPreview.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$grpPreview.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
$form.Controls.Add($grpPreview)

# Global slider storage
$global:Sliders = @{}
$global:CurrentY = 10

function Commit-AmdSliderText {
    param($m)
    if (-not $m) { return }
    $raw = $m.TextBox.Text -replace '[^\d\.\-]', ''
    $parsed = 0.0
    if ([double]::TryParse($raw, [ref]$parsed)) {
        $parsed = [Math]::Max($m.Min, [Math]::Min($m.Max, $parsed))
        $m.TrackBar.Value = [int][Math]::Round($parsed * $m.Scale)
        $m.TextBox.Text = ($parsed.ToString($m.Format) + $m.Unit)
        Update-FromAmdSliders
    } else {
        $current = [double]$m.TrackBar.Value / $m.Scale
        $m.TextBox.Text = ($current.ToString($m.Format) + $m.Unit)
    }
}

function Add-AmdSlider {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Name,
        [string]$Label,
        [double]$Min,
        [double]$Max,
        [double]$Default,
        [double]$Scale = 1.0,
        [string]$Unit = "",
        [string]$Format = "F0"
    )

    $rowPanel = New-Object System.Windows.Forms.Panel
    $rowPanel.Location = New-Object System.Drawing.Point(10, $global:CurrentY)
    $rowPanel.Size = New-Object System.Drawing.Size(585, 54)
    $rowPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $rowPanel.BackColor = [System.Drawing.Color]::FromArgb(22, 25, 34)
    $rowPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $Parent.Controls.Add($rowPanel)

    # Label on Left (Double-click resets to default)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point(12, 16)
    $lbl.Size = New-Object System.Drawing.Size(165, 22)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(235, 240, 250)
    $lbl.Cursor = [System.Windows.Forms.Cursors]::Hand
    $rowPanel.Controls.Add($lbl)

    # Value Box in Middle (Editable: on Enter or Blur updates)
    $txtVal = New-Object System.Windows.Forms.TextBox
    $txtVal.Text = ($Default.ToString($Format) + $Unit)
    $txtVal.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $txtVal.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
    $txtVal.Location = New-Object System.Drawing.Point(182, 14)
    $txtVal.Size = New-Object System.Drawing.Size(80, 24)
    $txtVal.BackColor = [System.Drawing.Color]::FromArgb(14, 16, 22)
    $txtVal.ForeColor = [System.Drawing.Color]::FromArgb(240, 245, 255)
    $txtVal.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $rowPanel.Controls.Add($txtVal)

    # Trackbar on Right
    $trk = New-Object System.Windows.Forms.TrackBar
    $trk.Location = New-Object System.Drawing.Point(272, 12)
    $trk.Size = New-Object System.Drawing.Size(298, 30)
    $trk.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $trk.Minimum = [int]($Min * $Scale)
    $trk.Maximum = [int]($Max * $Scale)
    $trk.Value = [int]($Default * $Scale)
    $trk.TickStyle = [System.Windows.Forms.TickStyle]::None
    $trk.BackColor = [System.Drawing.Color]::FromArgb(22, 25, 34)

    $meta = @{
        TextBox = $txtVal
        TrackBar = $trk
        Scale   = $Scale
        Unit    = $Unit
        Format  = $Format
        Name    = $Name
        Min     = $Min
        Max     = $Max
        Default = $Default
        Panel   = $rowPanel
    }
    $trk.Tag = $meta
    $txtVal.Tag = $meta
    $lbl.Tag = $meta

    # Trackbar scroll handler
    $trk.Add_Scroll({
        $m = $this.Tag
        $val = [double]$this.Value / [double]$m.Scale
        $m.TextBox.Text = ($val.ToString($m.Format) + $m.Unit)
        Update-FromAmdSliders
    })

    $txtVal.Add_Enter({
        $this.SelectAll()
    })

    $txtVal.Add_Leave({
        Commit-AmdSliderText $this.Tag
    })

    $txtVal.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            Commit-AmdSliderText $this.Tag
            if ($this.Tag.Panel) { $this.Tag.Panel.Focus() }
        }
    })

    # Double click label resets that single slider to default
    $lbl.Add_DoubleClick({
        $m = $this.Tag
        $m.TrackBar.Value = [int]($m.Default * $m.Scale)
        $m.TextBox.Text = ($m.Default.ToString($m.Format) + $m.Unit)
        Update-FromAmdSliders
    })

    $rowPanel.Controls.Add($trk)

    $global:Sliders[$Name] = @{
        TrackBar = $trk
        TextBox  = $txtVal
        Scale    = $Scale
        Unit     = $Unit
        Format   = $Format
        Default  = $Default
        Min      = $Min
        Max      = $Max
    }

    $global:CurrentY += 60
}

# --- SECTION 1: THE CORE 4 CONTROLS ---
$lblCoreHeader = New-Object System.Windows.Forms.Label
$lblCoreHeader.Text = "PRIMARY DISPLAY CONTROLS"
$lblCoreHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblCoreHeader.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)
$lblCoreHeader.Location = New-Object System.Drawing.Point(10, $global:CurrentY)
$lblCoreHeader.Size = New-Object System.Drawing.Size(300, 18)
$panelScroll.Controls.Add($lblCoreHeader)
$global:CurrentY += 22

Add-AmdSlider -Parent $panelScroll -Name "ColorTemp"  -Label "Color Temperature" -Min 4000 -Max 10000 -Default 6500 -Scale 1.0 -Unit " K" -Format "F0"
Add-AmdSlider -Parent $panelScroll -Name "Brightness" -Label "Brightness"        -Min -100 -Max 100  -Default 0    -Scale 1.0 -Unit ""   -Format "F0"
Add-AmdSlider -Parent $panelScroll -Name "Contrast"   -Label "Contrast"          -Min 0    -Max 200  -Default 100  -Scale 1.0 -Unit ""   -Format "F0"
Add-AmdSlider -Parent $panelScroll -Name "Saturation" -Label "Saturation"        -Min 0    -Max 200  -Default 100  -Scale 1.0 -Unit ""   -Format "F0"

$global:CurrentY += 10

# --- SECTION 2: ADVANCED CONTROLS ---
$lblAdvHeader = New-Object System.Windows.Forms.Label
$lblAdvHeader.Text = "ADVANCED PRECISION TUNING"
$lblAdvHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblAdvHeader.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)
$lblAdvHeader.Location = New-Object System.Drawing.Point(10, $global:CurrentY)
$lblAdvHeader.Size = New-Object System.Drawing.Size(300, 18)
$panelScroll.Controls.Add($lblAdvHeader)
$global:CurrentY += 22

Add-AmdSlider -Parent $panelScroll -Name "Gamma"     -Label "Gamma"              -Min 1.0  -Max 3.0   -Default 2.20 -Scale 100.0 -Unit "" -Format "F2"
Add-AmdSlider -Parent $panelScroll -Name "Hue"       -Label "Hue"                -Min -30  -Max 30    -Default 0    -Scale 1.0   -Unit "°" -Format "F0"
Add-AmdSlider -Parent $panelScroll -Name "RedGain"   -Label "Red Balance"        -Min -50  -Max 50    -Default 0    -Scale 1.0   -Unit "%" -Format "F0"
Add-AmdSlider -Parent $panelScroll -Name "GreenGain" -Label "Green Balance"      -Min -50  -Max 50    -Default 0    -Scale 1.0   -Unit "%" -Format "F0"
Add-AmdSlider -Parent $panelScroll -Name "BlueGain"  -Label "Blue Balance"       -Min -50  -Max 50    -Default 0    -Scale 1.0   -Unit "%" -Format "F0"

function Get-CurrentSliderValues {
    return @{
        ColorTemp  = [double]$global:Sliders["ColorTemp"].TrackBar.Value / [double]$global:Sliders["ColorTemp"].Scale
        Brightness = [double]$global:Sliders["Brightness"].TrackBar.Value / [double]$global:Sliders["Brightness"].Scale
        Contrast   = [double]$global:Sliders["Contrast"].TrackBar.Value / [double]$global:Sliders["Contrast"].Scale
        Saturation = [double]$global:Sliders["Saturation"].TrackBar.Value / [double]$global:Sliders["Saturation"].Scale
        Gamma      = [double]$global:Sliders["Gamma"].TrackBar.Value / [double]$global:Sliders["Gamma"].Scale
        Hue        = [double]$global:Sliders["Hue"].TrackBar.Value / [double]$global:Sliders["Hue"].Scale
        RedGain    = [double]$global:Sliders["RedGain"].TrackBar.Value / [double]$global:Sliders["RedGain"].Scale
        GreenGain  = [double]$global:Sliders["GreenGain"].TrackBar.Value / [double]$global:Sliders["GreenGain"].Scale
        BlueGain   = [double]$global:Sliders["BlueGain"].TrackBar.Value / [double]$global:Sliders["BlueGain"].Scale
    }
}

function Update-FromAmdSliders {
    $v = Get-CurrentSliderValues
    [DisplayGdi]::ApplyRampDirect($v.ColorTemp, $v.Brightness, $v.Contrast, $v.Saturation, $v.Gamma, $v.Hue, $v.RedGain, $v.GreenGain, $v.BlueGain) | Out-Null
    Save-DisplayProfile $v
}

function Load-SavedProfileToSliders {
    $p = Load-DisplayProfile
    if ($p) {
        foreach ($prop in @("ColorTemp", "Brightness", "Contrast", "Saturation", "Gamma", "Hue", "RedGain", "GreenGain", "BlueGain")) {
            if ($null -ne $p.$prop -and $global:Sliders.ContainsKey($prop)) {
                $s = $global:Sliders[$prop]
                $val = [double]$p.$prop
                $s.TrackBar.Value = [int]($val * $s.Scale)
                $s.TextBox.Text = ($val.ToString($s.Format) + $s.Unit)
            }
        }
    }
}

function Reset-AllToDefaults {
    foreach ($key in $global:Sliders.Keys) {
        $s = $global:Sliders[$key]
        $s.TrackBar.Value = [int]($s.Default * $s.Scale)
        $s.TextBox.Text = ($s.Default.ToString($s.Format) + $s.Unit)
    }
    Update-FromAmdSliders
}

# Studio Presets Dictionary
$global:StudioPresets = @{
    "sRGB" = @{
        ColorTemp = 6500; Brightness = 0; Contrast = 100; Saturation = 100; Gamma = 2.20; Hue = 0; RedGain = 0; GreenGain = 0; BlueGain = 0
    }
    "Creator" = @{
        ColorTemp = 6350; Brightness = 0; Contrast = 108; Saturation = 128; Gamma = 2.26; Hue = 0; RedGain = 3; GreenGain = 1; BlueGain = -4
    }
    "MacBook" = @{
        ColorTemp = 6400; Brightness = -1; Contrast = 110; Saturation = 122; Gamma = 2.28; Hue = 0; RedGain = 2; GreenGain = 0; BlueGain = -3
    }
    "Cinema" = @{
        ColorTemp = 6300; Brightness = 0; Contrast = 106; Saturation = 118; Gamma = 2.25; Hue = 0; RedGain = 2; GreenGain = 1; BlueGain = -3
    }
    "Night" = @{
        ColorTemp = 5200; Brightness = -3; Contrast = 96; Saturation = 95; Gamma = 2.15; Hue = 0; RedGain = 2; GreenGain = 2; BlueGain = -12
    }
}

function Apply-StudioPreset {
    param([string]$Key)
    if ($global:StudioPresets.ContainsKey($Key)) {
        $p = $global:StudioPresets[$Key]
        foreach ($prop in @("ColorTemp", "Brightness", "Contrast", "Saturation", "Gamma", "Hue", "RedGain", "GreenGain", "BlueGain")) {
            if ($global:Sliders.ContainsKey($prop)) {
                $s = $global:Sliders[$prop]
                $val = [double]$p.$prop
                $s.TrackBar.Value = [int]($val * $s.Scale)
                $s.TextBox.Text = ($val.ToString($s.Format) + $s.Unit)
            }
        }
        Update-FromAmdSliders
    }
}

# Build Preset Buttons in Preset Strip
$presetList = @(
    @{ Key = "sRGB";    Text = "Studio sRGB Reference" },
    @{ Key = "Creator"; Text = "Creator 45% NTSC" },
    @{ Key = "MacBook"; Text = "MacBook Liquid P3" },
    @{ Key = "Cinema";  Text = "Cinema DCI-P3" },
    @{ Key = "Night";   Text = "Night D50 Reading" }
)

$btnX = 115
foreach ($item in $presetList) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $item.Text
    $btn.Location = New-Object System.Drawing.Point($btnX, 7)
    $btn.Size = New-Object System.Drawing.Size(155, 28)
    $btn.BackColor = [System.Drawing.Color]::FromArgb(32, 36, 48)
    $btn.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(55, 62, 78)
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Tag = $item.Key
    $btn.Add_Click({
        Apply-StudioPreset $this.Tag
    })
    $presetPanel.Controls.Add($btn)
    $btnX += 162
}

# Reference Test Pattern Bitmap
$pbPreview = New-Object System.Windows.Forms.PictureBox
$pbPreview.Location = New-Object System.Drawing.Point(12, 25)
$pbPreview.Size = New-Object System.Drawing.Size(282, 465)
$pbPreview.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pbPreview.BackColor = [System.Drawing.Color]::Black
$pbPreview.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pbPreview.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$grpPreview.Controls.Add($pbPreview)

$bmp = New-Object System.Drawing.Bitmap(282, 465)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(16, 16, 16))

# 1. 16 Grayscale Steps
$stepWidth = 282 / 16.0
for ($i = 0; $i -lt 16; $i++) {
    $c = [int]($i * 255 / 15.0)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($c, $c, $c))
    $g.FillRectangle($brush, [int]($i * $stepWidth), 5, [int]($stepWidth + 1), 38)
}

# 2. Smooth Gradient
for ($x = 0; $x -lt 282; $x++) {
    $c = [int]($x * 255.0 / 281.0)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($c, $c, $c))
    $g.DrawLine($pen, $x, 50, $x, 95)
}

# 3. Colors
$colors = @(
    [System.Drawing.Color]::Red,
    [System.Drawing.Color]::FromArgb(255, 128, 0),
    [System.Drawing.Color]::Yellow,
    [System.Drawing.Color]::Lime,
    [System.Drawing.Color]::Cyan,
    [System.Drawing.Color]::Blue,
    [System.Drawing.Color]::Magenta,
    [System.Drawing.Color]::White
)
$cWidth = 282 / $colors.Count
for ($i = 0; $i -lt $colors.Count; $i++) {
    $brush = New-Object System.Drawing.SolidBrush($colors[$i])
    $g.FillRectangle($brush, [int]($i * $cWidth), 105, [int]($cWidth + 1), 65)
}

# 4. Skin Tones
$skinColors = @(
    [System.Drawing.Color]::FromArgb(255, 224, 189),
    [System.Drawing.Color]::FromArgb(234, 192, 134),
    [System.Drawing.Color]::FromArgb(212, 160, 102),
    [System.Drawing.Color]::FromArgb(174, 114, 60),
    [System.Drawing.Color]::FromArgb(112, 66, 20)
)
$sWidth = 282 / $skinColors.Count
for ($i = 0; $i -lt $skinColors.Count; $i++) {
    $brush = New-Object System.Drawing.SolidBrush($skinColors[$i])
    $g.FillRectangle($brush, [int]($i * $sWidth), 180, [int]($sWidth + 1), 55)
}

# 5. Low End Shadows
for ($i = 0; $i -lt 8; $i++) {
    $val = $i * 4 + 4
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($val, $val, $val))
    $g.FillRectangle($brush, [int]($i * 282 / 8.0), 245, [int](282 / 8.0), 50)
}

# 6. Highlights
for ($i = 0; $i -lt 8; $i++) {
    $val = 255 - (7 - $i) * 4
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($val, $val, $val))
    $g.FillRectangle($brush, [int]($i * 282 / 8.0), 305, [int](282 / 8.0), 50)
}

$fontSmall = New-Object System.Drawing.Font("Segoe UI", 8)
$brushText = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 160, 160))
$g.DrawString("Grayscale | Gradient | Primaries | Skin | Shadows | Highlights", $fontSmall, $brushText, 2, 365)

$pbPreview.Image = $bmp

# Startup Button in Right Column
$btnStartup = New-Object System.Windows.Forms.Button
$btnStartup.Text = "Save as Windows Startup Profile"
$btnStartup.Location = New-Object System.Drawing.Point(12, 505)
$btnStartup.Size = New-Object System.Drawing.Size(282, 48)
$btnStartup.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnStartup.BackColor = [System.Drawing.Color]::FromArgb(35, 125, 60)
$btnStartup.ForeColor = [System.Drawing.Color]::White
$btnStartup.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStartup.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(45, 150, 75)
$btnStartup.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnStartup.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnStartup.Add_Click({
    $v = Get-CurrentSliderValues
    Save-DisplayProfile $v

    $taskName = "DisplayTuneAutoCalibration"
    $psExe = (Get-Process -Id $PID).Path
    $cmdLine = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptDir\display-tune.ps1`" apply -Startup"
    
    $xmlContent = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>DisplayTune Hardware LUT Calibration Loader (Logon, Wake and Unlock)</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT3S</Delay>
    </LogonTrigger>
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>SessionUnlock</StateChange>
      <Delay>PT1S</Delay>
    </SessionStateChangeTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=107]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
      <Delay>PT2S</Delay>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$psExe</Command>
      <Arguments>$cmdLine</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    $tempXml = Join-Path $env:TEMP "DisplayTuneTask.xml"
    [System.IO.File]::WriteAllText($tempXml, $xmlContent, [System.Text.Encoding]::Unicode)
    schtasks.exe /Create /F /TN $taskName /XML "$tempXml" | Out-Null
    Remove-Item $tempXml -Force -ErrorAction SilentlyContinue

    [System.Windows.Forms.MessageBox]::Show("Successfully saved calibration and registered task to auto-restore on Windows Logon, Wake from Sleep, and Screen Unlock!", "DisplayTune", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})
$grpPreview.Controls.Add($btnStartup)

# Load saved profile if exists, then apply to display
Load-SavedProfileToSliders
Update-FromAmdSliders

# Run GUI
[System.Windows.Forms.Application]::EnableVisualStyles()
$form.ShowDialog() | Out-Null
