param(
    [string]$Flutter = 'flutter',
    [string]$AndroidSdk,
    [string]$JavaHome,
    [string]$GradleCache
)
$ErrorActionPreference = 'Stop'
if ($AndroidSdk) {
    $env:ANDROID_HOME = (Resolve-Path -LiteralPath $AndroidSdk).Path
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
}
if ($JavaHome) {
    $env:JAVA_HOME = (Resolve-Path -LiteralPath $JavaHome).Path
    if (!(Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin/jlink.exe'))) {
        throw 'A complete JDK with jlink is required, not a runtime-only Java installation'
    }
}
if ($GradleCache) { $env:GRADLE_USER_HOME = [IO.Path]::GetFullPath($GradleCache) }
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
    & $Flutter build apk --debug --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
} finally { Pop-Location }
