<#
.SYNOPSIS
Installs the addon into the WoW Forever beta client.

.DESCRIPTION
Replaces Interface\AddOns\ResourceEfficiencyTooltips in the game folder with an exact copy of the
repo's ResourceEfficiencyTooltips folder, so files removed from the repo don't linger in the game.
Restart the game after .toc or file list changes; otherwise /reload is enough.

.PARAMETER GameDir
The client folder holding Interface\AddOns. Defaults to the Forever beta (_classic_beta_).

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\Install-Addon.ps1
#>
param(
    [string]$GameDir = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_'
)

$ErrorActionPreference = 'Stop'
$addonName = 'ResourceEfficiencyTooltips'

$source = Join-Path (Split-Path $PSScriptRoot -Parent) $addonName
if (-not (Test-Path (Join-Path $source "$addonName.toc"))) { throw "Addon not found at $source" }

$addOns = Join-Path $GameDir 'Interface\AddOns'
if (-not (Test-Path $addOns)) { throw "AddOns folder not found: $addOns" }
$target = Join-Path $addOns $addonName

if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
Copy-Item -LiteralPath $source -Destination $target -Recurse

$version = (Select-String -Path (Join-Path $target "$addonName.toc") -Pattern '^## Version:\s*(.+)$').Matches.Groups[1].Value
$files = (Get-ChildItem -LiteralPath $target -File -Recurse).Count
Write-Host "Installed $addonName $version ($files files) to $target"
