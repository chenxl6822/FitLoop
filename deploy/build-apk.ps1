param(
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,

    [ValidateSet("Compatibility", "Official")]
    [string]$SigningMode = "Compatibility",

    [string]$ExpectedSignerSha256 = "69316bd8f5a1d79dad539415f88b3ecbaf43f3113831782e35499c0f55a47c2a",

    [switch]$AllowInsecureApiForDevelopment
)

$ErrorActionPreference = "Stop"

if (-not $AllowInsecureApiForDevelopment -and -not $ApiBaseUrl.StartsWith("https://")) {
    throw "Release APK API base URL must use HTTPS. Use -AllowInsecureApiForDevelopment only for a non-published build."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$mobileDir = Join-Path $repoRoot "mobile"
$apkSource = Join-Path $mobileDir "build\app\outputs\flutter-apk\app-release.apk"
$apkDir = Join-Path $PSScriptRoot "apk"
$apkTarget = Join-Path $apkDir "app-release.apk"
$checksumTarget = Join-Path $apkDir "app-release.apk.sha256"
$versionTarget = Join-Path $apkDir "version.json"
$pubspecVersion = Select-String -Path (Join-Path $mobileDir "pubspec.yaml") -Pattern "^version:\s*(.+)$" |
    Select-Object -First 1 |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }
$versionName = ($pubspecVersion -split "\+")[0]
$versionCode = if ($pubspecVersion -match "\+(\d+)$") { [int]$Matches[1] } else { 1 }

function Find-ApkSigner {
    $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME) |
        Where-Object { $_ -and (Test-Path $_) } |
        Select-Object -Unique
    foreach ($sdkRoot in $sdkRoots) {
        $candidate = Get-ChildItem -Path (Join-Path $sdkRoot "build-tools") `
            -Recurse -Filter "apksigner.bat" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    throw "Android apksigner.bat was not found. Set ANDROID_SDK_ROOT or ANDROID_HOME."
}

function Get-SignerSha256([string]$ApkPath, [string]$ApkSigner) {
    if (-not (Test-Path $ApkPath)) { throw "APK not found: $ApkPath" }
    $output = & $ApkSigner verify --print-certs $ApkPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed: $ApkPath" }
    $match = $output | Select-String -Pattern "certificate SHA-256 digest:\s*([0-9a-fA-F]+)" |
        Select-Object -First 1
    if (-not $match) { throw "Unable to read APK signer SHA-256: $ApkPath" }
    return $match.Matches[0].Groups[1].Value.ToLowerInvariant()
}

$apkSigner = Find-ApkSigner
$expectedSigner = $ExpectedSignerSha256.ToLowerInvariant()
if ($SigningMode -eq "Compatibility" -and (Test-Path $apkTarget)) {
    $previousSigner = Get-SignerSha256 $apkTarget $apkSigner
    if ($previousSigner -ne $expectedSigner) {
        throw "Existing compatibility APK signer does not match the approved public certificate fingerprint."
    }
}

if ($SigningMode -eq "Official") {
    $requiredSigningVariables = @(
        "FITLOOP_RELEASE_STORE_FILE",
        "FITLOOP_RELEASE_STORE_PASSWORD",
        "FITLOOP_RELEASE_KEY_ALIAS",
        "FITLOOP_RELEASE_KEY_PASSWORD"
    )
    foreach ($name in $requiredSigningVariables) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            throw "Official signing requires environment variable $name."
        }
    }
}

$previousCompatibilityValue = $env:FITLOOP_COMPAT_SIGNING
try {
    if ($SigningMode -eq "Compatibility") {
        $env:FITLOOP_COMPAT_SIGNING = "true"
    } else {
        Remove-Item Env:FITLOOP_COMPAT_SIGNING -ErrorAction SilentlyContinue
    }

    Push-Location $mobileDir
    try {
        flutter pub get
        flutter analyze
        flutter test
        flutter build apk --release `
            --dart-define="FITLOOP_API_BASE_URL=$ApiBaseUrl" `
            --dart-define="FITLOOP_APP_VERSION=$versionName" `
            --dart-define="FITLOOP_BUILD_NUMBER=$versionCode"
    } finally {
        Pop-Location
    }
} finally {
    if ($null -eq $previousCompatibilityValue) {
        Remove-Item Env:FITLOOP_COMPAT_SIGNING -ErrorAction SilentlyContinue
    } else {
        $env:FITLOOP_COMPAT_SIGNING = $previousCompatibilityValue
    }
}

$signerSha256 = Get-SignerSha256 $apkSource $apkSigner
if ($SigningMode -eq "Compatibility" -and $signerSha256 -ne $expectedSigner) {
    throw "New compatibility APK signer does not match the currently published APK. Publication is blocked."
}

New-Item -ItemType Directory -Force -Path $apkDir | Out-Null
$temporaryTarget = "$apkTarget.new"
Copy-Item -Force $apkSource $temporaryTarget
Move-Item -Force $temporaryTarget $apkTarget

$sizeMb = [Math]::Round((Get-Item $apkTarget).Length / 1MB, 1)
$sha256 = (Get-FileHash -Algorithm SHA256 $apkTarget).Hash.ToLowerInvariant()
"$sha256  app-release.apk" | Set-Content -Encoding ASCII $checksumTarget

@{
    version       = $versionName
    versionCode   = $versionCode
    size          = "$sizeMb MB"
    buildDate     = (Get-Date -Format "yyyy-MM-dd")
    minSdkVersion = "Android 8.0 (API 26)"
    apiBaseUrl    = $ApiBaseUrl
    sha256        = $sha256
    signerSha256  = $signerSha256
    signingMode   = $SigningMode
} | ConvertTo-Json | Set-Content -Encoding UTF8 $versionTarget

Write-Host "APK copied to $apkTarget"
Write-Host "Checksum written to $checksumTarget"
Write-Host "API base URL: $ApiBaseUrl"
Write-Host "Signing mode: $SigningMode"
