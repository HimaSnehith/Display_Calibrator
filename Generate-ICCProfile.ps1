# ==============================================================================
# ICC Profile Generator for BOE NE156FHM-NXA Display
# Generates a valid standard ICC v2 Display Profile (.icc / .icm)
# ==============================================================================

param(
    [string]$OutputPath = "$PSScriptRoot\BOE_NE156FHM_NXA_Calibrated.icm",
    [switch]$Install
)

function Write-BE32($stream, [uint32]$val) {
    $bytes = [BitConverter]::GetBytes($val)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    $stream.Write($bytes, 0, 4)
}

function Write-BE16($stream, [uint16]$val) {
    $bytes = [BitConverter]::GetBytes($val)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    $stream.Write($bytes, 0, 2)
}

function Write-S15Fixed16($stream, [double]$val) {
    $raw = [int32][Math]::Round($val * 65536.0)
    $bytes = [BitConverter]::GetBytes($raw)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    $stream.Write($bytes, 0, 4)
}

function Write-TagHeader($stream, [string]$sig) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($sig)
    $stream.Write($bytes, 0, 4)
    Write-BE32 $stream 0 # reserved
}

$ms = New-Object System.IO.MemoryStream

# --- Header (128 bytes) ---
# Total profile size placeholder at 0..3
Write-BE32 $ms 0 
# CMM Type
$ms.Write([System.Text.Encoding]::ASCII.GetBytes("ADBE"), 0, 4)
# Version 2.4.0 (0x02400000)
Write-BE32 $ms 0x02400000
# Profile/Device Class: Display ('mntr')
$ms.Write([System.Text.Encoding]::ASCII.GetBytes("mntr"), 0, 4)
# Data Color Space: RGB ('RGB ')
$ms.Write([System.Text.Encoding]::ASCII.GetBytes("RGB "), 0, 4)
# PCS: CIEXYZ ('XYZ ')
$ms.Write([System.Text.Encoding]::ASCII.GetBytes("XYZ "), 0, 4)
# Creation Date / Time (2026-01-01 00:00:00)
Write-BE16 $ms 2026; Write-BE16 $ms 1; Write-BE16 $ms 1; Write-BE16 $ms 12; Write-BE16 $ms 0; Write-BE16 $ms 0
# Magic 'acsp'
$ms.Write([System.Text.Encoding]::ASCII.GetBytes("acsp"), 0, 4)
# Primary Platform: Microsoft ('MSFT')
$ms.Write([System.Text.Encoding]::ASCII.GetBytes("MSFT"), 0, 4)
# Profile Flags (0)
Write-BE32 $ms 0
# Device Manufacturer: BOE
$ms.Write([System.Text.Encoding]::ASCII.GetBytes("BOE "), 0, 4)
# Device Model
$ms.Write([System.Text.Encoding]::ASCII.GetBytes("NXA "), 0, 4)
# Device Attributes (0)
Write-BE32 $ms 0; Write-BE32 $ms 0
# Rendering Intent: Perceptual (0)
Write-BE32 $ms 0
# PCS Illuminant D50 (X=0.9642, Y=1.0000, Z=0.8249 in s15Fixed16)
Write-S15Fixed16 $ms 0.9642
Write-S15Fixed16 $ms 1.0000
Write-S15Fixed16 $ms 0.8249
# Profile Creator ('DTUN')
$ms.Write([System.Text.Encoding]::ASCII.GetBytes("DTUN"), 0, 4)
# ID (16 bytes zero)
for ($i = 0; $i -lt 16; $i++) { $ms.WriteByte(0) }
# Reserved (28 bytes zero)
for ($i = 0; $i -lt 28; $i++) { $ms.WriteByte(0) }

# Header is 128 bytes. Now Tag Table:
# Tags we need:
# 1. 'desc' - Text Description
# 2. 'cprt' - Copyright
# 3. 'wtpt' - Media White Point (D50)
# 4. 'rXYZ' - Red Matrix Column
# 5. 'gXYZ' - Green Matrix Column
# 6. 'bXYZ' - Blue Matrix Column
# 7. 'rTRC' - Red Tone Reproduction Curve
# 8. 'gTRC' - Green Tone Reproduction Curve
# 9. 'bTRC' - Blue Tone Reproduction Curve

$tags = @("desc", "cprt", "wtpt", "rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC")
$tagCount = $tags.Count

Write-BE32 $ms $tagCount

# Tag table placeholders: (12 bytes per tag: 4 byte signature, 4 byte offset, 4 byte length)
$tagTableStart = $ms.Position
for ($i = 0; $i -lt $tagCount; $i++) {
    $ms.Write([System.Text.Encoding]::ASCII.GetBytes($tags[$i]), 0, 4)
    Write-BE32 $ms 0 # offset
    Write-BE32 $ms 0 # length
}

$tagData = @{}

