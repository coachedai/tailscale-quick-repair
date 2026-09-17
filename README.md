# Tailscale Quick Repair

A small Windows utility that checks and repairs a local Tailscale connection and verifies a configured peer.

This repository is the source and update channel for **Tailscale Quick Repair**. It is completely separate from the CoachIntake repository.

## Current track

- Current development baseline: `3.0.0-phase1.1`
- Frozen stable base: `2.0.0`
- Update manifest: `updates/latest.json`
- Releases will be built and validated by GitHub Actions.

## Update architecture

Quick Repair will use one stable public manifest URL:

`https://raw.githubusercontent.com/coachedai/tailscale-quick-repair/main/updates/latest.json`

A published update will contain a version, monotonically increasing `versionCode`, release notes, a ZIP release asset, the ZIP SHA-256, and an inner package manifest with SHA-256 hashes for every shipped file.

The desktop app will download to a staging directory, verify hashes, preflight the package, create a rollback checkpoint, install transactionally, and restart itself.

## Safety rules

The release pipeline must not publish if validation fails. The working repair backend should only change for a confirmed repair defect. UI/update work must not silently broaden repair scope.

## Publishing

Normal development commits leave `release/publish.json` with `"publish": false`.

When a release is ready, source/version metadata is updated and the publish switch is enabled. GitHub Actions will build and validate the release package and then update `updates/latest.json`.
