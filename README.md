# Tailscale Quick Repair

A focused Windows utility for checking local Tailscale health, verifying a remote Tailscale peer, and applying a narrow Tailscale-only repair when needed.

This repository contains the public source, release assets, and trusted update channel for **Tailscale Quick Repair**.

## Install

From the 2.3 public release onward, new users can install Quick Repair with the native Windows Setup executable from the newest GitHub Release.

1. Install Tailscale and sign in on this PC.
2. Download `TailscaleQuickRepair-Setup-<version>.exe` from the latest release.
3. Run Setup and approve the Windows administrator prompt.
4. Enter the Tailscale IP or MagicDNS name of the remote PC, server, or VPS you want Quick Repair to check.
5. Choose whether Quick Repair should start with Windows.

The target can be changed later from **Details → Remote → Change**. The target is saved only on that PC under `%LOCALAPPDATA%\TailscaleQuickRepair\config.json`.

See [docs/INSTALL.md](docs/INSTALL.md) for the full install and update flow.

## What it does

Quick Repair checks four parts of the path:

- the local Tailscale desktop client
- the local Tailscale service/backend
- the configured remote Tailscale device
- the current direct or DERP-relayed path and latency

The repair engine is intentionally narrow. It may restart the local Tailscale service when Tailscale reports the configured peer online but the peer cannot actually be reached. A peer reported offline does not trigger that recovery. Quick Repair does not reset Winsock, TCP/IP, or unrelated network adapters.

The configured remote machine is a health target only; Quick Repair does not modify that remote machine.

## Automatic repair and diagnostics

Automatic repair is optional and local-only. It watches the local Tailscale client/service and uses the same protected repair path when recovery is actually needed.

Advanced Diagnostics is read-only. It can inspect Tailscale path, protocol and local VPN/network conditions, but it does not change the main health result or network settings.

## Updates

Quick Repair uses `updates/latest.json` as its public update channel. The app downloads release assets only from this repository and verifies the published file size and SHA-256 before installation.

Every update ZIP also contains `package-manifest.json`. Each packaged file is checked for its relative path, size, and SHA-256. The release pipeline extracts the finished ZIP and repeats those checks before publication.

Normal app/UI updates stay user-level and do not require elevation. If a release needs to replace the protected repair engine or scheduled tasks, Quick Repair hands the update to the native Setup host and Windows asks for administrator approval once.

The retired BAT/encoded-PowerShell update path is not used by the current native updater.

## Privacy

Machine-specific values such as peer addresses, usernames, local paths, and settings are not stored in this repository or uploaded by Quick Repair. The configured target stays in local configuration on the PC running the app.

The release pipeline performs repository-isolation and privacy scans before validation and again before publication. See [docs/PRIVACY.md](docs/PRIVACY.md).

## Release status

The current published version and exact trusted hashes are always defined by [`updates/latest.json`](updates/latest.json) and the corresponding GitHub Release. Development keeps `release/publish.json` disabled until the release candidate passes its Windows, WPF, native-host, privacy, package-manifest, SHA-256, and round-trip validation gates.

## Preview software

Quick Repair is still in preview. Current binaries are not Authenticode code-signed, so Windows SmartScreen may show an unfamiliar-app warning on a fresh download. Release hashes are published and independently verified by the build pipeline.
