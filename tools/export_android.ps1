param(
    [string]$Preset = 'Android',
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
# injects them into a temporary copy of the file and always restores the
# original, even when the export fails.

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

$replacements = [ordered]@{
    'keystore/release' = ('"' + ($keystore -replace '\\', '/') + '"')
    'keystore/release_user' = ('"' + $env:THE_TREE_KEY_ALIAS + '"')
    'keystore/release_password' = ('"' + $env:THE_TREE_KEY_PASSWORD + '"')
}

$lines = New-Object System.Collections.Generic.List[string]
foreach ($line in ($original -split "`n")) { $lines.Add($line) }

$optionsIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq '[preset.0.options]') { $optionsIndex = $i; break }
}
if ($optionsIndex -lt 0) {
    Write-Error 'export_presets.cfg has no [preset.0.options] section'
    exit 2
}

$insertAt = $optionsIndex + 1
foreach ($key in $replacements.Keys) {
    $value = $replacements[$key]
    $found = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
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
    Write-Output ("Exporting release with preset '" + $Preset + "' -> " + $Out)
    & $Godot --headless --path $root --export-release $Preset $Out
    if ($LASTEXITCODE -ne 0) {
        Write-Error ("Export failed with exit code " + $LASTEXITCODE)
        exit 1
    }
    Write-Output ("Done: " + (Join-Path $root $Out))
}
finally {
    if (Test-Path $backup) {
        [System.IO.File]::WriteAllText($presetPath, $original, $utf8)
        Remove-Item $backup -Force
    }
}
