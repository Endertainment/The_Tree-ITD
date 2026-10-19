param(
    [string]$Preset = 'Android AAB',
    [string]$Out = 'build/the-tree-release.aab',
    [string]$Godot = 'godot'
)

# Signs a release export with keystore details taken from the environment.
#
#   THE_TREE_KEYSTORE      absolute path to the .keystore file
#   THE_TREE_KEY_ALIAS     key alias inside the keystore
#   THE_TREE_KEY_PASSWORD  keystore password
#
# The committed export_presets.cfg never contains these values: the script
# injects them into the options block of the requested preset in a temporary
# copy of the file, and always restores the original, even when the export
# fails.

$ErrorActionPreference = 'Stop'

$keys = @('THE_TREE_KEYSTORE', 'THE_TREE_KEY_ALIAS', 'THE_TREE_KEY_PASSWORD')
$missing = @()
foreach ($name in $keys) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        $missing += $name
    }
}
if ($missing.Count -gt 0) {
    Write-Error ("Missing environment variables: " + ($missing -join ', '))
    exit 2
}

$keystore = $env:THE_TREE_KEYSTORE
if (-not (Test-Path $keystore)) {
    Write-Error ("Keystore not found: " + $keystore)
    exit 2
}

$root = Split-Path -Parent $PSScriptRoot
$presetPath = Join-Path $root 'export_presets.cfg'
if (-not (Test-Path $presetPath)) {
    Write-Error ("Missing " + $presetPath)
    exit 2
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$original = [System.IO.File]::ReadAllText($presetPath, $utf8)
$backup = $presetPath + '.release-backup'

$lines = New-Object System.Collections.Generic.List[string]
foreach ($line in ($original -split "`n")) { $lines.Add($line) }

# Find the [preset.N] block whose name matches $Preset.
$presetIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\[preset\.(\d+)\]$') {
        $candidate = [int]$Matches[1]
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j].StartsWith('[')) { break }
            if ($lines[$j].Trim() -eq ('name="' + $Preset + '"')) {
                $presetIndex = $candidate
                break
            }
        }
    }
    if ($presetIndex -ge 0) { break }
}
if ($presetIndex -lt 0) {
    Write-Error ("export_presets.cfg has no preset named '" + $Preset + "'")
    exit 2
}

$optionsHeader = '[preset.' + $presetIndex + '.options]'
$optionsIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq $optionsHeader) { $optionsIndex = $i; break }
}
if ($optionsIndex -lt 0) {
    Write-Error ('export_presets.cfg has no ' + $optionsHeader + ' section')
    exit 2
}

$replacements = [ordered]@{
    'keystore/release' = ('"' + ($keystore -replace '\\', '/') + '"')
    'keystore/release_user' = ('"' + $env:THE_TREE_KEY_ALIAS + '"')
    'keystore/release_password' = ('"' + $env:THE_TREE_KEY_PASSWORD + '"')
}

$insertAt = $optionsIndex + 1
foreach ($key in $replacements.Keys) {
    $value = $replacements[$key]
    $found = -1
    for ($i = $optionsIndex; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('[') -and $i -ne $optionsIndex) { break }
        if ($lines[$i].StartsWith($key + ' = ')) { $found = $i; break }
    }
    if ($found -ge 0) {
        $lines[$found] = $key + ' = ' + $value
    } else {
        $lines.Insert($insertAt, $key + ' = ' + $value)
        $insertAt++
    }
}

try {
    [System.IO.File]::WriteAllText($backup, $original, $utf8)
    [System.IO.File]::WriteAllLines($presetPath, $lines, $utf8)
    Write-Output ("Exporting '" + $Preset + "' -> " + $Out)
    & $Godot --headless --path $root --export-release $Preset $Out
    if ($LASTEXITCODE -ne 0) {
        Write-Error ("Export failed with exit code " + $LASTEXITCODE)
        exit 1
    }
    $target = Join-Path $root $Out
    if (-not (Test-Path $target)) {
        Write-Error ("Export reported success but " + $target + " is missing")
        exit 1
    }
    $size = [Math]::Round((Get-Item $target).Length / 1MB, 1)
    Write-Output ("Done: " + $target + " (" + $size + " MB)")
}
finally {
    if (Test-Path $backup) {
        [System.IO.File]::WriteAllText($presetPath, $original, $utf8)
        Remove-Item $backup -Force
    }
}
