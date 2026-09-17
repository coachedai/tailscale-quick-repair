# Tailscale Quick Repair

A focused Windows utility for checking local Tailscale health, verifying a remote Tailscale peer, and applying the proven Tailscale-only repair when needed.

This repository is the public source and update channel for **Tailscale Quick Repair**.

## Current baseline

- Current preview release: `3.0.0-phase2.2.5`
- Native self-update channel: enabled
- Stable manifest: `updates/latest.json`
- Releases are validated by GitHub Actions before publication.

## What the updater verifies

Quick Repair reads the public manifest through the GitHub API, downloads only release assets from this repository, and verifies the published package size and SHA-256 before installation.

The package also contains an inner manifest. Every packaged file is checked for its exact relative path, size, and SHA-256. The release pipeline then extracts the finished ZIP again and repeats those checks before publication.

Updates are applied transactionally to user-level app files, with a rollback checkpoint and automatic restart. The current updater is native and does not use the retired encoded-PowerShell/BAT update path.

## Privacy

Machine-specific values such as peer addresses, usernames, local paths, and user settings are not stored in this repository. Existing installations keep their target peer in local configuration under `%LOCALAPPDATA%\TailscaleQuickRepair\config.json`.

The release pipeline performs repository-isolation and privacy scans before validation and again before publication.

## Repair scope

The repair engine is intentionally narrow. Quick Repair may restart the Tailscale service when the configured peer is reported online by Tailscale but cannot actually be reached. An offline peer does not trigger that recovery. Ordinary UI and updater changes must not broaden repair scope.

## Public installer track

The next `2.3` track is turning the current fixed installation into a general public download. That work includes a generic privileged backend, first-run target setup, a later **Change target** control, and a normal Windows installer so another user can point Quick Repair at their own Tailscale IP or MagicDNS device.

Until that migration is complete, the public update packages are intended for already-configured Quick Repair installations rather than fresh third-party installs.

## Publishing

Normal development keeps `release/publish.json` at `"publish": false`. A release is published only after repository isolation, privacy checks, Windows/WPF validation, native updater compilation, HTTPS/TLS validation, package-manifest round-trip verification, and final package scanning all pass.
