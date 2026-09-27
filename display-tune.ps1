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

    [switch]$InstallStartup,
    [switch]$RemoveStartup
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "DisplayEngine.ps1")

function Show-Header {
    Write-Host ""
    Write-Host " =================================================================" -ForegroundColor Cyan
    Write-Host "   DISPLAYTUNE - AMD Custom Color Display Controller" -ForegroundColor White
    Write-Host "   Pure Hardware Color Pipeline (Zero Latency / Zero Preset Clutter)" -ForegroundColor Gray
    Write-Host " =================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Help {
    Show-Header
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  .\display-tune.ps1 gui                                    - Launch AMD Custom Color UI"
    Write-Host "  .\display-tune.ps1 inspect                                - Analyze panel model & current gamut"
    Write-Host "  .\display-tune.ps1 set [options]                          - Apply exact custom color parameters:"
    Write-Host "      -ColorTemp 6500 -Brightness 0 -Contrast 100 -Saturation 125 -Gamma 2.20 -Hue 0"
    Write-Host "  .\display-tune.ps1 reset                                  - Reset all parameters to 100% default"
    Write-Host "  .\display-tune.ps1 startup                                - Make current profile run at Windows logon"
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
            if ($res) {
                Write-Host "Loaded and applied saved profile from profile.json!" -ForegroundColor Green
            } else {
                Write-Host "Failed to apply hardware gamma ramp from profile." -ForegroundColor Red
            }
        } else {
            Write-Host "No saved profile found in profile.json. Use GUI or 'set' first." -ForegroundColor Yellow
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
        $cmdLine = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptDir\display-tune.ps1`" apply"
        
        $action = New-ScheduledTaskAction -Execute $psExe -Argument $cmdLine
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-Host "Configured DisplayTune to automatically run current profile at Windows Logon!" -ForegroundColor Green
    }

    Default {
        Show-Help
    }
}
