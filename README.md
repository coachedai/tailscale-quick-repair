# Tailscale Quick Repair

A small Windows utility that checks and repairs a local Tailscale connection and verifies a configured peer.

This repository is the source and update channel for **Tailscale Quick Repair**. It is intentionally isolated from unrelated projects and repositories.

## Current track

- Current development baseline: `3.0.0-phase2.1`
- Frozen stable base: `2.0.0`
- Update manifest: `updates/latest.json`
- Releases are validated by GitHub Actions before they can be published.

## Update architecture

Quick Repair uses one stable public manifest URL:

`https://raw.githubusercontent.com/coachedai/tailscale-quick-repair/main/updates/latest.json`

A published update contains a version, monotonically increasing `versionCode`, release notes, a ZIP release asset, the ZIP SHA-256, and an inner package manifest with SHA-256 hashes for every shipped file.

The desktop app downloads to a staging directory, verifies hashes, preflights the package, creates a rollback checkpoint, installs transactionally, and restarts itself.

## Privacy

Machine-specific values such as peer addresses, usernames, paths and local settings are not stored in this repository. They stay in local configuration under `%ProgramData%\TailscaleQuickRepair\config.json`.

## Safety rules

The release pipeline must not publish if validation fails. The working repair backend should only change for a confirmed repair defect. UI/update work must not silently broaden repair scope.

## Publishing

Normal development commits leave `release/publish.json` with `"publish": false`.

When a release is ready, source/version metadata is updated and the publish switch is enabled. GitHub Actions validates repository isolation, privacy, source/package integrity and the final artifact before a release can be published.
