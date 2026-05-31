param(
    [string]$ApiBaseUrl = "http://43.139.72.25"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$mobileDir = Join-Path $repoRoot "mobile"
$apkSource = Join-Path $mobileDir "build\app\outputs\flutter-apk\app-release.apk"
$apkDir = Join-Path $PSScriptRoot "apk"
$apkTarget = Join-Path $apkDir "app-release.apk"
$versionTarget = Join-Path $apkDir "version.json"

Push-Location $mobileDir
try {
    flutter pub get
    flutter analyze
    flutter test
    flutter build apk --release --dart-define="FITLOOP_API_BASE_URL=$ApiBaseUrl"
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Force -Path $apkDir | Out-Null
Copy-Item -Force $apkSource $apkTarget

$pubspecVersion = Select-String -Path (Join-Path $mobileDir "pubspec.yaml") -Pattern "^version:\s*(.+)$" |
    Select-Object -First 1 |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }

$versionName = ($pubspecVersion -split "\+")[0]
$versionCode = if ($pubspecVersion -match "\+(\d+)$") { [int]$Matches[1] } else { 1 }
$sizeMb = [Math]::Round((Get-Item $apkTarget).Length / 1MB, 1)

@{
    version       = $versionName
    versionCode   = $versionCode
    size          = "$sizeMb MB"
    buildDate     = (Get-Date -Format "yyyy-MM-dd")
    minSdkVersion = "Android 8.0 (API 26)"
    apiBaseUrl    = $ApiBaseUrl
} | ConvertTo-Json | Set-Content -Encoding UTF8 $versionTarget

Write-Host "APK copied to $apkTarget"
Write-Host "API base URL: $ApiBaseUrl"