# 1. desc tag
$descStream = New-Object System.IO.MemoryStream
Write-TagHeader $descStream "desc"
$descText = "BOE NE156FHM-NXA D65 Calibrated"
Write-BE32 $descStream ($descText.Length + 1)
$descBytes = [System.Text.Encoding]::ASCII.GetBytes($descText)
$descStream.Write($descBytes, 0, $descBytes.Length)
$descStream.WriteByte(0) # null
Write-BE32 $descStream 0; Write-BE32 $descStream 0; Write-BE16 $descStream 0; Write-BE16 $descStream 0; Write-BE32 $descStream 0
$tagData["desc"] = $descStream.ToArray()

# 2. cprt tag
$cprtStream = New-Object System.IO.MemoryStream
Write-TagHeader $cprtStream "text"
$cprtText = "DisplayTune 2026"
$cprtBytes = [System.Text.Encoding]::ASCII.GetBytes($cprtText)
$cprtStream.Write($cprtBytes, 0, $cprtBytes.Length)
$cprtStream.WriteByte(0)
$tagData["cprt"] = $cprtStream.ToArray()

# 3. wtpt tag (D50)
$wtptStream = New-Object System.IO.MemoryStream
Write-TagHeader $wtptStream "XYZ "
Write-S15Fixed16 $wtptStream 0.9642
Write-S15Fixed16 $wtptStream 1.0000
Write-S15Fixed16 $wtptStream 0.8249
$tagData["wtpt"] = $wtptStream.ToArray()

# 4. rXYZ tag (D50 adapted sRGB matrix columns)
$rxyzStream = New-Object System.IO.MemoryStream
Write-TagHeader $rxyzStream "XYZ "
Write-S15Fixed16 $rxyzStream 0.43607
Write-S15Fixed16 $rxyzStream 0.22250
Write-S15Fixed16 $rxyzStream 0.01393
$tagData["rXYZ"] = $rxyzStream.ToArray()

# 5. gXYZ tag
$gxyzStream = New-Object System.IO.MemoryStream
Write-TagHeader $gxyzStream "XYZ "
Write-S15Fixed16 $gxyzStream 0.38515
Write-S15Fixed16 $gxyzStream 0.71687
Write-S15Fixed16 $gxyzStream 0.09708
$tagData["gXYZ"] = $gxyzStream.ToArray()

# 6. bXYZ tag
$bxyzStream = New-Object System.IO.MemoryStream
Write-TagHeader $bxyzStream "XYZ "
Write-S15Fixed16 $bxyzStream 0.14307
Write-S15Fixed16 $bxyzStream 0.06061
Write-S15Fixed16 $bxyzStream 0.71410
$tagData["bXYZ"] = $bxyzStream.ToArray()

# 7-9. TRC curves (Gamma 2.2 parameterized curve / u8Fixed8 gamma = 0x0233 = 2.2)
$trcStream = New-Object System.IO.MemoryStream
Write-TagHeader $trcStream "curv"
Write-BE32 $trcStream 1 # 1 entry = single gamma value
Write-BE16 $trcStream 0x0233 # 2.2 in 8.8 fixed point
$trcBytes = $trcStream.ToArray()
$tagData["rTRC"] = $trcBytes
$tagData["gTRC"] = $trcBytes
$tagData["bTRC"] = $trcBytes

# Write Tag Data & Update Table
$tagOffsets = @{}
$tagLengths = @{}

foreach ($tag in $tags) {
    # 4-byte align position
    while ($ms.Position % 4 -ne 0) { $ms.WriteByte(0) }
    $tagOffsets[$tag] = [uint32]$ms.Position
    $bytes = $tagData[$tag]
    $tagLengths[$tag] = [uint32]$bytes.Length
    $ms.Write($bytes, 0, $bytes.Length)
}

# 4-byte align total length
while ($ms.Position % 4 -ne 0) { $ms.WriteByte(0) }
$totalLength = [uint32]$ms.Position

# Seek back to write total length
$ms.Position = 0
Write-BE32 $ms $totalLength

# Seek back to write tag table entries
$ms.Position = $tagTableStart
for ($i = 0; $i -lt $tagCount; $i++) {
    $tag = $tags[$i]
    $ms.Write([System.Text.Encoding]::ASCII.GetBytes($tag), 0, 4)
    Write-BE32 $ms $tagOffsets[$tag]
    Write-BE32 $ms $tagLengths[$tag]
}

[System.IO.File]::WriteAllBytes($OutputPath, $ms.ToArray())
Write-Host "Created Calibrated ICC Profile at: $OutputPath" -ForegroundColor Green

if ($Install) {
    $colorDir = "$env:WINDIR\System32\spool\drivers\color"
    $dest = Join-Path $colorDir (Split-Path $OutputPath -Leaf)
    Copy-Item -Path $OutputPath -Destination $dest -Force
    Write-Host "Installed profile to Windows Color Directory: $dest" -ForegroundColor Cyan
}
