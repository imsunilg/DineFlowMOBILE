<#
.SYNOPSIS
  Release build: bumps the DineFlow mobile version (minor +1, patch reset to 0, build number +1), builds a
  release APK, and copies it into releases/ as DineFlow_<major.minor.patch>.apk. The application's launcher
  label is never touched by this script -- it stays "DineFlow" regardless of version
  (see android/app/src/main/AndroidManifest.xml); the version number is never appended to it.

  Only run this for an actual release. Running it does a real version bump each time -- there is no dry-run.
  If the build fails, pubspec.yaml is rolled back to its previous version and no APK is produced.

.USAGE
  pwsh ./scripts/build-apk.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $root 'pubspec.yaml'
$releasesDir = Join-Path $root 'releases'

$originalPubspec = Get-Content $pubspecPath -Raw
if ($originalPubspec -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$') {
    throw "Could not find a 'version: X.Y.Z+N' line in pubspec.yaml"
}
$major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3]; $build = [int]$Matches[4]
$previousVersion = "$major.$minor.$patch+$build"

$newMinor = $minor + 1
$newPatch = 0
$newBuild = $build + 1
$newVersion = "$major.$newMinor.$newPatch+$newBuild"
$releaseName = "DineFlow_$major.$newMinor.$newPatch.apk"

$pubspec = $originalPubspec -replace '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', "version: $newVersion"
Set-Content -Path $pubspecPath -Value $pubspec -NoNewline -Encoding utf8
Write-Host "Version bumped: $previousVersion -> $newVersion"

try {
    Push-Location $root
    try {
        flutter clean
        if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed' }
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }
    }
    finally {
        Pop-Location
    }

    $builtApk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $builtApk)) { throw "Expected APK not found at $builtApk" }

    New-Item -ItemType Directory -Force -Path $releasesDir | Out-Null
    $releasedApk = Join-Path $releasesDir $releaseName
    if (Test-Path $releasedApk) { throw "$releaseName already exists in releases/ -- refusing to overwrite a previous release" }
    Copy-Item -Path $builtApk -Destination $releasedApk

    Write-Host ''
    Write-Host '========================================'
    Write-Host 'DineFlow Mobile Release'
    Write-Host '========================================'
    Write-Host ''
    Write-Host "Application : DineFlow"
    Write-Host "Version     : $major.$newMinor.$newPatch"
    Write-Host "Build       : $newBuild"
    Write-Host ''
    Write-Host 'APK:'
    Write-Host "releases/$releaseName"
    Write-Host '========================================'
}
catch {
    Write-Host ''
    Write-Host "BUILD FAILED: $_" -ForegroundColor Red
    Write-Host "Rolling back pubspec.yaml to version $previousVersion (no release was produced)." -ForegroundColor Red
    Set-Content -Path $pubspecPath -Value $originalPubspec -NoNewline -Encoding utf8
    throw
}
