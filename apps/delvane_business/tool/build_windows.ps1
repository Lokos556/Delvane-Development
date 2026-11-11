# Flutter 3.32 only knows VS 2019/2022 generator names. This app-local fallback
# uses installed VS 2026 without modifying Flutter, Visual Studio, or the backend.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$appRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $appRoot
try {
    $ErrorActionPreference = 'Continue'
    $output = & flutter --no-version-check build windows --release 2>&1
    $flutterExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $output | ForEach-Object {
        $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
        if (-not [string]::IsNullOrWhiteSpace($line) -and $line -ne 'System.Management.Automation.RemoteException') { Write-Host $line }
    }
    if ($flutterExit -eq 0) { exit 0 }

    # Do not conceal Dart/compiler failures or attempt an unrelated fallback.
    if (($output -join "`n") -notmatch 'Visual Studio 16 2019') {
        throw "Flutter build failed ($flutterExit). No generator compatibility fallback applies."
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsPath = (& $vswhere -latest -products '*' -version '[18.0,19.0)' -requires Microsoft.VisualStudio.Workload.NativeDesktop Microsoft.VisualStudio.Component.VC.CMake.Project -property installationPath | Select-Object -First 1)
    if (-not $vsPath) { throw 'A complete Visual Studio 2026 C++ installation is required for this fallback.' }
    $cmake = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path -LiteralPath $cmake)) { throw 'Visual Studio CMake executable was not found.' }
    if (-not (Test-Path -LiteralPath 'windows/flutter/ephemeral/generated_config.cmake')) {
        throw 'Flutter did not generate its build configuration. Fix the Flutter preparation error first.'
    }
    Write-Host 'Using the project-local Visual Studio 2026 generator fallback.'
    & $cmake -S windows -B build/windows-vs2026/x64 -G 'Visual Studio 18 2026' -A x64 -DFLUTTER_TARGET_PLATFORM=windows-x64
    if ($LASTEXITCODE -ne 0) { throw 'Windows CMake configuration failed.' }
    & $cmake --build build/windows-vs2026/x64 --config Release --target INSTALL
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
    $bundle = Join-Path $appRoot 'build/windows-vs2026/x64/runner/Release'
    if (-not (Test-Path -LiteralPath (Join-Path $bundle 'delvane_business.exe'))) { throw 'Release executable was not produced.' }
    Write-Host "Windows release bundle: $bundle"
} finally {
    Pop-Location
}
