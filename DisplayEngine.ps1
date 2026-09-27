# ==============================================================================
# DisplayTune - Real-Time Display Color Engine (AMD Adrenalin Pipeline)
# High-Performance GDI Hardware LUT Controller
# ==============================================================================

if (-not ([System.Management.Automation.PSTypeName]'DisplayGdi').Type) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class DisplayGdi {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll", SetLastError = true)]
    public static extern bool GetDeviceGammaRamp(IntPtr hdc, IntPtr lpRamp);

    [DllImport("gdi32.dll", SetLastError = true)]
    public static extern bool SetDeviceGammaRamp(IntPtr hdc, IntPtr lpRamp);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct RAMP {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public ushort[] Red;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public ushort[] Green;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public ushort[] Blue;
    }

    public static RAMP GenerateRamp(double colorTemp, double brightness, double contrast, double saturation, double gamma, double hue, double redGain, double greenGain, double blueGain) {
        RAMP ramp = new RAMP();
        ramp.Red = new ushort[256];
        ramp.Green = new ushort[256];
        ramp.Blue = new ushort[256];

        // 1. Color Temperature Gains (Planckian locus)
        double rT = 1.0, gT = 1.0, bT = 1.0;
        if (Math.Abs(colorTemp - 6500.0) > 1.0) {
            double k = Math.Max(4000.0, Math.Min(10000.0, colorTemp));
            double t = k / 100.0;
            
            // Red
            if (t <= 66.0) rT = 1.0;
            else {
                double calc = 329.698727446 * Math.Pow(t - 60.0, -0.1332047592);
                rT = Math.Max(0.0, Math.Min(255.0, calc)) / 255.0;
            }

            // Green
            if (t <= 66.0) {
                double calc = 99.4708025861 * Math.Log(t) - 161.1195681661;
                gT = Math.Max(0.0, Math.Min(255.0, calc)) / 255.0;
            } else {
                double calc = 288.1221695283 * Math.Pow(t - 60.0, -0.0755148492);
                gT = Math.Max(0.0, Math.Min(255.0, calc)) / 255.0;
            }

            // Blue
            if (t >= 66.0) bT = 1.0;
            else if (t <= 19.0) bT = 0.0;
            else {
                double calc = 138.5177312231 * Math.Log(t - 10.0) - 305.0447927307;
                bT = Math.Max(0.0, Math.Min(255.0, calc)) / 255.0;
            }

            double d65G = (99.4708025861 * Math.Log(65.0) - 161.1195681661) / 255.0;
            gT = gT / d65G;
        }

        // 2. Factors
        double c = contrast / 100.0;
        double b = brightness / 200.0;
        double s = saturation / 100.0;
        double sMidBoost = (s - 1.0) * 0.45;
        double gExp = (gamma > 0.1) ? (2.20 / gamma) : 1.0;

        double rGainMul = 1.0 + (redGain / 100.0);
        double gGainMul = 1.0 + (greenGain / 100.0);
        double bGainMul = 1.0 + (blueGain / 100.0);

        double hueRad = (hue * Math.PI) / 180.0;
        double cosA = Math.Cos(hueRad);
        double sinA = Math.Sin(hueRad);

        for (int i = 0; i < 256; i++) {
            double x = i / 255.0;

            // Contrast & Brightness
            double val = (x - 0.5) * c + 0.5 + b;
            if (val > 0.0) {
                val = Math.Pow(val, gExp);
            } else {
                val = 0.0;
            }

            // Chroma wave expansion (natural vibrance, no orange skew)
            double chromaWave = Math.Sin(x * Math.PI);
            double rChannelGain = rT * rGainMul * (1.0 + sMidBoost * chromaWave * 0.35);
            double gChannelGain = gT * gGainMul * (1.0 + sMidBoost * chromaWave * 0.22);
            double bChannelGain = bT * bGainMul * (1.0 - sMidBoost * chromaWave * 0.18);

            double rVal = val * rChannelGain;
            double gVal = val * gChannelGain;
            double bVal = val * bChannelGain;

            // Hue rotation
            if (Math.Abs(hue) > 0.01) {
                double hR = rVal * (0.213 + cosA * 0.787 - sinA * 0.213) + gVal * (0.715 - cosA * 0.715 - sinA * 0.715) + bVal * (0.072 - cosA * 0.072 + sinA * 0.928);
                double hG = rVal * (0.213 - cosA * 0.213 + sinA * 0.143) + gVal * (0.715 + cosA * 0.285 + sinA * 0.140) + bVal * (0.072 - cosA * 0.072 - sinA * 0.283);
                double hB = rVal * (0.213 - cosA * 0.213 - sinA * 0.787) + gVal * (0.715 - cosA * 0.715 + sinA * 0.715) + bVal * (0.072 + cosA * 0.928 + sinA * 0.072);
                rVal = hR; gVal = hG; bVal = hB;
            }

            // Clamp [0.0, 1.0]
            rVal = Math.Max(0.0, Math.Min(1.0, rVal));
            gVal = Math.Max(0.0, Math.Min(1.0, gVal));
            bVal = Math.Max(0.0, Math.Min(1.0, bVal));

            ramp.Red[i] = (ushort)Math.Round(rVal * 65535.0);
            ramp.Green[i] = (ushort)Math.Round(gVal * 65535.0);
            ramp.Blue[i] = (ushort)Math.Round(bVal * 65535.0);
        }

        // Driver Monotonicity Assurance (prevents Windows GDI rejecting non-monotonic ramps)
        for (int i = 1; i < 256; i++) {
            if (ramp.Red[i] < ramp.Red[i - 1]) ramp.Red[i] = ramp.Red[i - 1];
            if (ramp.Green[i] < ramp.Green[i - 1]) ramp.Green[i] = ramp.Green[i - 1];
            if (ramp.Blue[i] < ramp.Blue[i - 1]) ramp.Blue[i] = ramp.Blue[i - 1];
        }

        return ramp;
    }

    public static bool ApplyRampDirect(double colorTemp, double brightness, double contrast, double saturation, double gamma, double hue, double redGain, double greenGain, double blueGain) {
        RAMP ramp = GenerateRamp(colorTemp, brightness, contrast, saturation, gamma, hue, redGain, greenGain, blueGain);
        IntPtr hdc = GetDC(IntPtr.Zero);
        IntPtr ptr = Marshal.AllocHGlobal(Marshal.SizeOf(ramp));
        Marshal.StructureToPtr(ramp, ptr, false);
        bool success = SetDeviceGammaRamp(hdc, ptr);
        Marshal.FreeHGlobal(ptr);
        ReleaseDC(IntPtr.Zero, hdc);
        return success;
    }

    public static bool ApplyRamp(ushort[] red, ushort[] green, ushort[] blue) {
        IntPtr hdc = GetDC(IntPtr.Zero);
        RAMP ramp = new RAMP { Red = red, Green = green, Blue = blue };
        IntPtr ptr = Marshal.AllocHGlobal(Marshal.SizeOf(ramp));
        Marshal.StructureToPtr(ramp, ptr, false);
        bool success = SetDeviceGammaRamp(hdc, ptr);
        Marshal.FreeHGlobal(ptr);
        ReleaseDC(IntPtr.Zero, hdc);
        return success;
    }
}
"@ -ErrorAction SilentlyContinue
}

