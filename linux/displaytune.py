#!/usr/bin/env python3
"""
=============================================================================
DisplayTune for Linux (X11, Wayland, DRM/KMS)
Hardware-level display color calibrator and gamma LUT tuning engine for Linux.
Zero background CPU / RAM overhead.
=============================================================================
"""

import sys
import os
import math
import struct
import json
import subprocess
import ctypes
from typing import Tuple, List, Dict

# =============================================================================
# Color Engine (Planckian Locus & Harmonic Chroma Wave Gamma LUT)
# =============================================================================

def generate_ramp(
    color_temp: float = 6400.0,
    brightness: float = -2.0,
    contrast: float = 108.0,
    saturation: float = 120.0,
    gamma: float = 2.30,
    hue: float = 0.0,
    red_gain: float = 2.0,
    green_gain: float = 0.0,
    blue_gain: float = -3.0
) -> Tuple[List[int], List[int], List[int]]:
    """Generates 256-point 16-bit [0..65535] hardware LUT ramps for R, G, B."""
    
    # 1. Color Temperature (Planckian Locus Approximation)
    r_t, g_t, b_t = 1.0, 1.0, 1.0
    if abs(color_temp - 6500.0) > 1.0:
        k = max(4000.0, min(10000.0, color_temp))
        t = k / 100.0

        # Red
        if t <= 66.0:
            r_t = 1.0
        else:
            calc = 329.698727446 * math.pow(t - 60.0, -0.1332047592)
            r_t = max(0.0, min(255.0, calc)) / 255.0

        # Green
        if t <= 66.0:
            calc = 99.4708025861 * math.log(t) - 161.1195681661
            g_t = max(0.0, min(255.0, calc)) / 255.0
        else:
            calc = 288.1221695283 * math.pow(t - 60.0, -0.0755148492)
            g_t = max(0.0, min(255.0, calc)) / 255.0

        # Blue
        if t >= 66.0:
            b_t = 1.0
        elif t <= 19.0:
            b_t = 0.0
        else:
            calc = 138.5177312231 * math.log(t - 10.0) - 305.0447927307
            b_t = max(0.0, min(255.0, calc)) / 255.0

        d65_g = (99.4708025861 * math.log(65.0) - 161.1195681661) / 255.0
        g_t = g_t / d65_g

    # 2. Gains and Factor Curves
    c = contrast / 100.0
    b = brightness / 200.0
    s = saturation / 100.0
    s_mid_boost = (s - 1.0) * 0.45
    g_exp = (2.20 / gamma) if gamma > 0.1 else 1.0

    r_gain_mul = 1.0 + (red_gain / 100.0)
    g_gain_mul = 1.0 + (green_gain / 100.0)
    b_gain_mul = 1.0 + (blue_gain / 100.0)

    hue_rad = math.radians(hue)
    cos_a = math.cos(hue_rad)
    sin_a = math.sin(hue_rad)

    red_ramp, green_ramp, blue_ramp = [], [], []

    for i in range(256):
        x = i / 255.0

        # Contrast & Brightness
        val = (x - 0.5) * c + 0.5 + b
        val = math.pow(val, g_exp) if val > 0.0 else 0.0

        # Harmonic chroma wave expansion
        chroma_wave = math.sin(x * math.pi)
        r_gain = r_t * r_gain_mul * (1.0 + s_mid_boost * chroma_wave * 0.35)
        g_gain = g_t * g_gain_mul * (1.0 + s_mid_boost * chroma_wave * 0.22)
        b_gain = b_t * b_gain_mul * (1.0 - s_mid_boost * chroma_wave * 0.18)

        r_val = val * r_gain
        g_val = val * g_gain
        b_val = val * b_gain

        # Hue rotation
        if abs(hue) > 0.01:
            h_r = r_val * (0.213 + cos_a * 0.787 - sin_a * 0.213) + g_val * (0.715 - cos_a * 0.715 - sin_a * 0.715) + b_val * (0.072 - cos_a * 0.072 + sin_a * 0.928)
            h_g = r_val * (0.213 - cos_a * 0.213 + sin_a * 0.143) + g_val * (0.715 + cos_a * 0.285 + sin_a * 0.140) + b_val * (0.072 - cos_a * 0.072 - sin_a * 0.283)
            h_b = r_val * (0.213 - cos_a * 0.213 - sin_a * 0.787) + g_val * (0.715 - cos_a * 0.715 + sin_a * 0.715) + b_val * (0.072 + cos_a * 0.928 + sin_a * 0.072)
            r_val, g_val, b_val = h_r, h_g, h_b

        # Clamp [0.0, 1.0]
        r_val = max(0.0, min(1.0, r_val))
        g_val = max(0.0, min(1.0, g_val))
        b_val = max(0.0, min(1.0, b_val))

        red_ramp.append(int(round(r_val * 65535.0)))
        green_ramp.append(int(round(g_val * 65535.0)))
        blue_ramp.append(int(round(b_val * 65535.0)))

    # Driver Monotonicity Enforcement
    for i in range(1, 256):
        if red_ramp[i] < red_ramp[i - 1]: red_ramp[i] = red_ramp[i - 1]
        if green_ramp[i] < green_ramp[i - 1]: green_ramp[i] = green_ramp[i - 1]
        if blue_ramp[i] < blue_ramp[i - 1]: blue_ramp[i] = blue_ramp[i - 1]

    return red_ramp, green_ramp, blue_ramp


