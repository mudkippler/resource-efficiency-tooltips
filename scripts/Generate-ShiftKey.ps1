<#
.SYNOPSIS
Renders the Shift keycap texture shown in tooltips that have more info behind Shift.

.DESCRIPTION
Draws a <kbd>-style key (light face, grey border, darker bottom edge, dark "Shift" text) with
ImageMagick and writes ResourceEfficiencyTooltips\shift.tga: 128x64 (WoW textures need power-of-two
sizes), 32-bit with alpha, uncompressed. The addon shows it at 32x16 with a |T...|t escape (SHIFT_KEY).

.PARAMETER Magick
Path to ImageMagick's magick.exe.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\Generate-ShiftKey.ps1
#>
param(
    [string]$Magick = 'C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Magick)) { throw "ImageMagick not found at $Magick (pass -Magick)" }
$output = Join-Path (Split-Path $PSScriptRoot -Parent) 'ResourceEfficiencyTooltips\shift.tga'

& $Magick -size 128x64 xc:none `
    -fill '#7d7d7d' -draw 'roundrectangle 3,6 124,60 11,11' `
    -fill '#f4f4f4' -stroke '#b4b4b4' -strokewidth 2 -draw 'roundrectangle 3,3 124,53 11,11' `
    -stroke none -fill '#333333' -font 'C:/Windows/Fonts/segoeuib.ttf' -pointsize 36 -gravity center `
    -annotate +0-4 'Shift' `
    -depth 8 -type TrueColorAlpha -compress none $output
if ($LASTEXITCODE -ne 0) { throw "magick failed with exit code $LASTEXITCODE" }
Write-Host "Wrote $output"
