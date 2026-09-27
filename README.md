# 🚀 DisplayTune - AMD Radeon Custom Color Controller

> **Pure hardware display color controller matching AMD Radeon Custom Color with zero preset clutter, fluid linear saturation, and direct hardware GDI precision.**

---

## 🎛️ The 4 Core Display Controls (Top Section)

| Control | Description | Range / Default |
| :--- | :--- | :--- |
| **Color Temperature** | Shifts white point warmth (`4000K` warm sunset to `10000K` cool blue) | `4000K` – `10000K` (Default `6500K`) |
| **Brightness** | Overall display luminance level | `-100` to `+100` (Default `0`) |
| **Contrast** | Light/dark separation without crushing shadows | `0` to `200` (Default `100`) |
| **Saturation** | Pure linear Rec.709 chroma booster (boosts all colors evenly without orange skew) | `0` to `200` (Default `100`) |

---

## ⚙️ Advanced Fine-Tuning (Bottom Section)

- **Gamma**: Linear midtone transfer curve (`1.00` to `3.00`, default `2.20`).
- **Hue**: Full 360° color wheel rotation (`-30°` to `+30°`, default `0°`).
- **Red Balance**: Direct red gain fine-tuning (`-50%` to `+50%`).
- **Green Balance**: Direct green gain fine-tuning (`-50%` to `+50%`).
- **Blue Balance**: Direct blue gain fine-tuning (`-50%` to `+50%`).

---

## 💻 Commands

```powershell
# Launch the AMD-Style GUI
.\display-tune.ps1 gui

# Reset all display settings to 100% factory default
.\display-tune.ps1 reset

# Apply custom parameters from CLI
.\display-tune.ps1 set -ColorTemp 6500 -Brightness 0 -Contrast 105 -Saturation 125 -Gamma 2.20
```
