param(
    [string]$DeviceId,
    [switch]$Install
)

# No server launch, database access, firewall change or LAN listener. The server
# must already be running through the repository's guarded development launcher.
$ErrorActionPreference = 'Stop'
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
$adbPath = if ($adbCommand) { $adbCommand.Source } else {
    Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
}
if (-not (Test-Path -LiteralPath $adbPath)) {
    throw 'adb was not found. Install Android SDK Platform-Tools or add adb to PATH.'
}
$devices = @(& $adbPath devices)
if ($LASTEXITCODE -ne 0) { throw 'adb device discovery failed.' }
$authorized = @($devices | ForEach-Object {
    if ($_ -match '^(\S+)\s+device$') { $Matches[1] }
})
if (-not $DeviceId) {
    if ($authorized.Count -ne 1) {
        throw 'Connect and authorize one USB Android device, or use -DeviceId for an authorized device. No installation or forwarding was performed.'
    }
    $DeviceId = $authorized[0]
}
if ($DeviceId -notin $authorized) { throw 'The selected Android device is not connected and authorized.' }

$marker = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/development/workspace' -TimeoutSec 5 -MaximumRedirection 0
if ($marker.isolated -ne $true -or [string]::IsNullOrWhiteSpace($marker.workspace_id)) {
    throw 'The local server is not the isolated development workspace. Refusing to forward or install.'
}
$forwards = @(& $adbPath -s $DeviceId reverse --list)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect USB reverse forwarding.' }
$existing = @($forwards | Where-Object { $_ -match '\s+tcp:8765\s+' })
if ($existing.Count -gt 0) {
    if (@($existing | Where-Object { $_ -notmatch '\s+tcp:8765\s+tcp:8765\s*$' }).Count -gt 0) {
        throw 'Device port 8765 already forwards elsewhere. Refusing to replace it.'
    }
} else {
    & $adbPath -s $DeviceId reverse --no-rebind tcp:8765 tcp:8765
    if ($LASTEXITCODE -ne 0) { throw 'USB reverse forwarding failed.' }
}
Write-Output 'USB forwarding ready: Android 127.0.0.1:8765 -> Windows 127.0.0.1:8765.'
if ($marker.mode) { Write-Output "Isolated backend mode: $($marker.mode)." }
if ($Install) {
    $apk = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apk)) { throw 'Debug APK missing. Run flutter build apk --debug first.' }
    & $adbPath -s $DeviceId install -r $apk
    if ($LASTEXITCODE -ne 0) { throw 'APK installation failed. Existing application data was not removed.' }
    & $adbPath -s $DeviceId shell am start -n com.delvane.delvane_business/.MainActivity
    if ($LASTEXITCODE -ne 0) { throw 'Android activity launch failed.' }
    Write-Output 'Delvane Business launched. Sign in with an isolated development account.'
}
