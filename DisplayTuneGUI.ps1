# ==============================================================================
# DisplayTune GUI - AMD Radeon Style Custom Color Controller
# Clean, fluid, intuitive controls for any display with zero preset clutter
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "DisplayEngine.ps1")

# Create Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "DisplayTune - AMD Custom Color Controller"
$form.Size = New-Object System.Drawing.Size(980, 720)
$form.MinimumSize = New-Object System.Drawing.Size(900, 620)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(21, 23, 28)
$form.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true

# Header Bar (AMD Style)
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Location = New-Object System.Drawing.Point(16, 12)
$headerPanel.Size = New-Object System.Drawing.Size(932, 60)
$headerPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(28, 31, 38)
$headerPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($headerPanel)

$info = Get-DisplayHardwareInfo
$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = ("Custom Color Controls | Display: " + $info.PanelModel + " (" + $info.Resolution + " @ " + $info.RefreshRate + ")")
$lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(235, 60, 60)
$lblHeader.Location = New-Object System.Drawing.Point(15, 8)
$lblHeader.AutoSize = $true
$headerPanel.Controls.Add($lblHeader)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Modify the display's color reproduction in real-time (AMD Direct Hardware Pipeline)"
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 165, 180)
$lblSub.Location = New-Object System.Drawing.Point(15, 32)
$lblSub.AutoSize = $true
$headerPanel.Controls.Add($lblSub)

# Reset Button in Header (Top Right)
$btnResetTop = New-Object System.Windows.Forms.Button
$btnResetTop.Text = "Reset to Default"
$btnResetTop.Location = New-Object System.Drawing.Point(780, 12)
$btnResetTop.Size = New-Object System.Drawing.Size(135, 34)
$btnResetTop.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnResetTop.BackColor = [System.Drawing.Color]::FromArgb(45, 48, 58)
$btnResetTop.ForeColor = [System.Drawing.Color]::White
$btnResetTop.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnResetTop.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnResetTop.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnResetTop.Add_Click({ Reset-AllToDefaults })
$headerPanel.Controls.Add($btnResetTop)

# Left Column: Sliders Container (Scrollable)
$panelScroll = New-Object System.Windows.Forms.Panel
$panelScroll.Location = New-Object System.Drawing.Point(16, 85)
$panelScroll.Size = New-Object System.Drawing.Size(610, 575)
$panelScroll.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$panelScroll.AutoScroll = $true
$form.Controls.Add($panelScroll)

# Right Column: Live Pattern Box
$grpPreview = New-Object System.Windows.Forms.GroupBox
$grpPreview.Text = " Live Calibration Pattern "
$grpPreview.Location = New-Object System.Drawing.Point(640, 85)
$grpPreview.Size = New-Object System.Drawing.Size(308, 575)
$grpPreview.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$grpPreview.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
$form.Controls.Add($grpPreview)

# Global slider storage
$global:Sliders = @{}
$global:CurrentY = 10

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
    $rowPanel.Size = New-Object System.Drawing.Size(565, 54)
    $rowPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $rowPanel.BackColor = [System.Drawing.Color]::FromArgb(26, 28, 35)
    $rowPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $Parent.Controls.Add($rowPanel)

    # Label on Left
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point(12, 16)
    $lbl.Size = New-Object System.Drawing.Size(160, 22)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(235, 240, 250)
    $rowPanel.Controls.Add($lbl)

    # Value Box in Middle
    $txtVal = New-Object System.Windows.Forms.TextBox
    $txtVal.Text = ($Default.ToString($Format) + $Unit)
    $txtVal.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $txtVal.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
    $txtVal.Location = New-Object System.Drawing.Point(180, 14)
    $txtVal.Size = New-Object System.Drawing.Size(75, 24)
    $txtVal.BackColor = [System.Drawing.Color]::FromArgb(18, 20, 24)
    $txtVal.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $txtVal.ReadOnly = $true
    $rowPanel.Controls.Add($txtVal)

    # Trackbar on Right
    $trk = New-Object System.Windows.Forms.TrackBar
    $trk.Location = New-Object System.Drawing.Point(265, 12)
    $trk.Size = New-Object System.Drawing.Size(285, 30)
    $trk.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $trk.Minimum = [int]($Min * $Scale)
    $trk.Maximum = [int]($Max * $Scale)
    $trk.Value = [int]($Default * $Scale)
    $trk.TickStyle = [System.Windows.Forms.TickStyle]::None
    $trk.BackColor = [System.Drawing.Color]::FromArgb(26, 28, 35)

    $trk.Tag = @{
        TextBox = $txtVal
        Scale   = $Scale
        Unit    = $Unit
        Format  = $Format
        Name    = $Name
    }

    $trk.Add_Scroll({
        $meta = $this.Tag
        $val = [double]$this.Value / [double]$meta.Scale
        $meta.TextBox.Text = ($val.ToString($meta.Format) + $meta.Unit)
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
    }

    $global:CurrentY += 60
}

