using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace DisplayTune {
    // =========================================================================
    // Win32 GDI Display Driver Interop
    // =========================================================================
    public static class DisplayGdi {
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
            RAMP ramp = new RAMP {
                Red = new ushort[256],
                Green = new ushort[256],
                Blue = new ushort[256]
            };

            // 1. Color Temperature (Planckian locus)
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
                val = (val > 0.0) ? Math.Pow(val, gExp) : 0.0;

                // Harmonic chroma wave expansion
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

            // Driver Monotonicity Enforcement
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
    }

    // =========================================================================
    // Profile Data Model & JSON Persistence
    // =========================================================================
    public class DisplayProfile {
        public double ColorTemp { get; set; }
        public double Brightness { get; set; }
        public double Contrast { get; set; }
        public double Saturation { get; set; }
        public double Gamma { get; set; }
        public double Hue { get; set; }
        public double RedGain { get; set; }
        public double GreenGain { get; set; }
        public double BlueGain { get; set; }

        public DisplayProfile() {
            ColorTemp = 6500;
            Brightness = 0;
            Contrast = 100;
            Saturation = 100;
            Gamma = 2.20;
            Hue = 0;
            RedGain = 0;
            GreenGain = 0;
            BlueGain = 0;
        }

        public static string GetProfilePath() {
            try {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string localPath = Path.Combine(baseDir, "profile.json");
                // Test write permission
                string testFile = Path.Combine(baseDir, ".test_write.tmp");
                File.WriteAllText(testFile, "test");
                File.Delete(testFile);
                return localPath;
            } catch {
                string appData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DisplayTune");
                if (!Directory.Exists(appData)) Directory.CreateDirectory(appData);
                return Path.Combine(appData, "profile.json");
            }
        }

        public void Save() {
            try {
                string path = GetProfilePath();
                StringBuilder sb = new StringBuilder();
                sb.AppendLine("{");
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  \"ColorTemp\": {0:F0},", ColorTemp));
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  \"Brightness\": {0:F0},", Brightness));
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  \"Contrast\": {0:F0},", Contrast));
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  \"Saturation\": {0:F0},", Saturation));
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  \"Gamma\": {0:F2},", Gamma));
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  \"Hue\": {0:F0},", Hue));
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  \"RedGain\": {0:F0},", RedGain));
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  \"GreenGain\": {0:F0},", GreenGain));
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  \"BlueGain\": {0:F0}", BlueGain));
                sb.AppendLine("}");
                File.WriteAllText(path, sb.ToString(), Encoding.UTF8);
            } catch { }
        }

        public static DisplayProfile Load() {
            DisplayProfile p = new DisplayProfile();
            try {
                string path = GetProfilePath();
                if (File.Exists(path)) {
                    string[] lines = File.ReadAllLines(path);
                    foreach (string line in lines) {
                        string l = line.Trim().TrimEnd(',');
                        if (l.Contains(":")) {
                            string[] parts = l.Split(':');
                            string key = parts[0].Trim().Trim('"');
                            string valStr = parts[1].Trim();
                            double val;
                            if (double.TryParse(valStr, NumberStyles.Any, CultureInfo.InvariantCulture, out val)) {
                                if (key.Equals("ColorTemp", StringComparison.OrdinalIgnoreCase)) p.ColorTemp = val;
                                else if (key.Equals("Brightness", StringComparison.OrdinalIgnoreCase)) p.Brightness = val;
                                else if (key.Equals("Contrast", StringComparison.OrdinalIgnoreCase)) p.Contrast = val;
                                else if (key.Equals("Saturation", StringComparison.OrdinalIgnoreCase)) p.Saturation = val;
                                else if (key.Equals("Gamma", StringComparison.OrdinalIgnoreCase)) p.Gamma = val;
                                else if (key.Equals("Hue", StringComparison.OrdinalIgnoreCase)) p.Hue = val;
                                else if (key.Equals("RedGain", StringComparison.OrdinalIgnoreCase)) p.RedGain = val;
                                else if (key.Equals("GreenGain", StringComparison.OrdinalIgnoreCase)) p.GreenGain = val;
                                else if (key.Equals("BlueGain", StringComparison.OrdinalIgnoreCase)) p.BlueGain = val;
                            }
                        }
                    }
                }
            } catch { }
            return p;
        }
    }

    // =========================================================================
    // Hardware Info Provider
    // =========================================================================
    public static class HardwareInfo {
        public static string PanelModel = "Standard Display Panel";
        public static string Resolution = "1920 x 1080";
        public static string RefreshRate = "60 Hz";
        public static string Gpus = "Integrated Graphics";

        public static void Query() {
            try {
                using (ManagementObjectSearcher mos = new ManagementObjectSearcher(@"root\wmi", "SELECT * FROM WmiMonitorID")) {
                    foreach (ManagementObject mo in mos.Get()) {
                        byte[] mfgBytes = (byte[])mo["ManufacturerName"];
                        byte[] prodBytes = (byte[])mo["ProductCodeID"];
                        byte[] userBytes = (byte[])mo["UserFriendlyName"];

                        string mfg = DecodeBytes(mfgBytes);
                        string prod = DecodeBytes(prodBytes);
                        string user = DecodeBytes(userBytes);

                        if (!string.IsNullOrEmpty(user)) PanelModel = user;
                        else if (mfg == "BOE" && prod == "0D39") PanelModel = "BOE NE156FHM-NXA";
                        else if (!string.IsNullOrEmpty(mfg) || !string.IsNullOrEmpty(prod)) PanelModel = (mfg + " " + prod).Trim();
                        break;
                    }
                }
            } catch { }

            try {
                using (ManagementObjectSearcher mos = new ManagementObjectSearcher("SELECT * FROM Win32_VideoController WHERE CurrentHorizontalResolution > 0")) {
                    List<string> gpuList = new List<string>();
                    foreach (ManagementObject mo in mos.Get()) {
                        string name = (string)mo["Name"];
                        if (!string.IsNullOrEmpty(name)) gpuList.Add(name);

                        uint h = Convert.ToUInt32(mo["CurrentHorizontalResolution"]);
                        uint v = Convert.ToUInt32(mo["CurrentVerticalResolution"]);
                        uint hz = Convert.ToUInt32(mo["CurrentRefreshRate"]);
                        if (h > 0 && v > 0) {
                            Resolution = h + " x " + v;
                            if (hz > 0) RefreshRate = hz + " Hz";
                        }
                    }
                    if (gpuList.Count > 0) Gpus = string.Join(" + ", gpuList.ToArray());
                }
            } catch { }
        }

        private static string DecodeBytes(byte[] bytes) {
            if (bytes == null) return "";
            StringBuilder sb = new StringBuilder();
            foreach (byte b in bytes) {
                if (b > 0) sb.Append((char)b);
            }
            return sb.ToString().Trim();
        }
    }

    // =========================================================================
    // Main UI Form
    // =========================================================================
    public class MainForm : Form {
        private class SliderControl {
            public string Name;
            public string Label;
            public double Min;
            public double Max;
            public double Default;
            public double Scale;
            public string Unit;
            public string Format;
            public Panel Panel;
            public Label LblTitle;
            public TextBox TxtVal;
            public TrackBar Track;
        }

        private Dictionary<string, SliderControl> sliders = new Dictionary<string, SliderControl>();
        private int currentY = 10;
        private Panel panelScroll;

        public MainForm() {
            Text = "DisplayTune - Studio Display Color Controller";
            Size = new Size(1000, 760);
            MinimumSize = new Size(920, 660);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(15, 17, 23);
            ForeColor = Color.FromArgb(240, 240, 245);
            Font = new Font("Segoe UI", 9.5f);
            DoubleBuffered = true;

            HardwareInfo.Query();
            BuildLayout();
            LoadProfileToUI();
            ApplyAllSliders();
        }

        private void BuildLayout() {
            // Header
            Panel headerPanel = new Panel {
                Location = new Point(16, 12),
                Size = new Size(ClientSize.Width - 32, 60),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = Color.FromArgb(22, 25, 34),
                BorderStyle = BorderStyle.FixedSingle
            };
            Controls.Add(headerPanel);

            Label lblHeader = new Label {
                Text = "Custom Color Controls | " + HardwareInfo.PanelModel + " (" + HardwareInfo.Resolution + " @ " + HardwareInfo.RefreshRate + ")",
                Font = new Font("Segoe UI", 11f, FontStyle.Bold),
                ForeColor = Color.FromArgb(245, 75, 75),
                Location = new Point(15, 9),
                AutoSize = true
            };
            headerPanel.Controls.Add(lblHeader);

            Label lblSub = new Label {
                Text = "Direct Hardware LUT Pipeline | Type value or drag slider | Double-click label to reset item",
                ForeColor = Color.FromArgb(155, 165, 185),
                Location = new Point(15, 32),
                AutoSize = true
            };
            headerPanel.Controls.Add(lblSub);

            Button btnResetTop = new Button {
                Text = "Reset to Default",
                Location = new Point(headerPanel.ClientSize.Width - 155, 13),
                Size = new Size(140, 34),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                BackColor = Color.FromArgb(40, 44, 56),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 9f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btnResetTop.FlatAppearance.BorderColor = Color.FromArgb(60, 66, 82);
            btnResetTop.Click += (s, e) => ResetAllToDefaults();
            headerPanel.Controls.Add(btnResetTop);

            // Presets Bar
            Panel presetPanel = new Panel {
                Location = new Point(16, 78),
                Size = new Size(ClientSize.Width - 32, 44),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = Color.FromArgb(18, 20, 28),
                BorderStyle = BorderStyle.FixedSingle
            };
            Controls.Add(presetPanel);

            Label lblPresetTitle = new Label {
                Text = "Studio Presets:",
                Font = new Font("Segoe UI", 9f, FontStyle.Bold),
                ForeColor = Color.FromArgb(160, 170, 195),
                Location = new Point(12, 12),
                AutoSize = true
            };
            presetPanel.Controls.Add(lblPresetTitle);

            AddPresetButton(presetPanel, "Studio sRGB", 115, 6500, 0, 100, 100, 2.20, 0, 0, 0, 0);
            AddPresetButton(presetPanel, "Creator 45% NTSC", 277, 6350, 0, 108, 128, 2.26, 0, 3, 1, -4);
            AddPresetButton(presetPanel, "MacBook Liquid P3", 439, 6400, -1, 110, 122, 2.28, 0, 2, 0, -3);
            AddPresetButton(presetPanel, "Cinema DCI-P3", 601, 6300, 0, 106, 118, 2.25, 0, 2, 1, -3);
            AddPresetButton(presetPanel, "Night D50 Reading", 763, 5200, -3, 96, 95, 2.15, 0, 2, 2, -12);

            // Left Column (Scrollable Sliders)
            panelScroll = new Panel {
                Location = new Point(16, 130),
                Size = new Size(ClientSize.Width - 350, ClientSize.Height - 146),
                Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right,
                AutoScroll = true
            };
            Controls.Add(panelScroll);

            // Right Column (Preview Pattern & Startup Button)
            GroupBox grpPreview = new GroupBox {
                Text = " Live Calibration Pattern ",
                Location = new Point(ClientSize.Width - 324, 130),
                Size = new Size(308, ClientSize.Height - 146),
                Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Right,
                ForeColor = Color.FromArgb(200, 210, 230)
            };
            Controls.Add(grpPreview);

            PictureBox pb = new PictureBox {
                Location = new Point(12, 25),
                Size = new Size(282, grpPreview.ClientSize.Height - 90),
                Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = Color.Black,
                BorderStyle = BorderStyle.FixedSingle,
                SizeMode = PictureBoxSizeMode.StretchImage,
                Image = GenerateCalibrationPattern(282, 465)
            };
            grpPreview.Controls.Add(pb);

            Button btnStartup = new Button {
                Text = "Save as Windows Startup Profile",
                Location = new Point(12, grpPreview.ClientSize.Height - 55),
                Size = new Size(282, 45),
                Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = Color.FromArgb(35, 125, 60),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btnStartup.FlatAppearance.BorderColor = Color.FromArgb(45, 150, 75);
            btnStartup.Click += (s, e) => SaveAsStartup();
            grpPreview.Controls.Add(btnStartup);

            // --- SECTION 1: PRIMARY CONTROLS ---
            Label lblCore = new Label {
                Text = "PRIMARY DISPLAY CONTROLS",
                Font = new Font("Segoe UI", 9f, FontStyle.Bold),
                ForeColor = Color.FromArgb(140, 150, 175),
                Location = new Point(10, currentY),
                Size = new Size(300, 18)
            };
            panelScroll.Controls.Add(lblCore);
            currentY += 22;

            AddSlider("ColorTemp", "Color Temperature", 4000, 10000, 6500, 1.0, " K", "F0");
            AddSlider("Brightness", "Brightness", -100, 100, 0, 1.0, "", "F0");
            AddSlider("Contrast", "Contrast", 0, 200, 100, 1.0, "", "F0");
            AddSlider("Saturation", "Saturation", 0, 200, 100, 1.0, "", "F0");

            currentY += 10;

            // --- SECTION 2: ADVANCED CONTROLS ---
            Label lblAdv = new Label {
                Text = "ADVANCED PRECISION TUNING",
                Font = new Font("Segoe UI", 9f, FontStyle.Bold),
                ForeColor = Color.FromArgb(140, 150, 175),
                Location = new Point(10, currentY),
                Size = new Size(300, 18)
            };
            panelScroll.Controls.Add(lblAdv);
            currentY += 22;

            AddSlider("Gamma", "Gamma", 1.0, 3.0, 2.20, 100.0, "", "F2");
            AddSlider("Hue", "Hue", -30, 30, 0, 1.0, "°", "F0");
            AddSlider("RedGain", "Red Balance", -50, 50, 0, 1.0, "%", "F0");
            AddSlider("GreenGain", "Green Balance", -50, 50, 0, 1.0, "%", "F0");
            AddSlider("BlueGain", "Blue Balance", -50, 50, 0, 1.0, "%", "F0");
        }

        private void AddPresetButton(Panel parent, string text, int x, double temp, double bri, double con, double sat, double gam, double hue, double r, double g, double b) {
            Button btn = new Button {
                Text = text,
                Location = new Point(x, 7),
                Size = new Size(155, 28),
                BackColor = Color.FromArgb(32, 36, 48),
                ForeColor = Color.FromArgb(230, 235, 245),
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btn.FlatAppearance.BorderColor = Color.FromArgb(55, 62, 78);
            btn.Click += (s, e) => {
                SetSliderValue("ColorTemp", temp);
                SetSliderValue("Brightness", bri);
                SetSliderValue("Contrast", con);
                SetSliderValue("Saturation", sat);
                SetSliderValue("Gamma", gam);
                SetSliderValue("Hue", hue);
                SetSliderValue("RedGain", r);
                SetSliderValue("GreenGain", g);
                SetSliderValue("BlueGain", b);
                ApplyAllSliders();
            };
            parent.Controls.Add(btn);
        }

        private void AddSlider(string name, string label, double min, double max, double defVal, double scale, string unit, string format) {
            Panel row = new Panel {
                Location = new Point(10, currentY),
                Size = new Size(panelScroll.ClientSize.Width - 30, 54),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = Color.FromArgb(22, 25, 34),
                BorderStyle = BorderStyle.FixedSingle
            };
            panelScroll.Controls.Add(row);

            Label lbl = new Label {
                Text = label,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(235, 240, 250),
                Location = new Point(12, 16),
                Size = new Size(165, 22),
                Cursor = Cursors.Hand
            };
            row.Controls.Add(lbl);

            TextBox txt = new TextBox {
                Text = defVal.ToString(format, CultureInfo.InvariantCulture) + unit,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                TextAlign = HorizontalAlignment.Center,
                Location = new Point(182, 14),
                Size = new Size(80, 24),
                BackColor = Color.FromArgb(14, 16, 22),
                ForeColor = Color.FromArgb(240, 245, 255),
                BorderStyle = BorderStyle.FixedSingle
            };
            row.Controls.Add(txt);

            TrackBar trk = new TrackBar {
                Location = new Point(272, 12),
                Size = new Size(row.ClientSize.Width - 280, 30),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                Minimum = (int)Math.Round(min * scale),
                Maximum = (int)Math.Round(max * scale),
                Value = (int)Math.Round(defVal * scale),
                TickStyle = TickStyle.None,
                BackColor = Color.FromArgb(22, 25, 34)
            };
            row.Controls.Add(trk);

            SliderControl sc = new SliderControl {
                Name = name,
                Label = label,
                Min = min,
                Max = max,
                Default = defVal,
                Scale = scale,
                Unit = unit,
                Format = format,
                Panel = row,
                LblTitle = lbl,
                TxtVal = txt,
                Track = trk
            };
            sliders[name] = sc;

            trk.Scroll += (s, e) => {
                double val = trk.Value / scale;
                txt.Text = val.ToString(format, CultureInfo.InvariantCulture) + unit;
                ApplyAllSliders();
            };

            Action commitText = () => {
                string raw = txt.Text;
                // Remove unit / letters except digits, dot, minus
                StringBuilder clean = new StringBuilder();
                foreach (char c in raw) {
                    if (char.IsDigit(c) || c == '.' || c == '-') clean.Append(c);
                }
                double parsed;
                if (double.TryParse(clean.ToString(), NumberStyles.Any, CultureInfo.InvariantCulture, out parsed)) {
                    parsed = Math.Max(min, Math.Min(max, parsed));
                    trk.Value = (int)Math.Round(parsed * scale);
                    txt.Text = parsed.ToString(format, CultureInfo.InvariantCulture) + unit;
                    ApplyAllSliders();
                } else {
                    double curr = trk.Value / scale;
                    txt.Text = curr.ToString(format, CultureInfo.InvariantCulture) + unit;
                }
            };

            txt.Enter += (s, e) => txt.SelectAll();
            txt.Leave += (s, e) => commitText();
            txt.KeyDown += (s, e) => {
                if (e.KeyCode == Keys.Enter) {
                    e.SuppressKeyPress = true;
                    commitText();
                    row.Focus();
                }
            };

            lbl.DoubleClick += (s, e) => {
                trk.Value = (int)Math.Round(defVal * scale);
                txt.Text = defVal.ToString(format, CultureInfo.InvariantCulture) + unit;
                ApplyAllSliders();
            };

            currentY += 60;
        }

        private void SetSliderValue(string name, double val) {
            if (sliders.ContainsKey(name)) {
                SliderControl sc = sliders[name];
                double clamped = Math.Max(sc.Min, Math.Min(sc.Max, val));
                sc.Track.Value = (int)Math.Round(clamped * sc.Scale);
                sc.TxtVal.Text = clamped.ToString(sc.Format, CultureInfo.InvariantCulture) + sc.Unit;
            }
        }

        private double GetSliderValue(string name) {
            if (sliders.ContainsKey(name)) {
                SliderControl sc = sliders[name];
                return sc.Track.Value / sc.Scale;
            }
            return 0;
        }

        private void ApplyAllSliders() {
            DisplayProfile p = new DisplayProfile {
                ColorTemp = GetSliderValue("ColorTemp"),
                Brightness = GetSliderValue("Brightness"),
                Contrast = GetSliderValue("Contrast"),
                Saturation = GetSliderValue("Saturation"),
                Gamma = GetSliderValue("Gamma"),
                Hue = GetSliderValue("Hue"),
                RedGain = GetSliderValue("RedGain"),
                GreenGain = GetSliderValue("GreenGain"),
                BlueGain = GetSliderValue("BlueGain")
            };

            DisplayGdi.ApplyRampDirect(p.ColorTemp, p.Brightness, p.Contrast, p.Saturation, p.Gamma, p.Hue, p.RedGain, p.GreenGain, p.BlueGain);
            p.Save();
        }

        private void LoadProfileToUI() {
            DisplayProfile p = DisplayProfile.Load();
            SetSliderValue("ColorTemp", p.ColorTemp);
            SetSliderValue("Brightness", p.Brightness);
            SetSliderValue("Contrast", p.Contrast);
            SetSliderValue("Saturation", p.Saturation);
            SetSliderValue("Gamma", p.Gamma);
            SetSliderValue("Hue", p.Hue);
            SetSliderValue("RedGain", p.RedGain);
            SetSliderValue("GreenGain", p.GreenGain);
            SetSliderValue("BlueGain", p.BlueGain);
        }

        private void ResetAllToDefaults() {
            foreach (var kvp in sliders) {
                SliderControl sc = kvp.Value;
                sc.Track.Value = (int)Math.Round(sc.Default * sc.Scale);
                sc.TxtVal.Text = sc.Default.ToString(sc.Format, CultureInfo.InvariantCulture) + sc.Unit;
            }
            ApplyAllSliders();
        }

        private void SaveAsStartup() {
            ApplyAllSliders();
            try {
                string exePath = Process.GetCurrentProcess().MainModule.FileName;
                string xmlContent = string.Format(@"<?xml version=""1.0"" encoding=""UTF-16""?>
<Task version=""1.2"" xmlns=""http://schemas.microsoft.com/windows/2004/02/mit/task"">
  <RegistrationInfo>
    <Description>DisplayTune Hardware LUT Calibration Loader (Logon, Wake &amp; Unlock)</Description>
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
      <Subscription>&lt;QueryList&gt;&lt;Query Id=""0"" Path=""System""&gt;&lt;Select Path=""System""&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;Select Path=""System""&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=107]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
      <Delay>PT2S</Delay>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id=""Author"">
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
  <Actions Context=""Author"">
    <Exec>
      <Command>{0}</Command>
      <Arguments>--apply --startup</Arguments>
    </Exec>
  </Actions>
</Task>", exePath);

                string tempXml = Path.Combine(Path.GetTempPath(), "DisplayTuneTask.xml");
                File.WriteAllText(tempXml, xmlContent, Encoding.Unicode);

                string args = string.Format("/Create /F /TN \"DisplayTuneAutoCalibration\" /XML \"{0}\"", tempXml);
                ProcessStartInfo psi = new ProcessStartInfo("schtasks.exe", args) {
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process proc = Process.Start(psi);
                if (proc != null) {
                    proc.WaitForExit();
                }
                try { File.Delete(tempXml); } catch { }

                MessageBox.Show("Successfully saved calibration profile and registered DisplayTune to restore colors on Windows Logon, Wake from Sleep, and Screen Unlock!", "DisplayTune", MessageBoxButtons.OK, MessageBoxIcon.Information);
            } catch (Exception ex) {
                MessageBox.Show("Failed to register automated task: " + ex.Message, "DisplayTune", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private Bitmap GenerateCalibrationPattern(int width, int height) {
            Bitmap bmp = new Bitmap(width, height);
            using (Graphics g = Graphics.FromImage(bmp)) {
                g.Clear(Color.FromArgb(16, 16, 16));

                // 1. Grayscale
                float stepW = width / 16.0f;
                for (int i = 0; i < 16; i++) {
                    int c = (int)(i * 255.0f / 15.0f);
                    using (Brush b = new SolidBrush(Color.FromArgb(c, c, c))) {
                        g.FillRectangle(b, i * stepW, 5, stepW + 1, 38);
                    }
                }

                // 2. Smooth Gradient
                for (int x = 0; x < width; x++) {
                    int c = (int)(x * 255.0f / (width - 1));
                    using (Pen p = new Pen(Color.FromArgb(c, c, c))) {
                        g.DrawLine(p, x, 50, x, 95);
                    }
                }

                // 3. Colors
                Color[] colors = new Color[] {
                    Color.Red, Color.FromArgb(255, 128, 0), Color.Yellow,
                    Color.Lime, Color.Cyan, Color.Blue, Color.Magenta, Color.White
                };
                float cW = width / (float)colors.Length;
                for (int i = 0; i < colors.Length; i++) {
                    using (Brush b = new SolidBrush(colors[i])) {
                        g.FillRectangle(b, i * cW, 105, cW + 1, 65);
                    }
                }

                // 4. Skin Tones
                Color[] skin = new Color[] {
                    Color.FromArgb(255, 224, 189), Color.FromArgb(234, 192, 134),
                    Color.FromArgb(212, 160, 102), Color.FromArgb(174, 114, 60),
                    Color.FromArgb(112, 66, 20)
                };
                float sW = width / (float)skin.Length;
                for (int i = 0; i < skin.Length; i++) {
                    using (Brush b = new SolidBrush(skin[i])) {
                        g.FillRectangle(b, i * sW, 180, sW + 1, 55);
                    }
                }

                // 5. Low-end Shadows
                for (int i = 0; i < 8; i++) {
                    int val = i * 4 + 4;
                    using (Brush b = new SolidBrush(Color.FromArgb(val, val, val))) {
                        g.FillRectangle(b, i * (width / 8.0f), 245, width / 8.0f, 50);
                    }
                }

                // 6. Highlights
                for (int i = 0; i < 8; i++) {
                    int val = 255 - (7 - i) * 4;
                    using (Brush b = new SolidBrush(Color.FromArgb(val, val, val))) {
                        g.FillRectangle(b, i * (width / 8.0f), 305, width / 8.0f, 50);
                    }
                }

                using (Font f = new Font("Segoe UI", 8f))
                using (Brush b = new SolidBrush(Color.FromArgb(160, 160, 160))) {
                    g.DrawString("Grayscale | Gradient | Primaries | Skin | Shadows | Highlights", f, b, 2, 365);
                }
            }
            return bmp;
        }
    }

    // =========================================================================
    // Program Entry Point (Dual Mode: CLI / GUI)
    // =========================================================================
    public static class Program {
        [STAThread]
        public static void Main(string[] args) {
            if (args.Length > 0) {
                // CLI Execution Mode
                RunCli(args);
            } else {
                // GUI Mode
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm());
            }
        }

        private static void RunCli(string[] args) {
            bool isStartup = false;
            bool isApply = false;
            bool isReset = false;
            string preset = null;

            for (int i = 0; i < args.Length; i++) {
                string a = args[i].ToLower();
                if (a == "--apply" || a == "-apply" || a == "apply") isApply = true;
                if (a == "--startup" || a == "-startup" || a == "startup") isStartup = true;
                if (a == "--reset" || a == "-reset" || a == "reset") isReset = true;
                if ((a == "--preset" || a == "-preset" || a == "preset") && i + 1 < args.Length) {
                    preset = args[i + 1].ToLower();
                }
            }

            if (isReset) {
                DisplayGdi.ApplyRampDirect(6500, 0, 100, 100, 2.20, 0, 0, 0, 0);
                return;
            }

            if (!string.IsNullOrEmpty(preset)) {
                if (preset == "srgb") DisplayGdi.ApplyRampDirect(6500, 0, 100, 100, 2.20, 0, 0, 0, 0);
                else if (preset == "creator") DisplayGdi.ApplyRampDirect(6350, 0, 108, 128, 2.26, 0, 3, 1, -4);
                else if (preset == "macbook") DisplayGdi.ApplyRampDirect(6400, -1, 110, 122, 2.28, 0, 2, 0, -3);
                else if (preset == "cinema") DisplayGdi.ApplyRampDirect(6300, 0, 106, 118, 2.25, 0, 2, 1, -3);
                else if (preset == "night") DisplayGdi.ApplyRampDirect(5200, -3, 96, 95, 2.15, 0, 2, 2, -12);
                return;
            }

            if (isApply) {
                DisplayProfile p = DisplayProfile.Load();
                DisplayGdi.ApplyRampDirect(p.ColorTemp, p.Brightness, p.Contrast, p.Saturation, p.Gamma, p.Hue, p.RedGain, p.GreenGain, p.BlueGain);

                if (isStartup) {
                    Thread.Sleep(3000);
                    DisplayGdi.ApplyRampDirect(p.ColorTemp, p.Brightness, p.Contrast, p.Saturation, p.Gamma, p.Hue, p.RedGain, p.GreenGain, p.BlueGain);
                }
            }
        }
    }
}
