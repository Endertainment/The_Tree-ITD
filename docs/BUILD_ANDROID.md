# Building The Tree for Android

Everything in this document was executed on the machine that produced the
stage-7 build. Commands are PowerShell; the same steps work in `bash` with
`export` instead of `$env:`.

Verified build: `com.endertainment.thetree`, versionCode **1**, versionName
**0.1.0**, minSdk **24**, targetSdk **36**, `arm64-v8a` + `armeabi-v7a`,
signed with APK Signature Scheme v2 + v3, **56.2 MB**.

---

## 1. Prerequisites

| Tool | Version used | Notes |
|---|---|---|
| Godot | 4.7.2 stable, **.NET/mono build** | Project is GDScript-only; the mono editor still exports it. |
| Export templates | `4.7.2.stable.mono` | Must match the editor exactly. |
| JDK | 21 (`Eclipse Adoptium`) | Any 17+ works. 21 was verified. |
| Android SDK | cmdline-tools `13114738`, `platform-tools`, `build-tools;35.0.0`, `platforms;android-35` | Installed under `C:\Android\Sdk`. |

Export templates live in:

```
%APPDATA%\Godot\export_templates\4.7.2.stable.mono\
```

If that folder is missing, open the editor once and use
**Editor → Manage Export Templates → Download and Install**.

### 1.1 Install the Android SDK from scratch

```powershell
$sdkRoot = 'C:\Android\Sdk'
$zip = "$env:TEMP\cmdline-tools.zip"
Invoke-WebRequest -UseBasicParsing `
  -Uri 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' `
  -OutFile $zip
Expand-Archive $zip -DestinationPath "$env:TEMP\cmdline-tools" -Force
New-Item -ItemType Directory -Force -Path "$sdkRoot\cmdline-tools" | Out-Null
Copy-Item "$env:TEMP\cmdline-tools\cmdline-tools" "$sdkRoot\cmdline-tools\latest" -Recurse -Force

$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.4.7-hotspot'
$sdkmanager = "$sdkRoot\cmdline-tools\latest\bin\sdkmanager.bat"

# Accept licences (answer y to each prompt)
1..40 | ForEach-Object { 'y' } | & $sdkmanager --sdk_root=$sdkRoot --licenses

& $sdkmanager --sdk_root=$sdkRoot 'platform-tools' 'build-tools;35.0.0' 'platforms;android-35'
```

Verify:

```powershell
Test-Path 'C:\Android\Sdk\platform-tools\adb.exe'          # True
Test-Path 'C:\Android\Sdk\build-tools\35.0.0\apksigner.bat' # True
Test-Path 'C:\Android\Sdk\platforms\android-35\android.jar' # True
```

---

## 2. Debug keystore

Godot will not export without one. Create it once:

```powershell
$javaHome = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.4.7-hotspot'
$ks = "$env:USERPROFILE\.android\debug.keystore"
New-Item -ItemType Directory -Force -Path (Split-Path $ks) | Out-Null
& "$javaHome\bin\keytool.exe" -genkeypair -keyalg RSA -keysize 2048 -validity 10000 `
  -keystore $ks -storepass android -alias androiddebugkey -keypass android `
  -dname "CN=Android Debug,O=Android,C=US"
```

`keytool` prints its progress to stderr, so a non-zero `$LASTEXITCODE` here can
be noise; confirm the file exists instead.

---

## 3. Point Godot at the SDK

### 3.1 From the editor

**Editor → Editor Settings → Export → Android**:

| Setting | Value |
|---|---|
| Android SDK Path | `C:/Android/Sdk` |
| Java SDK Path | `C:/Program Files/Eclipse Adoptium/jdk-21.0.4.7-hotspot` |
| Debug Keystore | `C:/Users/<you>/.android/debug.keystore` |
| Debug Keystore User | `androiddebugkey` |
| Debug Keystore Pass | `android` |

### 3.2 Without opening the editor

Godot stores these in `%APPDATA%\Godot\editor_settings-4.7.tres`:

```ini
export/android/android_sdk_path = "C:/Android/Sdk"
export/android/java_sdk_path = "C:/Program Files/Eclipse Adoptium/jdk-21.0.4.7-hotspot"
export/android/debug_keystore = "C:/Users/VOVA/.android/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
export/android/adb = "C:/Android/Sdk/platform-tools/adb.exe"
# Without this, `--export-debug` finishes writing the APK and then hangs while
# trying to stop the adb server.
export/android/shutdown_adb_on_exit = false
```

---

## 4. Build

The preset in `export_presets.cfg` is named **Android** and exports to
`build/the-tree-debug.apk`.

```powershell
# from the project root
godot --headless --path . --export-debug "Android" build/the-tree-debug.apk
```

Paths used on the machine this was verified on:

```powershell
& 'C:\Users\VOVA\Desktop\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe' `
  --headless --path . --export-debug "Android" build/the-tree-debug.apk
```

A warm build takes ~17 s and exits `0`. The editor prints
`ERROR: EditorSettings not instantiated yet ... shutdown_adb_on_exit` during
teardown; it is an engine log line after the APK is already signed and does not
affect the artifact.

### 4.1 What the preset pins

