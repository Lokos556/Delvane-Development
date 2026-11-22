# Windows access to the isolated Hetzner UAT

The dedicated Windows staging release connects to `https://127.0.0.1:18443`. Git for Windows SSH forwards that local port to one Unix socket on `delvane-test-01`. The relay is bound to the running Delvane container's network namespace and connects only to `127.0.0.1:8080` inside it. The socket is readable and writable by the UAT SSH account. The relay drops privileges after binding. The application and PostgreSQL retain their existing bridge and firewall policy, with zero published ports. The relay has no Docker socket and provides no PostgreSQL access. [OpenSSH forwarding syntax](https://man.openbsd.org/ssh#L)

The relay generates a one-day TLS certificate for `127.0.0.1`. The launcher obtains the public certificate through pinned SSH and trusts it only in this staging process. Normal TLS hostname verification, staging deployment checks, secure cookies and CSRF still apply. Regular builds keep their existing origin and trust rules. The government integrations are outside this access path.

## Start access

1. In the Hetzner root console, copy and verify the staged relay script.

   ```sh
   install -m 0600 /home/delvane-uat/delvane-uat-preflight/windows-uat-relay.sh /root/windows-uat-relay.sh
   sha256sum /root/windows-uat-relay.sh
   ```

   Expected SHA-256 is `5738f61e2fd063b3fc2df7c9b5352890bc45b33812a26f076bdae4c794782b05`. If it matches, run `bash /root/windows-uat-relay.sh`. Choose a disposable PMS password at the hidden prompt. Keep it private and leave the root console open when it reports readiness.

2. On Windows, unlock the existing Git for Windows SSH identity if needed. From the repository root, start the tunnel and release together.

   ```powershell
   .\apps\delvane_business\tool\connect_uat_windows.ps1
   ```

   The launcher prints the verified staging deployment before starting the app. Add `-TunnelOnly` to check the HTTPS connection without opening Delvane. This mode stops when you press Enter. The launcher needs the existing repository Python virtual environment.

3. Sign in as `owner-windows@uat.invalid` using the disposable password. The account belongs to the fictional UAT tenant. Select the synthetic reporting property.

## Verify in the Windows release

1. Confirm the property dashboard and reservation list load. Create a direct reservation for a fictional guest on unused future dates, refresh and verify the saved reference. Open that reservation, change a non-sensitive booking detail and confirm the edit after refresh.
2. Open **Apartments and rooms**. Choose an eligible past date and the existing physical room type. Submit the authorized historical count with a fictional reason. Verify the new revision and the current selling inventory separately.
3. Open **Government reporting**, then **NTAK**. Inspect the synthetic property's blocked job and one redacted evidence export. Confirm it shows zero transmission attempts and no official acceptance. Check the disabled transmission indicators for both NTAK and VIZA.
4. Sign out and close Delvane. The launcher stops its local SSH process. In the root console, press Ctrl+C to close the relay and deactivate the synthetic operator, which also revokes its sessions. The relay stops automatically after four hours. PostgreSQL and Delvane keep running.

If the relay stops unexpectedly, check that the socket and synthetic session were closed before restarting. The root script is scoped to the restored Phase C synthetic lab and refuses another deployment. If SSH rejects Unix socket forwarding, retain the existing server policy and record the refusal.

## Release artifact and reproduction

The dedicated executable is `apps/delvane_business/build/windows-uat/x64/runner/Release/delvane_business.exe`. It was built with Flutter 3.50.0 and Dart 3.14.0. Keep the release files together.

From the Flutter project directory, generate the build configuration using:

```powershell
flutter --no-version-check build windows --release --config-only --dart-define=DELVANE_ENV=staging --dart-define=DELVANE_API_ORIGIN=https://127.0.0.1:18443 --dart-define=DELVANE_UAT_TUNNEL=true
```

On this workstation, Flutter writes the generated defines before reporting a generator conflict for the existing default Windows build cache. Leave that cache in place and use the separate x64 directory. Locate CMake through the existing Visual Studio installation.

```powershell
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsPath = & $vswhere -latest -products '*' -version '[18.0,19.0)' -requires Microsoft.VisualStudio.Workload.NativeDesktop Microsoft.VisualStudio.Component.VC.CMake.Project -property installationPath | Select-Object -First 1
$cmake = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
& $cmake -S windows -B build/windows-uat/x64 -G 'Visual Studio 18 2026' -A x64 -DFLUTTER_TARGET_PLATFORM=windows-x64
& $cmake --build build/windows-uat/x64 --config Release --target INSTALL
```

Local verification covered the actual relay in a Linux network namespace, a rejected connection from a different local UID, and the actual Windows release with a trusted and unrelated synthetic TLS certificate. It did not authenticate against Hetzner. The operator walkthrough requires the root relay and the synthetic owner password.
