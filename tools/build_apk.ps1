param(
    [switch]$Release,
    [switch]$Install,
    [string]$Godot = 'godot',
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
#   -Godot    path to the Godot executable (default: "godot" from PATH)
#   -Out      output path (default: build/the-tree-debug.apk or -release.apk)
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

New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null

$mode = if ($Release) { '--export-release' } else { '--export-debug' }
Write-Output ("Building " + $mode + " '" + $preset + "' -> " + $Out)
& $Godot --headless --path $root $mode $preset $Out
if ($LASTEXITCODE -ne 0) {
    throw ("Godot export failed with exit code " + $LASTEXITCODE)
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
    Write-Output "Installing on the attached device..."
    & $adb install -r $target
    if ($LASTEXITCODE -ne 0) {
        Write-Output 'Install failed. If the signature changed (debug vs release), run: adb uninstall com.endertainment.thetree'
    }
}