# --- SECTION 1: THE CORE 4 CONTROLS ---
$lblCoreHeader = New-Object System.Windows.Forms.Label
$lblCoreHeader.Text = "MAIN DISPLAY CONTROLS"
$lblCoreHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblCoreHeader.ForeColor = [System.Drawing.Color]::FromArgb(130, 140, 160)
$lblCoreHeader.Location = New-Object System.Drawing.Point(10, $global:CurrentY)
$lblCoreHeader.Size = New-Object System.Drawing.Size(300, 18)
$panelScroll.Controls.Add($lblCoreHeader)
$global:CurrentY += 22

Add-AmdSlider -Parent $panelScroll -Name "ColorTemp"  -Label "Color Temperature" -Min 4000 -Max 10000 -Default 6500 -Scale 1.0 -Unit " K" -Format "F0"
Add-AmdSlider -Parent $panelScroll -Name "Brightness" -Label "Brightness"        -Min -100 -Max 100  -Default 0    -Scale 1.0 -Unit ""   -Format "F0"
Add-AmdSlider -Parent $panelScroll -Name "Contrast"   -Label "Contrast"          -Min 0    -Max 200  -Default 100  -Scale 1.0 -Unit ""   -Format "F0"
Add-AmdSlider -Parent $panelScroll -Name "Saturation" -Label "Saturation"        -Min 0    -Max 200  -Default 100  -Scale 1.0 -Unit ""   -Format "F0"

$global:CurrentY += 10

# --- SECTION 2: ADVANCED CONTROLS (COLLAPSIBLE / ACCESSIBLE) ---
$lblAdvHeader = New-Object System.Windows.Forms.Label
$lblAdvHeader.Text = "ADVANCED FINE-TUNING"
$lblAdvHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblAdvHeader.ForeColor = [System.Drawing.Color]::FromArgb(130, 140, 160)
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

# Reference Test Pattern Bitmap
$pbPreview = New-Object System.Windows.Forms.PictureBox
$pbPreview.Location = New-Object System.Drawing.Point(12, 25)
$pbPreview.Size = New-Object System.Drawing.Size(282, 470)
$pbPreview.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pbPreview.BackColor = [System.Drawing.Color]::Black
$pbPreview.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pbPreview.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$grpPreview.Controls.Add($pbPreview)

$bmp = New-Object System.Drawing.Bitmap(282, 470)
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
$btnStartup.Location = New-Object System.Drawing.Point(12, 510)
$btnStartup.Size = New-Object System.Drawing.Size(282, 45)
$btnStartup.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnStartup.BackColor = [System.Drawing.Color]::FromArgb(35, 125, 60)
$btnStartup.ForeColor = [System.Drawing.Color]::White
$btnStartup.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStartup.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnStartup.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnStartup.Add_Click({
    $v = Get-CurrentSliderValues
    Save-DisplayProfile $v

    $taskName = "DisplayTuneAutoCalibration"
    $psExe = (Get-Process -Id $PID).Path
    $cmdLine = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptDir\display-tune.ps1`" apply"
    
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $cmdLine
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    [System.Windows.Forms.MessageBox]::Show("Successfully saved current Custom Color profile to profile.json and set to run automatically at Windows Logon!", "DisplayTune", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})
$grpPreview.Controls.Add($btnStartup)

# Load saved profile if exists, then apply to display
Load-SavedProfileToSliders
Update-FromAmdSliders

# Run GUI
[System.Windows.Forms.Application]::EnableVisualStyles()
$form.ShowDialog() | Out-Null