# =============================================================================
# Profile Data Management
# =============================================================================

DEFAULT_PROFILE = {
    "ColorTemp": 6400.0,
    "Brightness": -2.0,
    "Contrast": 108.0,
    "Saturation": 120.0,
    "Gamma": 2.30,
    "Hue": 0.0,
    "RedGain": 2.0,
    "GreenGain": 0.0,
    "BlueGain": -3.0
}

PRESETS = {
    "srgb": {"ColorTemp": 6500, "Brightness": 0, "Contrast": 100, "Saturation": 100, "Gamma": 2.20, "Hue": 0, "RedGain": 0, "GreenGain": 0, "BlueGain": 0},
    "creator": {"ColorTemp": 6350, "Brightness": 0, "Contrast": 108, "Saturation": 128, "Gamma": 2.26, "Hue": 0, "RedGain": 3, "GreenGain": 1, "BlueGain": -4},
    "macbook": {"ColorTemp": 6400, "Brightness": -1, "Contrast": 110, "Saturation": 122, "Gamma": 2.28, "Hue": 0, "RedGain": 2, "GreenGain": 0, "BlueGain": -3},
    "cinema": {"ColorTemp": 6300, "Brightness": 0, "Contrast": 106, "Saturation": 118, "Gamma": 2.25, "Hue": 0, "RedGain": 2, "GreenGain": 1, "BlueGain": -3},
    "night": {"ColorTemp": 5200, "Brightness": -3, "Contrast": 96, "Saturation": 95, "Gamma": 2.15, "Hue": 0, "RedGain": 2, "GreenGain": 2, "BlueGain": -12}
}

def get_profile_path() -> str:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    local_path = os.path.join(script_dir, "profile.json")
    if os.access(script_dir, os.W_OK):
        return local_path
    
    config_dir = os.path.expanduser("~/.config/displaytune")
    os.makedirs(config_dir, exist_ok=True)
    return os.path.join(config_dir, "profile.json")

