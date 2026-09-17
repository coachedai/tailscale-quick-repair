# Install and update guide

## Before installing

Tailscale Quick Repair is a Windows utility. Install Tailscale on the PC first and sign in normally.

Choose the Tailscale device you want Quick Repair to verify. You can use either:

- its Tailscale IP address, or
- its MagicDNS name.

The target can be another Windows PC, a server, or a VPS. Quick Repair tests that device over Tailscale but does not install or change anything on the target machine.

## Fresh install

1. Open the newest GitHub Release for this repository.
2. Download `TailscaleQuickRepair-Setup-<version>.exe`.
3. Run the Setup executable.
4. Approve the Windows administrator prompt.
5. Enter the Tailscale IP or MagicDNS name of the device to monitor.
6. Choose whether Quick Repair should start with Windows.
7. Setup downloads the matching trusted Setup package from this repository, verifies its size and SHA-256, verifies every file in the package manifest, installs the app and protected repair components, then starts Quick Repair.

The configured target is stored locally in `%LOCALAPPDATA%\TailscaleQuickRepair\config.json`.

## Change the target later

Open **Details**, find the **Remote** section, choose **Change**, enter the new Tailscale IP or MagicDNS name, and save it.

The new value remains local to that Windows account. It is not added to GitHub or the public release manifest.

## In-app updates

Open **Details → Maintenance** and choose **Check again**.

If a normal app update is available, **Update now** downloads and verifies the release package, stages it, creates a rollback checkpoint, replaces the user-level app files, verifies the installed hashes, and restarts Quick Repair.

If an update also changes the protected repair engine or scheduled tasks, **Update now** hands the migration to `TailscaleQuickRepairSetup.exe`. Windows then asks for administrator approval. The Setup host preserves the existing target and startup preference, verifies the protected Setup package, updates the protected components, rebuilds the scheduled tasks/integration, and restarts the app.

## What gets installed

User-level app files are kept under `%LOCALAPPDATA%\TailscaleQuickRepair`.

Protected repair components are kept under `%ProgramData%\TailscaleQuickRepair` and are invoked through Windows Task Scheduler when elevated repair work is necessary.

The target configuration remains under LocalAppData and is not part of release packages.

## Security model

Quick Repair trusts only the public update manifest in this repository and release assets hosted under this repository's GitHub Releases path. Release package size and SHA-256 are checked before installation. The inner package manifest then verifies each included file's exact relative path, size, and SHA-256.

Release automation performs the same checks again before publication, plus privacy and repository-isolation scanning.

## SmartScreen

The current preview executables are not Authenticode code-signed. Windows SmartScreen can therefore show an unfamiliar-app warning on a newly downloaded Setup executable even when its published SHA-256 matches the release. Code signing is a separate distribution-hardening step from the package hash verification described above.
