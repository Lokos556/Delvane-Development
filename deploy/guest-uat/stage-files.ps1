# Transfer the previously built controls over pinned Git for Windows SSH.
[CmdletBinding()]
param([switch]$ResumeStorage, [switch]$RecoverSnapshot, [switch]$ResendTrial, [switch]$ResendDiagnostic, [switch]$Permanent, [switch]$PermanentV2, [switch]$PermanentV3)
$ErrorActionPreference = 'Stop'
$git = 'C:/Program Files/Git/usr/bin'
$sshHome = Join-Path $env:USERPROFILE '.ssh'
$bundle = Join-Path $PSScriptRoot '../../build/guest-uat'
$remote = 'delvane-uat@2.29.168.55'
$stage = '/home/delvane-uat/delvane-guest-storage-3091'
$manifest = 'STORAGE-STAGE-SHA256SUMS-v2'
$payload = @('delvane-guest-3091-local.tar.gz', 'delvane-guest-uat-storage-controls-v2.tar.gz',
    'cloudflared-2026.11.1-linux-amd64.tar.gz', 'deploy-private-storage-v2.sh', 'start-docker-connector.sh')
if ($PermanentV3) {
    $bundle = Join-Path $PSScriptRoot '../../build/uat-v3'
    $stage = '/home/delvane-uat/delvane-uat-v3'
    $manifest = 'SHA256SUMS'
    $payload = @('delvane-permanent-v3-3091-local.tar.gz', 'replace-release.py')
} elseif ($PermanentV2) {
    $bundle = Join-Path $PSScriptRoot '../../build/uat-v2'
    $stage = '/home/delvane-uat/delvane-uat-v2'
    $manifest = 'SHA256SUMS'
    $payload = @('delvane-permanent-v2-3091-local.tar.gz', 'replace-release.py')
} elseif ($Permanent) {
    $bundle = Join-Path $PSScriptRoot '../../build/permanent-uat'
    $manifest = 'PERMANENT-STAGE-SHA256SUMS'
    $payload = @('delvane-permanent-3091-local.tar.gz', 'delvane-permanent-controls.tar.gz', 'install-delvane-permanent.sh')
} elseif ($ResendDiagnostic) {
    $manifest = 'RESEND-DIAGNOSTIC-SHA256SUMS'
    $payload = @('resend-netcheck.py')
} elseif ($ResendTrial) {
    $manifest = 'RESEND-TRIAL-SHA256SUMS-v2'
    $payload = @('delvane-resend-trial-controls-v2.tar.gz', 'resend-trial-v2.sh')
} elseif ($RecoverSnapshot) {
    $manifest = 'STORAGE-STAGE-SHA256SUMS-v4'
    $payload = @('delvane-guest-uat-storage-controls-v4.tar.gz', 'deploy-snapshot-recovery.sh')
} elseif ($ResumeStorage) {
    $manifest = 'STORAGE-STAGE-SHA256SUMS-v3'
    $payload = @('delvane-guest-uat-storage-controls-v3.tar.gz', 'deploy-private-storage-v3.sh')
}
$files = $payload + $manifest
$sums = @($payload | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath (Join-Path $bundle $_) -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $_"
})
$manifestLines = @(Get-Content -LiteralPath (Join-Path $bundle $manifest))
if (Compare-Object $sums $manifestLines) { throw 'The local deployment files do not match their checksum manifest.' }
$env:SSH_AUTH_SOCK = (Get-Content -LiteralPath (Join-Path $sshHome 'delvane-uat-agent-socket') -Raw).Trim()
& "$git/ssh-add.exe" -l | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unlock the existing Git SSH agent key before staging.' }
$pin = Join-Path ([IO.Path]::GetTempPath()) ('delvane-guest-pin-' + [guid]::NewGuid())
try {
    $entries = @(& "$git/ssh-keygen.exe" -F '2.29.168.55' -f (Join-Path $sshHome 'known_hosts') |
        Where-Object { $_ -match '^[^#]+\s+ssh-ed25519\s+' })
    if ($entries.Count -ne 1) { throw 'Expected one pinned Hetzner ED25519 key.' }
    Set-Content -LiteralPath $pin -Value $entries[0] -Encoding ascii
    $fingerprint = (& "$git/ssh-keygen.exe" -lf $pin -E sha256) -split '\s+'
    if ($LASTEXITCODE -ne 0 -or $fingerprint[1] -cne 'SHA256:H+UWQhcjqvjgZuv9U+24xKnSy6K254h9zDm6TKh9rCo') {
        throw 'The saved host key fingerprint does not match.'
    }
    $options = @('-F', 'none', '-i', (Join-Path $sshHome 'id_ed25519'), '-o', 'Port=22',
        '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes',
        '-o', 'HostKeyAlgorithms=ssh-ed25519', '-o', "UserKnownHostsFile=$pin",
        '-o', 'GlobalKnownHostsFile=none', '-o', 'ForwardAgent=no', '-o', 'ConnectTimeout=10')
    $preflight = "test `$(hostname -s) = delvane-test-01 && test `$(id -un) = delvane-uat && umask 077 && mkdir -p '$stage' && test ! -L '$stage' && test `$(stat -c '%U:%a' '$stage') = delvane-uat:700"
    & "$git/ssh.exe" @options $remote $preflight
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify the server account and its private staging directory.' }
    $paths = @($files | ForEach-Object { (Resolve-Path -LiteralPath (Join-Path $bundle $_)).Path })
    & "$git/scp.exe" @options @paths "${remote}:${stage}/"
    if ($LASTEXITCODE -ne 0) { throw 'The staged transfer failed.' }
    $fileArguments = $files -join ' '
    $payloadArguments = $payload -join ' '
    $remoteSums = @(& "$git/ssh.exe" @options $remote "cd '$stage' && chmod 600 -- $fileArguments && sha256sum -- $payloadArguments")
    if ($LASTEXITCODE -ne 0 -or (Compare-Object $sums $remoteSums)) { throw 'The staged files do not match the local checksums.' }
    $remoteSums | Write-Host
    & "$git/ssh.exe" @options $remote "cd '$stage' && stat -c '%a %n' -- $fileArguments"
    if ($LASTEXITCODE -ne 0) { throw 'Remote permission or checksum verification failed.' }
    if ($ResumeStorage -or $RecoverSnapshot) {
        & "$git/ssh.exe" @options $remote "cd '$stage' && sha256sum -c --strict STORAGE-STAGE-SHA256SUMS-v2"
        if ($LASTEXITCODE -ne 0) { throw 'The original staged archives did not pass checksum verification.' }
    }
    Write-Host "Verified deployment files staged at $stage."
}
finally {
    if (Test-Path -LiteralPath $pin) { Remove-Item -LiteralPath $pin }
}