function Get-DisplayHardwareInfo {
    [CmdletBinding()]
    param()

    $mfg = "Standard"
    $prod = "Generic"
    $panelModel = "Standard IPS/OLED Panel"
    
    try {
        $mon = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mon) {
            if ($mon.ManufacturerName) {
                $mfg = -join ($mon.ManufacturerName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
            }
            if ($mon.ProductCodeID) {
                $prod = -join ($mon.ProductCodeID | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
            }
            if ($mon.UserFriendlyName) {
                $user = -join ($mon.UserFriendlyName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
                if ($user.Length -gt 0) { $panelModel = $user }
            }
            if ($panelModel -eq "Standard IPS/OLED Panel" -and $prod.Length -gt 0) {
                if ($mfg -eq "BOE" -and $prod -eq "0D39") {
                    $panelModel = "BOE NE156FHM-NXA"
                } else {
                    $panelModel = "$mfg $prod"
                }
            }
        }
    } catch {}

    $res = "1920 x 1080"
    $hz = "60 Hz"
    try {
        $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1
        if ($vc) {
            $res = ("{0} x {1}" -f $vc.CurrentHorizontalResolution, $vc.CurrentVerticalResolution)
            $hz = ("{0} Hz" -f $vc.CurrentRefreshRate)
        }
    } catch {}

    $gpus = @()
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    } catch {}

    $priGpu = if ($gpus.Count -gt 0) { $gpus[0] } else { "Integrated Display Controller" }
    $secGpu = if ($gpus.Count -gt 1) { $gpus[1] } else { "N/A" }

    return [PSCustomObject]@{
        PanelModel       = $panelModel
        Manufacturer     = $mfg
        ProductCode      = $prod
        NativeGamma      = 2.2
        RefreshRate      = $hz
        Resolution       = $res
        PrimaryGPU       = $priGpu
        DedicatedGPU     = $secGpu
    }
}

function Build-AmdStandardRamp {
    param(
        [double]$ColorTemperature = 6500,
        [double]$Brightness = 0,
        [double]$Contrast = 100,
        [double]$Saturation = 100,
        [double]$Gamma = 2.20,
        [double]$Hue = 0,
        [double]$RedGain = 0,
        [double]$GreenGain = 0,
        [double]$BlueGain = 0
    )

    $ramp = [DisplayGdi]::GenerateRamp($ColorTemperature, $Brightness, $Contrast, $Saturation, $Gamma, $Hue, $RedGain, $GreenGain, $BlueGain)
    return @{
        Red   = $ramp.Red
        Green = $ramp.Green
        Blue  = $ramp.Blue
    }
}

$global:ProfilePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "profile.json"

function Save-DisplayProfile {
    param([hashtable]$Settings)
    try {
        $json = $Settings | ConvertTo-Json -Depth 2
        Set-Content -Path $global:ProfilePath -Value $json -Force -Encoding UTF8
    } catch {}
}

function Load-DisplayProfile {
    try {
        if (Test-Path $global:ProfilePath) {
            $raw = Get-Content -Path $global:ProfilePath -Raw -Encoding UTF8
            return ($raw | ConvertFrom-Json)
        }
    } catch {}
    return $null
}