| Option | Value |
|---|---|
| `package/unique_name` | `com.endertainment.thetree` |
| `version/code` / `version/name` | `1` / `"0.1.0"` |
| `architectures/arm64-v8a` | `true` (release target) |
| `architectures/armeabi-v7a` | `true` (debug compatibility) |
| `gradle_build/use_gradle_build` | `false` |
| `screen/immersive_mode` | `true` |
| `permissions/internet` | `true` |
| `graphics/opengl_debug` | `false` |
| `exclude_filter` | `tools/*,tests/*,docs/*,addons/*` |

`tools/` and `tests/` are dev-only and are stripped from the package.

### 4.2 minSdk / targetSdk

With `use_gradle_build=false` Godot takes both values from the export template
and **refuses** preset overrides (`"Min SDK" can only be overridden when "Use
Gradle Build" is enabled`). The shipped template produces minSdk **24** /
targetSdk **36**.

If Play ever requires a different `targetSdk`, either update the export
templates or switch this preset to a Gradle build and set
`gradle_build/min_sdk` / `gradle_build/target_sdk`. Verify the result with
`aapt2 dump badging` (below) — never trust the preset file alone.

---

## 5. Verify the APK

```powershell
$apk = 'build/the-tree-debug.apk'
& 'C:\Android\Sdk\build-tools\35.0.0\aapt2.exe' dump badging $apk |
  Select-String 'package:|sdkVersion|targetSdkVersion|application-label|uses-permission|native-code'

$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.4.7-hotspot'
& 'C:\Android\Sdk\build-tools\35.0.0\apksigner.bat' verify --verbose $apk
```

Expected:

```
package: name='com.endertainment.thetree' versionCode='1' versionName='0.1.0'
minSdkVersion:'24'
targetSdkVersion:'36'
application-label:'The Tree'
uses-permission: name='android.permission.INTERNET'
native-code: 'arm64-v8a' 'armeabi-v7a'
Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
```

---

## 6. Install on a device

```powershell
& 'C:\Android\Sdk\platform-tools\adb.exe' install -r build/the-tree-debug.apk
& 'C:\Android\Sdk\platform-tools\adb.exe' shell monkey -p com.endertainment.thetree -c android.intent.category.LAUNCHER 1
& 'C:\Android\Sdk\platform-tools\adb.exe' logcat -s godot:V
```

Portrait is locked in `project.godot` (`window/handheld/orientation=1`) and
immersive mode comes from the preset.

---

## 7. Release signing from environment variables

Secrets never go in `export_presets.cfg`. `tools/export_android.ps1` reads them
from the environment, injects them into a temporary copy of the preset, runs the
export and restores the committed file.

```powershell
$env:THE_TREE_KEYSTORE     = 'C:\keys\the-tree-release.keystore'
$env:THE_TREE_KEY_ALIAS    = 'the-tree'
$env:THE_TREE_KEY_PASSWORD = '********'

godot --headless --path . --export-release "Android" build/the-tree-release.aab
```

`tools/export_android.ps1` wraps those three steps:

```powershell
./tools/export_android.ps1 -Preset Android -Out build/the-tree-release.aab
```

The script fails loudly when any of the three variables is missing, and always
restores `export_presets.cfg` — even when the export fails.

---

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Min SDK can only be overridden when Use Gradle Build is enabled` | Remove `gradle_build/min_sdk` + `target_sdk` from the preset, or enable Gradle. |
| Export writes the APK, then hangs | A stale `adb` server is holding the teardown. Check with `Get-Process adb`; run `Get-Process adb \| Stop-Process -Force` and export again. Also set `export/android/shutdown_adb_on_exit = false`. |
| `Android SDK path is invalid` | `export/android/android_sdk_path` points at an old folder; fix the editor setting. |
| `Debug keystore not configured` | Create the keystore (§2) and set the three `debug_keystore*` settings. |
| `Exporting to Android when using C#/.NET is experimental` | You are running the mono editor. Harmless for a GDScript project; a non-mono editor removes the message. |
| `GDExtension ... git_plugin ... no arm64 library` | The git editor plugin is excluded via `exclude_filter`; if you see it, the export cache is stale — re-run the export. |

---

## 9. Release AAB (stage 8)

The `Android AAB` preset (second block in `export_presets.cfg`) turns on Gradle,
sets `export_format=1` (AAB), `minSdk 26` and `targetSdk 35`. Gradle builds need
the Android build template inside the project:

```powershell
godot --headless --path . --install-android-build-template
```

That writes `res://android/build` (gitignored, `.gitignore` has `/android/`).
Without it the exporter fails with `Trying to build from a gradle built
template, but no version info for it exists`.

Sign without touching the preset by exporting the three CI variables and running
the export directly:

```powershell
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = 'C:\Users\VOVA\.the-tree\release.keystore'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'thetree'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = '<password>'
$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.4.7-hotspot'
godot --headless --path . --export-release 'Android AAB' build/the-tree-release.aab
```

`tools/export_android.ps1 -Preset "Android AAB"` does the same by temporarily
injecting the keystore into the preset; prefer the env vars in CI so the secret
never reaches a file.

Verify without uploading:

```powershell
java -jar bundletool.jar dump manifest --bundle build/the-tree-release.aab
java -jar bundletool.jar build-apks --bundle build/the-tree-release.aab `
  --output build/the-tree-release.apks --mode=universal `
  --ks release.keystore --ks-key-alias thetree --ks-pass pass:<pw> --key-pass pass:<pw>
```

Installing the resulting universal APK over USB can be refused by MIUI with
`INSTALL_FAILED_USER_RESTRICTED`; that is the phone's "Install via USB" policy,
not a build problem. Test through the Play closed track instead.
