# Release privacy and project-isolation policy

This repository is public. Release automation is intentionally strict.

Before any package can be published, GitHub Actions performs all of these checks:

1. The workflow verifies that `GITHUB_REPOSITORY` is exactly `coachedai/tailscale-quick-repair`.
2. The checked-out Git remote must point to this repository.
3. Validation runs with read-only repository permissions.
4. Repository files are scanned for secrets, personal Windows paths, email addresses, literal IP addresses, machine-specific VPS/device names, private config files, and cross-project references.
5. Cross-project content is forbidden from repository paths and file contents.
6. The staged update package is scanned again after build.
7. The downloaded validation artifact is expanded and scanned a third time immediately before publication.
8. Only the publish job receives `contents: write`, and that token is scoped to this repository.

## Local configuration

Machine-specific settings are private local state and must never be committed.

Quick Repair reads local configuration from:

`%ProgramData%\TailscaleQuickRepair\config.json`

That file is intentionally excluded from the repository and update package. Updates preserve the existing local configuration.

Example shape only:

```json
{
  "schema": 1,
  "peer": "<your Tailscale peer IP or MagicDNS name>"
}
```

Do not put real peer addresses, usernames, machine names, emails, API keys, passwords, business-project data, or other personal information in this public repository.
