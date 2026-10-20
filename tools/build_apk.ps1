param(
    [switch]$Release,
    [switch]$Install,
    [string]$Godot = 'C:\Tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe',
    [string]$Out = ''
)

# Builds the Android APK with one command.
#
#   pwsh -ExecutionPolicy Bypass -File tools/build_apk.ps1
#   pwsh -ExecutionPolicy Bypass -File tools/build_apk.ps1 -Release
#   pwsh -ExecutionPolicy Bypass -File tools/build_apk.ps1 -Install
#
# Options:
#   -Release  export the release APK, signed with the release keystore
#   -Install  adb install -r the built APK afterwards
#   -Godot    path to the preferred Godot executable
#   -Out      output path (default: build/the-tree-debug.apk or -release.apk)
#
# Android export needs a Godot build whose versioned export templates are
# installed. Godot 4 names the folder after the engine build, e.g.
#   4.7.2.stable        (standard build)
#   4.7.2.stable.mono   (.NET build)
# A standard editor cannot use .NET templates, and the other way round. The
# script therefore checks the preferred executable first and falls back to any
# other installed Godot that does have android_debug.apk.
#
# Release signing is read from the environment:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
# If they are unset, this machine's credentials file
# (%USERPROFILE%\.the-tree\release-keystore.txt) is used instead.

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Out)) {
    if ($Release) { $Out = 'build/the-tree-release.apk' } else { $Out = 'build/the-tree-debug.apk' }
}
$preset = 'Android'
$target = Join-Path $root $Out


function Get-ConsoleVariant([string]$exe) {
    if ($exe -match '_console\.exe$') { return $exe }
    if ($exe -match '\.exe$') {
        $console = $exe -replace '\.exe$', '_console.exe'
        if (Test-Path $console) { return $console }
    }
    return $exe
}

function Get-EngineVersion([string]$exe) {
    try {
        $output = & $exe --headless --version 2>$null
        $line = ($output | Select-Object -Last 1)
        if ($null -eq $line) { return '' }
        return ([string]$line).Trim()
    } catch {
        return ''
    }
}

# Godot looks for templates in export_templates/<major.minor.patch>.<type>,
# where <type> is "stable" or "stable.mono" for .NET builds.
function Get-TemplateDir([string]$version) {
    $parts = $version.Split('.')
    if ($parts.Count -lt 3) { return '' }
    $name = ($parts[0..2] -join '.') + '.stable'
    if ($version -match '\.mono') { $name += '.mono' }
    return (Join-Path $env:APPDATA "Godot\export_templates\$name")
}

function Find-GodotWithTemplates([string]$preferred) {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($preferred)) { $candidates.Add($preferred) }
    foreach ($name in @('godot', 'godot4')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { $candidates.Add($cmd.Source) }
    }
    $candidates.Add((Join-Path $env:USERPROFILE 'Desktop\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Desktop\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'))

    $tried = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path $candidate)) { continue }
        $exe = Get-ConsoleVariant $candidate
        $version = Get-EngineVersion $exe
        if ([string]::IsNullOrWhiteSpace($version)) {
            $tried.Add("$candidate -> could not read --version")
            continue
        }
        $dir = Get-TemplateDir $version
        if (Test-Path (Join-Path $dir 'android_debug.apk')) {
            return @{ Exe = $exe; Version = $version; Templates = $dir; Tried = $tried }
        }
        $tried.Add("$candidate -> $version (no Android templates in $dir)")
    }
    $message = "No Godot with Android export templates was found.`n"
    if ($tried.Count -gt 0) { $message += ($tried -join "`n") + "`n" }
    $message += @"
Install the templates once: open the Godot editor -> Editor -> Manage Export
Templates -> Download and Install (do it in the build you want to export with).
Then re-run this script, or pass -Godot <path to that Godot.exe>.
"@
    throw $message
}


if ($Release -and [string]::IsNullOrWhiteSpace($env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH)) {
    $credFile = Join-Path $env:USERPROFILE '.the-tree\release-keystore.txt'
    if (Test-Path $credFile) {
        foreach ($line in Get-Content $credFile) {
            if ($line -match '^THE_TREE_KEYSTORE=(.+)$') {
                $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $Matches[1]
            } elseif ($line -match '^THE_TREE_KEY_ALIAS=(.+)$') {
                $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $Matches[1]
            } elseif ($line -match '^THE_TREE_KEY_PASSWORD=(.+)$') {
                $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $Matches[1]
            }
        }
        Write-Output ("Signing with " + $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH)
    }
}
if ($Release -and [string]::IsNullOrWhiteSpace($env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH)) {
    throw 'Release build needs a signing key: set GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD or create %USERPROFILE%\.the-tree\release-keystore.txt'
}

$engine = Find-GodotWithTemplates $Godot
Write-Output ("Using " + $engine.Exe + " (" + $engine.Version + ")")
Write-Output ("Templates: " + $engine.Templates)

New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null

$mode = if ($Release) { '--export-release' } else { '--export-debug' }
Write-Output ("Building " + $mode + " '" + $preset + "' -> " + $Out)
& $engine.Exe --headless --path $root $mode $preset $Out
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }
if ($code -ne 0) {
    throw ("Godot export failed with exit code " + $code)
}
if (-not (Test-Path $target)) {
    throw ("Export reported success but " + $target + " is missing")
}

$size = [Math]::Round((Get-Item $target).Length / 1MB, 1)
Write-Output ("OK: " + $target + " (" + $size + " MB)")

if ($Install) {
    $adb = 'adb'
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
        $adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
    } elseif (Test-Path 'C:\Android\Sdk\platform-tools\adb.exe') {
        $adb = 'C:\Android\Sdk\platform-tools\adb.exe'
    }
    $devices = & $adb devices
    if (($devices | Select-String 'device$').Count -eq 0) {
        Write-Output 'No device attached; skipping install.'
        return
    }
    Write-Output 'Installing on the attached device...'
    & $adb install -r $target
    if ($LASTEXITCODE -ne 0) {
        Write-Output 'Install failed. If the signature changed (debug vs release), run: adb uninstall com.endertainment.thetree'
    }
}