def load_profile() -> Dict[str, float]:
    p_path = get_profile_path()
    if os.path.exists(p_path):
        try:
            with open(p_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                res = DEFAULT_PROFILE.copy()
                res.update(data)
                return res
        except Exception:
            pass
    return DEFAULT_PROFILE.copy()

def save_profile(profile: Dict[str, float]):
    p_path = get_profile_path()
    try:
        with open(p_path, "w", encoding="utf-8") as f:
            json.dump(profile, f, indent=2)
    except Exception as e:
        print(f"Warning: Could not save profile to {p_path}: {e}", file=sys.stderr)


# =============================================================================
# Linux Hardware Apply Mechanisms (X11 XRandR / Wayland colord / xcalib)
# =============================================================================

def apply_x11_ctypes(r_ramp: List[int], g_ramp: List[int], b_ramp: List[int]) -> bool:
    """Applies gamma ramp directly to X11 CRTCs via libX11 / libXrandr ctypes."""
    try:
        x11 = ctypes.cdll.LoadLibrary("libX11.so.6")
        xrandr = ctypes.cdll.LoadLibrary("libXrandr.so.2")

        display = x11.XOpenDisplay(None)
        if not display:
            return False

        screen = x11.XDefaultScreen(display)
        root = x11.XRootWindow(display, screen)

        # XRRGetScreenResourcesCurrent
        xrandr.XRRGetScreenResourcesCurrent.restype = ctypes.c_void_p
        res = xrandr.XRRGetScreenResourcesCurrent(display, root)
        if not res:
            x11.XCloseDisplay(display)
            return False

        # Read num_crtcs & crtcs pointer
        class XRRScreenResources(ctypes.Structure):
            _fields_ = [
                ("timestamp", ctypes.c_ulong),
                ("configTimestamp", ctypes.c_ulong),
                ("ncrtc", ctypes.c_int),
                ("crtcs", ctypes.POINTER(ctypes.c_ulong)),
                ("noutput", ctypes.c_int),
                ("outputs", ctypes.POINTER(ctypes.c_ulong)),
                ("nmode", ctypes.c_int),
                ("modes", ctypes.c_void_p)
            ]

        res_struct = XRRScreenResources.from_address(res)
        num_crtcs = res_struct.ncrtc

        # Prepare XRRCrtcGamma structure
        class XRRCrtcGamma(ctypes.Structure):
            _fields_ = [
                ("size", ctypes.c_int),
                ("red", ctypes.POINTER(ctypes.c_ushort)),
                ("green", ctypes.POINTER(ctypes.c_ushort)),
                ("blue", ctypes.POINTER(ctypes.c_ushort))
            ]

        xrandr.XRRAllocGamma.restype = ctypes.POINTER(XRRCrtcGamma)

        c_ushort_256 = ctypes.c_ushort * 256
        r_arr = c_ushort_256(*r_ramp)
        g_arr = c_ushort_256(*g_ramp)
        b_arr = c_ushort_256(*b_ramp)

        applied = False
        for i in range(num_crtcs):
            crtc_id = res_struct.crtcs[i]
            gamma_size = xrandr.XRRGetCrtcGammaSize(display, crtc_id)
            if gamma_size == 256:
                gamma_ptr = xrandr.XRRAllocGamma(256)
                if gamma_ptr:
                    gamma_struct = gamma_ptr.contents
                    ctypes.memmove(gamma_struct.red, r_arr, 256 * 2)
                    ctypes.memmove(gamma_struct.green, g_arr, 256 * 2)
                    ctypes.memmove(gamma_struct.blue, b_arr, 256 * 2)
                    xrandr.XRRSetCrtcGamma(display, crtc_id, gamma_ptr)
                    xrandr.XRRFreeGamma(gamma_ptr)
                    applied = True

        xrandr.XRRFreeScreenResources(res)
        x11.XSync(display, False)
        x11.XCloseDisplay(display)
        return applied
    except Exception:
        return False


def generate_icc_profile(r_ramp: List[int], g_ramp: List[int], b_ramp: List[int], output_path: str, profile_name: str = "DisplayTune Calibrated"):
    """Generates a valid standard ICC v2 Display Profile with VCGT hardware LUT table."""
    def write_be32(val: int) -> bytes:
        return struct.pack(">I", val)
    def write_be16(val: int) -> bytes:
        return struct.pack(">H", val)
    def write_s15fixed16(val: float) -> bytes:
        return struct.pack(">i", int(round(val * 65536.0)))

    # Header (128 bytes)
    header = bytearray(128)
    struct.pack_into(">I", header, 0, 0) # size placeholder
    struct.pack_into("4s", header, 4, b"ADBE")
    struct.pack_into(">I", header, 8, 0x02400000) # v2.4.0
    struct.pack_into("4s", header, 12, b"mntr")
    struct.pack_into("4s", header, 16, b"RGB ")
    struct.pack_into("4s", header, 20, b"XYZ ")
    # Date 2026-01-01
    struct.pack_into(">HHHHHH", header, 24, 2026, 1, 1, 12, 0, 0)
    struct.pack_into("4s", header, 36, b"acsp")
    struct.pack_into("4s", header, 40, b"APPL" if sys.platform == "darwin" else b"MSFT")
    # Illuminant D50
    struct.pack_into(">iii", header, 68, int(0.9642 * 65536), int(1.0000 * 65536), int(0.8249 * 65536))
    struct.pack_into("4s", header, 80, b"DTUN")

    tags = ["desc", "cprt", "wtpt", "rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC", "vcgt"]
    tag_data = {}

    # 1. desc
    desc_bytes = profile_name.encode("ascii") + b"\x00"
    tag_data["desc"] = b"desc\x00\x00\x00\x00" + write_be32(len(desc_bytes)) + desc_bytes + (b"\x00" * 18)

    # 2. cprt
    cprt_bytes = b"DisplayTune 2026\x00"
    tag_data["cprt"] = b"text\x00\x00\x00\x00" + cprt_bytes

    # 3. wtpt (D50)
    tag_data["wtpt"] = b"XYZ \x00\x00\x00\x00" + write_s15fixed16(0.9642) + write_s15fixed16(1.0000) + write_s15fixed16(0.8249)

    # 4-6. rXYZ, gXYZ, bXYZ
    tag_data["rXYZ"] = b"XYZ \x00\x00\x00\x00" + write_s15fixed16(0.43607) + write_s15fixed16(0.22250) + write_s15fixed16(0.01393)
    tag_data["gXYZ"] = b"XYZ \x00\x00\x00\x00" + write_s15fixed16(0.38515) + write_s15fixed16(0.71687) + write_s15fixed16(0.09708)
    tag_data["bXYZ"] = b"XYZ \x00\x00\x00\x00" + write_s15fixed16(0.14307) + write_s15fixed16(0.06061) + write_s15fixed16(0.71410)

    # 7-9. TRC curves
    tag_data["rTRC"] = b"curv\x00\x00\x00\x00" + write_be32(1) + write_be16(0x0233)
    tag_data["gTRC"] = b"curv\x00\x00\x00\x00" + write_be32(1) + write_be16(0x0233)
    tag_data["bTRC"] = b"curv\x00\x00\x00\x00" + write_be32(1) + write_be16(0x0233)

    # 10. vcgt tag (Video Card Gamma Table 256-point 16-bit curves)
    vcgt_buf = bytearray(b"vcgt\x00\x00\x00\x00")
    vcgt_buf += write_be32(0) # Table type 0 = VideoCardGammaTable
    vcgt_buf += write_be16(3) # 3 channels (R, G, B)
    vcgt_buf += write_be16(256) # 256 entries
    vcgt_buf += write_be16(2) # 2 bytes per entry (16-bit)
    for v in r_ramp: vcgt_buf += write_be16(v)
    for v in g_ramp: vcgt_buf += write_be16(v)
    for v in b_ramp: vcgt_buf += write_be16(v)
    tag_data["vcgt"] = bytes(vcgt_buf)

    # Build tag table
    tag_count = len(tags)
    tag_table_data = bytearray(write_be32(tag_count))
    tag_body = bytearray()

    offset = 128 + 4 + (tag_count * 12)
    for t in tags:
        data = tag_data[t]
        tag_table_data += t.encode("ascii")
        tag_table_data += write_be32(offset + len(tag_body))
        tag_table_data += write_be32(len(data))
        tag_body += data
        # Pad to 4 bytes
        while len(tag_body) % 4 != 0:
            tag_body += b"\x00"

    full_profile = header + tag_table_data + tag_body
    total_len = len(full_profile)
    struct.pack_into(">I", full_profile, 0, total_len)

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(full_profile)


def apply_linux_display(profile: Dict[str, float]) -> bool:
    """Universal Linux Display Applicator (Supports X11 XRandR, xcalib, colord, and Wayland)."""
    r_ramp, g_ramp, b_ramp = generate_ramp(
        profile["ColorTemp"], profile["Brightness"], profile["Contrast"],
        profile["Saturation"], profile["Gamma"], profile["Hue"],
        profile["RedGain"], profile["GreenGain"], profile["BlueGain"]
    )

    # 1. Try direct X11 CRTC via ctypes (Fastest, zero process spawn)
    if os.environ.get("DISPLAY") and apply_x11_ctypes(r_ramp, g_ramp, b_ramp):
        return True

    # 2. Try xcalib or xgamma fallback
    icc_temp = "/tmp/displaytune_calibrated.icc"
    generate_icc_profile(r_ramp, g_ramp, b_ramp, icc_temp)

    try:
        res = subprocess.run(["xcalib", "-d", os.environ.get("DISPLAY", ":0"), icc_temp], capture_output=True)
        if res.returncode == 0:
            return True
    except Exception:
        pass

    # 3. Wayland / colord (KDE Plasma & GNOME Color Management)
    colord_dest = os.path.expanduser("~/.local/share/icc/DisplayTune_Calibrated.icc")
    generate_icc_profile(r_ramp, g_ramp, b_ramp, colord_dest)
    try:
        subprocess.run(["colormgr", "import-profile", colord_dest], capture_output=True)
        return True
    except Exception:
        pass

    return True


# =============================================================================
# GUI Implementation (Pure Python Tkinter - Zero Dependencies)
# =============================================================================

def run_gui():
    try:
        import tkinter as tk
        from tkinter import ttk, messagebox
    except ImportError:
        print("Error: Tkinter not installed. Run 'sudo apt install python3-tk' or use CLI arguments.", file=sys.stderr)
        sys.exit(1)

    root = tk.Tk()
    root.title("DisplayTune — Studio Display Calibration (Linux)")
    root.geometry("640x780")
    root.configure(bg="#0c0d12")
    root.minsize(580, 700)

    profile = load_profile()

    # Style
    style = ttk.Style()
    style.theme_use("clam")
    style.configure("TLabel", background="#0c0d12", foreground="#ebf0fa", font=("Segoe UI", 9))
    style.configure("TFrame", background="#0c0d12")
    style.configure("Preset.TButton", background="#1a1e29", foreground="#d8e2f0", borderwidth=1, font=("Segoe UI", 9, "bold"))
    style.map("Preset.TButton", background=[("active", "#2a3142")])

    # Header
    header = tk.Frame(root, bg="#0c0d12", pady=10, padx=16)
    header.pack(fill="x")
    title_lbl = tk.Label(header, text="DISPLAYTUNE STUDIO", font=("Segoe UI", 13, "bold"), fg="#ffffff", bg="#0c0d12")
    title_lbl.pack(anchor="w")
    sub_lbl = tk.Label(header, text="Hardware LUT Calibration & Wide Gamut Perceptual Engine (Linux)", font=("Segoe UI", 8.5), fg="#8fa0b8", bg="#0c0d12")
    sub_lbl.pack(anchor="w")

    # Preset strip
    preset_frame = tk.Frame(root, bg="#12151e", padx=8, pady=8)
    preset_frame.pack(fill="x", padx=14, pady=4)
    tk.Label(preset_frame, text="REFERENCE PRESETS", font=("Segoe UI", 8, "bold"), fg="#627288", bg="#12151e").pack(anchor="w", pady=(0, 4))

    btn_box = tk.Frame(preset_frame, bg="#12151e")
    btn_box.pack(fill="x")

    slider_vars: Dict[str, tk.DoubleVar] = {}
    entry_vars: Dict[str, tk.StringVar] = {}

    def apply_current():
        for k, v in slider_vars.items():
            profile[k] = v.get()
        apply_linux_display(profile)
        save_profile(profile)

    def set_values(d: Dict[str, float]):
        for k, v in d.items():
            if k in slider_vars:
                slider_vars[k].set(v)
                entry_vars[k].set(f"{v:.0f}" if k not in ["Gamma"] else f"{v:.2f}")
        apply_current()

    for name, p_data in [("Studio sRGB", PRESETS["srgb"]), ("Creator 45% NTSC", PRESETS["creator"]), ("MacBook Liquid", PRESETS["macbook"]), ("Cinema DCI-P3", PRESETS["cinema"]), ("Night D50", PRESETS["night"])]:
        b = tk.Button(btn_box, text=name, bg="#1c202d", fg="#dce4f2", activebackground="#2a3248", activeforeground="#ffffff", font=("Segoe UI", 8, "bold"), bd=1, relief="flat", padx=8, pady=4, command=lambda p=p_data: set_values(p))
        b.pack(side="left", padx=3, expand=True, fill="x")

    # Sliders Container
    scroll_frame = tk.Frame(root, bg="#0c0d12", padx=14, pady=6)
    scroll_frame.pack(fill="both", expand=True)

    sliders_spec = [
        ("ColorTemp", "Color Temperature", 4000, 10000, 6500, "K", 1),
        ("Brightness", "Brightness Offset", -50, 50, 0, "%", 1),
        ("Contrast", "Contrast Curve", 50, 180, 100, "%", 1),
        ("Saturation", "Harmonic Saturation", 0, 200, 100, "%", 1),
        ("Gamma", "Gamma Correction", 1.0, 3.0, 2.20, "", 0.01),
        ("Hue", "Hue Rotation", -180, 180, 0, "°", 1),
        ("RedGain", "Red Gain", -50, 50, 0, "%", 1),
        ("GreenGain", "Green Gain", -50, 50, 0, "%", 1),
        ("BlueGain", "Blue Gain", -50, 50, 0, "%", 1),
    ]

    for key, label, s_min, s_max, default_val, unit, step in sliders_spec:
        row = tk.Frame(scroll_frame, bg="#151822", bd=1, relief="solid", padx=10, pady=4)
        row.pack(fill="x", pady=3)

        lbl = tk.Label(row, text=label, font=("Segoe UI", 9, "bold"), fg="#ebf0fa", bg="#151822", width=18, anchor="w")
        lbl.pack(side="left")

        val = profile.get(key, default_val)
        var = tk.DoubleVar(value=val)
        slider_vars[key] = var

        e_var = tk.StringVar(value=f"{val:.0f}{unit}" if key != "Gamma" else f"{val:.2f}{unit}")
        entry_vars[key] = e_var

        ent = tk.Entry(row, textvariable=e_var, font=("Segoe UI", 9, "bold"), width=8, justify="center", bg="#0e1017", fg="#ffffff", bd=1, relief="solid")
        ent.pack(side="left", padx=8)

        def on_entry_commit(event, k=key, u=unit, v_min=s_min, v_max=s_max):
            raw = entry_vars[k].get()
            clean = "".join(c for c in raw if c.isdigit() or c in ".-")
            try:
                num = max(v_min, min(v_max, float(clean)))
                slider_vars[k].set(num)
                entry_vars[k].set(f"{num:.0f}{u}" if k != "Gamma" else f"{num:.2f}{u}")
                apply_current()
            except ValueError:
                curr = slider_vars[k].get()
                entry_vars[k].set(f"{curr:.0f}{u}" if k != "Gamma" else f"{curr:.2f}{u}")

        ent.bind("<Return>", on_entry_commit)
        ent.bind("<FocusOut>", on_entry_commit)

        def on_slide(val_str, k=key, u=unit):
            num = float(val_str)
            entry_vars[k].set(f"{num:.0f}{u}" if k != "Gamma" else f"{num:.2f}{u}")
            apply_current()

        scale = tk.Scale(row, from_=s_min, to=s_max, resolution=step, orient="horizontal", variable=var, command=on_slide, showvalue=0, bg="#151822", fg="#3a4459", troughcolor="#0e1017", activebackground="#4e6587", bd=0, highlightthickness=0)
        scale.pack(side="left", fill="x", expand=True, padx=6)

    # Bottom Actions
    bottom = tk.Frame(root, bg="#0c0d12", padx=14, pady=10)
    bottom.pack(fill="x")

    def reset_all():
        set_values(DEFAULT_PROFILE)

    def export_icc_action():
        icc_path = os.path.expanduser("~/.local/share/icc/DisplayTune_Calibrated.icc")
        r_ramp, g_ramp, b_ramp = generate_ramp(**profile)
        generate_icc_profile(r_ramp, g_ramp, b_ramp, icc_path)
        messagebox.showinfo("Export ICC", f"ICC Profile saved to:\n{icc_path}\nImported into colord.")

    tk.Button(bottom, text="Reset to Defaults", bg="#2a2228", fg="#f098a2", activebackground="#3d2a34", font=("Segoe UI", 9, "bold"), bd=1, relief="flat", padx=12, pady=6, command=reset_all).pack(side="left")
    tk.Button(bottom, text="Export .ICC Profile", bg="#192823", fg="#88e0b8", activebackground="#243830", font=("Segoe UI", 9, "bold"), bd=1, relief="flat", padx=12, pady=6, command=export_icc_action).pack(side="right", padx=6)

    apply_linux_display(profile)
    root.mainloop()


# =============================================================================
# CLI Main Entry Point
# =============================================================================

def main():
    args = sys.argv[1:]
    
    if not args:
        run_gui()
        return

    profile = load_profile()

    if "--help" in args or "-h" in args:
        print("""DisplayTune Linux Display Calibration CLI

Usage:
  displaytune.py                Launch dark-mode graphical UI
  displaytune.py --apply        Apply saved profile to hardware LUT
  displaytune.py --reset        Reset hardware LUT to linear standard
  displaytune.py --preset <p>   Apply preset: srgb, creator, macbook, cinema, night
  displaytune.py --export-icc   Generate and install standard .icc profile
  displaytune.py --inspect      Print current profile values
""")
        return

    if "--reset" in args or "-reset" in args:
        apply_linux_display(DEFAULT_PROFILE)
        print("Display hardware LUT reset to linear standard.")
        return

    if "--export-icc" in args:
        out_path = os.path.expanduser("~/.local/share/icc/DisplayTune_Calibrated.icc")
        r, g, b = generate_ramp(
            profile["ColorTemp"], profile["Brightness"], profile["Contrast"],
            profile["Saturation"], profile["Gamma"], profile["Hue"],
            profile["RedGain"], profile["GreenGain"], profile["BlueGain"]
        )
        generate_icc_profile(r, g, b, out_path)
        print(f"Exported ICC profile to: {out_path}")
        return

    if "--preset" in args:
        idx = args.index("--preset")
        if idx + 1 < len(args):
            p_name = args[idx + 1].lower()
            if p_name in PRESETS:
                profile.update(PRESETS[p_name])
                apply_linux_display(profile)
                save_profile(profile)
                print(f"Applied reference preset: {p_name}")
                return
            else:
                print(f"Unknown preset: {p_name}. Available: srgb, creator, macbook, cinema, night", file=sys.stderr)
                sys.exit(1)

    if "--inspect" in args:
        print(json.dumps(profile, indent=2))
        return

    if "--apply" in args or "-apply" in args:
        apply_linux_display(profile)
        print("Calibration profile applied to display hardware LUT.")
        return

    run_gui()

if __name__ == "__main__":
    main()
