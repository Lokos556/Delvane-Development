# Build the standalone ARM64 UAT release with the local Android debug signer.
$ErrorActionPreference = 'Stop'
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$buildTemp = 'C:\Delvane\AndroidBuildTemp'
New-Item -ItemType Directory -Path $buildTemp -Force | Out-Null
Push-Location (Join-Path $PSScriptRoot '..')
try {
    $env:TEMP = $buildTemp
    $env:TMP = $buildTemp
    flutter --no-version-check build apk --release --no-pub --target-platform android-arm64 `
        --build-number=3 --dart-define=DELVANE_ENV=staging `
        --dart-define=DELVANE_API_ORIGIN=https://api.delvane.app
    if ($LASTEXITCODE -ne 0) { throw 'Android UAT release build failed.' }
    $apk = 'build/app/outputs/flutter-apk/delvane-business-uat-v2-arm64.apk'
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination $apk
    Get-FileHash -Algorithm SHA256 -LiteralPath $apk
} finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    Pop-Location
}
