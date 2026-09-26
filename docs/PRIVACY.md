# Release privacy and project-isolation policy

This repository is public. Release automation is intentionally strict.

Before any package can be published, GitHub Actions performs all of these checks:

1. The workflow verifies that `GITHUB_REPOSITORY` is exactly `coachedai/tailscale-quick-repair`.
2. The checked-out Git remote must point to this repository.
3. Validation runs with read-only repository permissions.
4. Repository files are scanned for secrets, personal Windows paths, email addresses, literal IP addresses, machine-specific VPS/device names, private config files, and cross-project references.
5. Cross-project content is forbidden from repository paths and file contents.
6. Staged update and Setup packages are scanned again after build.
7. Validated release payloads are expanded and scanned again immediately before publication.
8. Only the publish job receives `contents: write`, and that token is scoped to this repository.

## Local configuration

Machine-specific settings are private local state and must never be committed.

Quick Repair stores the configured target under the current Windows user at:

`%LOCALAPPDATA%\TailscaleQuickRepair\config.json`

That file is intentionally excluded from the repository and release packages. Updates and protected migrations preserve the existing local target.

Example shape only:

```json
{
  "peer": "<your Tailscale peer IP or MagicDNS name>"
}
```

The target is used only by the local app and repair/diagnostic workers to test the selected Tailscale device. Quick Repair does not upload that target to GitHub or write it into the public update channel.

Do not put real peer addresses, usernames, machine names, emails, API keys, passwords, business-project data, or other personal information in this public repository.


## Real-machine field testing

Real-machine observations are private and must stay off GitHub.

Do not upload, commit, attach, paste into Actions, or preserve in repository history any real-machine screenshot, screen recording, local log, field-result JSON, crash dump, registry export, configuration file, command transcript, local path, Windows account name, SID, hostname, device name, peer name/address, IP address, tailnet-specific value, VPN-specific local detail, or other machine/user identifier.

Do not record a per-user or per-machine acceptance result in this public repository. Real-machine observations may guide an interactive troubleshooting session, but repository evidence must remain generic and product-scoped. Persisted acceptance evidence on GitHub must come from disposable/synthetic CI fixtures or otherwise contain no information derived from a specific user's computer.

If a real-machine observation reveals a product issue, record only the generalized product behavior or bug necessary to fix it, with all user/machine context removed.

The privacy scanner fails closed on unreviewed non-text/binary repository files. Evidence-like media, screen captures, logs, dumps, registry/event exports, packet captures, opaque archives, office/PDF documents, databases/backups and arbitrary binary blobs are forbidden. Expanded release packages may contain only the expected compiled native executable/library binaries in addition to scanned text files. Literal network identifiers are blocked in normal, regex-escaped and bracket-encoded dotted forms so a defensive pattern cannot accidentally preserve a machine-specific address in source history.


## Historical audit

All reachable repository refs are scanned separately from the current-tree release scan. The historical audit reports only Git object hashes, generic reason codes and public commit hashes; it never prints matched sensitive content. The history audit runs on every development-branch push so a value that is later deleted from the current tree cannot silently remain only in Git history.

One pre-isolation README object is retained as explicit historical redaction debt by its Git object hash only. It contained a cross-project naming reference that was removed in a later sanitized revision. No content, URL, secret, configuration, path, address or data from that unrelated project is included in the current repository. Any additional historical cross-project or privacy finding fails the audit.

Removing the legacy object itself would require a coordinated destructive rewrite of public Git history, branches and release/tag commit identities. That is not performed automatically.
