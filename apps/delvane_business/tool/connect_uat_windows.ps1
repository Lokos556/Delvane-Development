# Start a loopback-only tunnel for the dedicated Windows UAT release.
[CmdletBinding()]
param(
    [string]$Executable = '',
    [switch]$TunnelOnly
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Executable)) {
    $Executable = Join-Path $PSScriptRoot '../build/windows-uat/x64/runner/Release/delvane_business.exe'
}
$gitSsh = 'C:\Program Files\Git\usr\bin'
$remote = 'delvane-uat@2.29.168.55'
$origin = 'https://127.0.0.1:18443'
$sshDirectory = Join-Path $env:USERPROFILE '.ssh'
$agentFile = Join-Path $sshDirectory 'delvane-uat-agent-socket'
$python = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../.venv/Scripts/python.exe')).Path
if (-not $TunnelOnly) { $Executable = (Resolve-Path -LiteralPath $Executable).Path }
$privateDir = Join-Path ([IO.Path]::GetTempPath()) ('delvane-uat-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($privateDir)
$pin = Join-Path $privateDir 'known_hosts'
$cert = Join-Path $privateDir 'certificate.pem'
$errorFile = Join-Path $privateDir 'ssh-error.txt'
$savedAgent = $env:SSH_AUTH_SOCK
$savedCertificate = $env:DELVANE_UAT_TLS_CERTIFICATE
$tunnel = $null

try {
    $env:SSH_AUTH_SOCK = (Get-Content -LiteralPath $agentFile -Raw).Trim()
    & "$gitSsh\ssh-add.exe" -l | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unlock the existing key in the Git for Windows SSH agent.' }
    $knownHosts = Join-Path $sshDirectory 'known_hosts'
    $entry = @(& "$gitSsh\ssh-keygen.exe" -F '2.29.168.55' -f $knownHosts |
        Where-Object { $_ -match '^[^#]+\s+ssh-ed25519\s+' })
    if ($entry.Count -ne 1) { throw 'Expected one pinned Hetzner ED25519 host key.' }
    Set-Content -LiteralPath $pin -Value $entry[0] -Encoding ascii
    $fingerprint = (& "$gitSsh\ssh-keygen.exe" -lf $pin -E sha256) -split '\s+'
    if ($LASTEXITCODE -ne 0 -or $fingerprint[1] -cne 'SHA256:H+UWQhcjqvjgZuv9U+24xKnSy6K254h9zDm6TKh9rCo') {
        throw 'The Hetzner SSH host key does not match its verified fingerprint.'
    }
    $options = @('-F', 'none', '-i', (Join-Path $sshDirectory 'id_ed25519'), '-o', 'Port=22',
        '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes',
        '-o', 'HostKeyAlgorithms=ssh-ed25519', '-o', "UserKnownHostsFile=$pin",
        '-o', 'GlobalKnownHostsFile=none', '-o', 'ForwardAgent=no', '-o', 'ConnectTimeout=10')
    $certificate = @(& "$gitSsh\ssh.exe" @options $remote 'test -S /run/delvane-uat-access/https.sock && cat /run/delvane-uat-access/cert.pem')
    if ($LASTEXITCODE -ne 0 -or $certificate[0] -cne '-----BEGIN CERTIFICATE-----' -or
        $certificate[-1] -cne '-----END CERTIFICATE-----') {
        throw 'The administrator must start the verified Hetzner UAT relay first.'
    }
    Set-Content -LiteralPath $cert -Value $certificate -Encoding ascii
    $forwarding = $options + @('-N', '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=15',
        '-o', 'ServerAliveCountMax=2', '-L', '127.0.0.1:18443:/run/delvane-uat-access/https.sock', $remote)
    $commandLine = ($forwarding | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $processOptions = @{
        FilePath = "$gitSsh\ssh.exe"
        ArgumentList = $commandLine
        WindowStyle = 'Hidden'
        RedirectStandardError = $errorFile
        PassThru = $true
    }
    $tunnel = Start-Process @processOptions

    $probe = @'
import json
import re
import ssl
import sys
import urllib.request

class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None

context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
context.load_verify_locations(cafile=sys.argv[1])
opener = urllib.request.build_opener(
    urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context), NoRedirects()
)
with opener.open("https://127.0.0.1:18443/api/client/environment", timeout=3) as response:
    info = json.load(response)
if (info.get("environment") != "staging" or info.get("secure_cookies") is not True
        or not re.fullmatch(r"delvane-uat-[a-f0-9]{12}", info.get("deployment_id", ""))):
    raise SystemExit("Unexpected deployment metadata")
print(info["deployment_id"])
'@
    $deployment = $null
    $ready = $false
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        if ($tunnel.HasExited) {
            throw "SSH forwarding stopped: $(Get-Content -LiteralPath $errorFile -Raw)"
        }
        $deployment = $probe | & $python -I - $cert 2>$null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "Pinned HTTPS staging verification failed. $(Get-Content -LiteralPath $errorFile -Raw)" }
    $env:DELVANE_UAT_TLS_CERTIFICATE = $cert
    Write-Host "Verified $deployment at $origin."
    if ($TunnelOnly) {
        Read-Host 'Press Enter to close the tunnel' | Out-Null
    } else {
        $client = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable) -PassThru
        $client.WaitForExit()
    }
} finally {
    if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -InputObject $tunnel }
    $env:SSH_AUTH_SOCK = $savedAgent
    $env:DELVANE_UAT_TLS_CERTIFICATE = $savedCertificate
    foreach ($path in @($pin, $cert, $errorFile)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    Remove-Item -LiteralPath $privateDir
}
