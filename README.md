# Tailscale Quick Repair

A focused Windows utility for checking local Tailscale health, verifying a remote Tailscale peer, and applying the proven Tailscale-only repair when needed.

This repository is the public source and update channel for **Tailscale Quick Repair**.

## Install

New users install with the native Windows Setup release asset. Setup asks for the Tailscale target this PC should check — either a Tailscale IP or a MagicDNS device name — and can optionally start Quick Repair with Windows.

Existing installs update from **Details → Maintenance → Check again → Update now**. Ordinary app updates stay user-level. Releases that update the protected repair engine hand off to the native Setup host and request normal Windows administrator approval.

See `docs/INSTALL.md` for the full installation and upgrade flow.

## Privacy

Machine-specific values such as peer addresses, usernames, local paths and settings are not stored in this repository. Each PC keeps its selected target in:

`%LOCALAPPDATA%\TailscaleQuickRepair\config.json`

The target can be changed later inside Quick Repair. It is not uploaded to GitHub.

The release pipeline performs repository-isolation and privacy scans before validation and again immediately before publication.

## Repair scope

The repair engine is intentionally narrow. Quick Repair checks local Tailscale health and the configured remote peer. It may recycle the Tailscale service when the peer is reported online by Tailscale but cannot actually be reached. An offline peer does not trigger that recovery.

The product does not perform broad Windows network resets as part of normal repair.

## Updates and verification

Quick Repair reads the public update manifest through the GitHub API and only accepts release assets from this repository.

Before installation it verifies the published package size and SHA-256. The package also contains an inner manifest, and every packaged file is checked for its exact relative path, size and SHA-256.

The release pipeline then extracts the finished package again and repeats those checks before publication. Protected-engine releases also build and verify a separate full Setup package.

Updates use protected transaction recovery for payload files. If Setup is interrupted after the new payload is already verified, its Windows integration steps are safe to replay to the same release state. The update path is native and does not use the retired encoded-PowerShell/BAT bridge.

See `docs/interrupted-setup-recovery.md` for the recovery model and its current limits.

## Main components

- Native desktop host
- Tailscale-only repair engine
- Optional automatic repair monitor
- Read-only advanced diagnostics
- Native self-updater
- Native Setup / repair-integration host
- Per-device target configuration

## Build and release safety

Normal development keeps `release/publish.json` at `"publish": false`.

A release is only published after repository isolation, privacy checks, PowerShell/WPF validation, native compilation, HTTPS/TLS checks, package-manifest round-trip verification, independent setup-package verification and final package scanning pass.

Preview Windows executables are not currently Authenticode/code-signed, so Windows may show the standard publisher warning on a fresh download. The SHA-256 hashes published with each release are the integrity source until signing is added.
