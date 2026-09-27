# DisplayTune

A low-latency, zero-overhead display color calibration and hardware look-up table (LUT) controller for Windows. Interacts directly with the Win32 GDI display driver pipeline (`GetDC` / `SetDeviceGammaRamp`) to adjust color temperature, contrast, brightness, gamma, and perceptual chroma without background processes.

---

## Architecture Overview

```
[ DisplayTune CLI / GUI ]
           │
           ▼
[ Hardware LUT Generator (Planckian Locus + Non-Linear Chroma Wave) ]
           │
           ▼
[ Win32 GDI Subsystem (gdi32.dll / user32.dll) ]
           │
           ▼
[ GPU Display Engine (AMD / Intel / NVIDIA) ] ──> [ Panel Hardware LUT ]
```

- **Direct Hardware Pipeline**: Writes directly to the 256-entry 16-bit RGB gamma ramp in GPU scanout registers.
- **Zero Resource Footprint**: Set-once execution model. Does not run background services or consume CPU/RAM after applying.
- **Universal Hardware Support**: Works across all integrated and dedicated GPUs (AMD Radeon, Intel Iris Xe/UHD, NVIDIA GeForce) on internal laptop displays and external monitors.
- **Dynamic Hardware Discovery**: Automatically queries WMI/CIM and monitor EDID for panel model, resolution, and refresh rate.

---

## Controls Reference

### Primary Display Parameters

| Parameter | Type | Range | Default | Description |
| :--- | :---: | :---: | :---: | :--- |
| `ColorTemp` | Float | `4000` - `10000` | `6500` | Blackbody Planckian locus white point temperature in Kelvin. |
| `Brightness` | Float | `-100` - `+100` | `0` | Black level offset across all channels. |
| `Contrast` | Float | `0` - `200` | `100` | Linear dynamic range expansion centered at midpoint (0.5). |
| `Saturation` | Float | `0` - `200` | `100` | Harmonic chroma wave expansion preserving neutral gray axis. |

### Advanced Precision Parameters

| Parameter | Type | Range | Default | Description |
| :--- | :---: | :---: | :---: | :--- |
| `Gamma` | Float | `1.00` - `3.00` | `2.20` | Power transfer curve exponent (`2.20 / Gamma`). |
| `Hue` | Float | `-30` - `+30` | `0` | Rotation angle in degrees on the YIQ color plane. |
| `RedGain` | Float | `-50` - `+50` | `0` | Channel gain multiplier for the red primary. |
| `GreenGain` | Float | `-50` - `+50` | `0` | Channel gain multiplier for the green primary. |
| `BlueGain` | Float | `-50` - `+50` | `0` | Channel gain multiplier for the blue primary. |

---

## Studio Reference Presets

| Preset | Target Calibration | Characteristics |
| :--- | :--- | :--- |
| **Studio sRGB** | Rec.709 / sRGB D65 Standard | Reference neutral 6500K white point, 2.20 gamma, unity gain. |
| **Creator 45% NTSC** | Perceptual 100% sRGB Emulation | Midtone chroma expansion, compensates for narrow red phosphor panels. |
| **MacBook Liquid P3** | Apple Liquid Retina Profile | Deep shadow contrast (Gamma 2.28), vibrant primaries, D65 white point. |
| **Cinema DCI-P3** | Filmic Mastering | Warm theatrical transfer (6300K), enhanced shadow detail. |
| **Night D50 Reading** | Low Blue-Light Paper White | 5200K warm white point, reduced blue luminance for eye fatigue prevention. |

---

## Standalone Executable

`DisplayTune.exe` is a 28 KB self-contained portable native Windows binary. It requires no installation, has no external dependencies, and launches in under 50 milliseconds.

```cmd
:: Launch GUI
DisplayTune.exe

:: Apply saved profile silently
DisplayTune.exe --apply

:: Apply preset
DisplayTune.exe --preset creator
DisplayTune.exe --preset srgb
DisplayTune.exe --preset macbook

:: Reset display to default
DisplayTune.exe --reset
```

---

## Usage (PowerShell Scripts)

### Graphical Interface

Launch the interactive control panel:

```powershell
.\display-tune.ps1 gui
```

- **Interactive Numeric Boxes**: Click any numeric box, enter a target value, and press `Enter` or click away to apply immediately.
- **Double-Click Reset**: Double-click any parameter label to reset that individual parameter to its default.
- **Persistent State**: Settings are automatically saved to `profile.json` on change.

### Command Line Interface

```powershell
# Display detected monitor hardware and GPU information
.\display-tune.ps1 inspect

# Apply a studio reference preset
.\display-tune.ps1 preset -PresetName creator
.\display-tune.ps1 preset -PresetName macbook
.\display-tune.ps1 preset -PresetName srgb

# Apply custom parameters
.\display-tune.ps1 set -ColorTemp 6400 -Brightness 0 -Contrast 110 -Saturation 130 -Gamma 2.28 -RedGain 4 -GreenGain 2 -BlueGain -5

# Apply saved configuration from profile.json
.\display-tune.ps1 apply

# Reset display to factory defaults
.\display-tune.ps1 reset

# Register logon task for persistent startup calibration
.\display-tune.ps1 startup

# Remove logon startup task
.\display-tune.ps1 startup -RemoveStartup
```

---

## File Structure

```
Display/
├── DisplayTune.exe         # Standalone compiled portable binary (28 KB)
├── DisplayTune.cs          # Native C# source code
├── DisplayEngine.ps1       # Low-level Win32 GDI wrapper and math engine
├── DisplayTuneGUI.ps1      # WinForms hardware controller interface
├── display-tune.ps1        # Unified CLI entry point
├── display-tune.cmd        # One-click Windows batch launcher
├── profile.json            # Persistent user calibration profile
└── README.md               # Technical documentation
```

---

## License

MIT License. Free for personal and commercial use.
