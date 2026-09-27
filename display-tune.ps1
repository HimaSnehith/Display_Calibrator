# ==============================================================================
# DisplayTune CLI - AMD Custom Color Controller
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Command = "help",

    [double]$ColorTemp = 6500,
    [double]$Brightness = 0,
    [double]$Contrast = 100,
    [double]$Saturation = 100,
    [double]$Gamma = 2.20,
    [double]$Hue = 0,
    [double]$RedGain = 0,
    [double]$GreenGain = 0,
    [double]$BlueGain = 0,

    [string]$PresetName = "creator",
    [switch]$InstallStartup,
    [switch]$RemoveStartup
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "DisplayEngine.ps1")

function Show-Header {
    Write-Host ""
    Write-Host " =================================================================" -ForegroundColor Cyan
    Write-Host "   DISPLAYTUNE - Direct Hardware Display Color Controller" -ForegroundColor White
    Write-Host "   Pure Hardware GDI Pipeline (Zero Latency / Studio Reference Presets)" -ForegroundColor Gray
    Write-Host " =================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Help {
    Show-Header
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  .\display-tune.ps1 gui                                    - Launch GUI Controller"
    Write-Host "  .\display-tune.ps1 inspect                                - Analyze panel model & active GPU"
    Write-Host "  .\display-tune.ps1 preset -PresetName [name]              - Apply studio preset (srgb, creator, macbook, cinema, night)"
    Write-Host "  .\display-tune.ps1 set [options]                          - Apply exact custom color parameters:"
    Write-Host "      -ColorTemp 6400 -Brightness 0 -Contrast 110 -Saturation 130 -Gamma 2.28"
    Write-Host "  .\display-tune.ps1 apply                                  - Apply last saved profile.json"
    Write-Host "  .\display-tune.ps1 reset                                  - Reset all display parameters to default"
    Write-Host "  .\display-tune.ps1 startup                                - Run saved profile at Windows logon"
    Write-Host ""
}

switch ($Command.ToLower()) {
    "inspect" {
        Show-Header
        $info = Get-DisplayHardwareInfo
        Write-Host "  [Detected Hardware Display Profile]" -ForegroundColor Green
        Write-Host "  -------------------------------------------------" -ForegroundColor Gray
        Write-Host ("  Panel Model:       {0}" -f $info.PanelModel) -ForegroundColor White
        Write-Host ("  Manufacturer:      {0} (ID: {1})" -f $info.Manufacturer, $info.ProductCode)
        Write-Host ("  Resolution:        {0} @ {1}" -f $info.Resolution, $info.RefreshRate)
        Write-Host ("  Integrated GPU:    {0}" -f $info.PrimaryGPU)
        Write-Host ("  Dedicated GPU:     {0}" -f $info.DedicatedGPU)
        Write-Host ""
    }

    "set" {
        Write-Host "Applying custom color parameters..." -ForegroundColor Cyan
        $res = [DisplayGdi]::ApplyRampDirect($ColorTemp, $Brightness, $Contrast, $Saturation, $Gamma, $Hue, $RedGain, $GreenGain, $BlueGain)
        if ($res) {
            Write-Host "Applied successfully!" -ForegroundColor Green
        } else {
            Write-Host "Failed to apply hardware gamma ramp." -ForegroundColor Red
        }
    }

    "reset" {
        Write-Host "Resetting all display parameters to 100% factory default..." -ForegroundColor Gray
        [DisplayGdi]::ApplyRampDirect(6500, 0, 100, 100, 2.20, 0, 0, 0, 0) | Out-Null
        Write-Host "Display reset to default." -ForegroundColor Green
    }

    "gui" {
        $guiPath = Join-Path $scriptDir "DisplayTuneGUI.ps1"
        & powershell -ExecutionPolicy Bypass -File $guiPath
    }

    "apply" {
        $p = Load-DisplayProfile
        if ($p) {
            $res = [DisplayGdi]::ApplyRampDirect($p.ColorTemp, $p.Brightness, $p.Contrast, $p.Saturation, $p.Gamma, $p.Hue, $p.RedGain, $p.GreenGain, $p.BlueGain)
            if ($PSBoundParameters.ContainsKey("Startup") -or ($Host.UI.RawUI.WindowTitle -eq "")) {
                Start-Sleep -Seconds 3
                [DisplayGdi]::ApplyRampDirect($p.ColorTemp, $p.Brightness, $p.Contrast, $p.Saturation, $p.Gamma, $p.Hue, $p.RedGain, $p.GreenGain, $p.BlueGain) | Out-Null
            }
            if ($res) {
                Write-Host "Loaded and applied saved profile from profile.json!" -ForegroundColor Green
            } else {
                Write-Host "Failed to apply hardware gamma ramp from profile." -ForegroundColor Red
            }
        } else {
            Write-Host "No saved profile found in profile.json. Use GUI or 'set' first." -ForegroundColor Yellow
        }
    }

    "preset" {
        $presets = @{
            "srgb"    = @{ ColorTemp = 6500; Brightness = 0;  Contrast = 100; Saturation = 100; Gamma = 2.20; Hue = 0; RedGain = 0; GreenGain = 0; BlueGain = 0 }
            "creator" = @{ ColorTemp = 6350; Brightness = 0;  Contrast = 108; Saturation = 128; Gamma = 2.26; Hue = 0; RedGain = 3; GreenGain = 1; BlueGain = -4 }
            "macbook" = @{ ColorTemp = 6400; Brightness = -1; Contrast = 110; Saturation = 122; Gamma = 2.28; Hue = 0; RedGain = 2; GreenGain = 0; BlueGain = -3 }
            "cinema"  = @{ ColorTemp = 6300; Brightness = 0;  Contrast = 106; Saturation = 118; Gamma = 2.25; Hue = 0; RedGain = 2; GreenGain = 1; BlueGain = -3 }
            "night"   = @{ ColorTemp = 5200; Brightness = -3; Contrast = 96;  Saturation = 95;  Gamma = 2.15; Hue = 0; RedGain = 2; GreenGain = 2; BlueGain = -12 }
        }
        $target = if ($PSBoundParameters.ContainsKey("PresetName")) { $PresetName.ToLower() } else { "creator" }
        if ($presets.ContainsKey($target)) {
            $p = $presets[$target]
            Save-DisplayProfile $p
            $res = [DisplayGdi]::ApplyRampDirect($p.ColorTemp, $p.Brightness, $p.Contrast, $p.Saturation, $p.Gamma, $p.Hue, $p.RedGain, $p.GreenGain, $p.BlueGain)
            if ($res) {
                Write-Host "Applied Studio Preset: $target" -ForegroundColor Green
            }
        } else {
            Write-Host "Unknown preset. Available: srgb, creator, macbook, cinema, night" -ForegroundColor Yellow
        }
    }

    "startup" {
        $taskName = "DisplayTuneAutoCalibration"
        if ($RemoveStartup) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "Removed DisplayTune from Windows startup." -ForegroundColor Yellow
            return
        }
        
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

        Write-Host "Configured DisplayTune to automatically run on Windows Logon, Wake from Sleep, and Screen Unlock!" -ForegroundColor Green
    }

    Default {
        Show-Help
    }
}
