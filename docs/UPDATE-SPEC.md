# Update protocol v1

## Stable manifest

Clients fetch:

`https://raw.githubusercontent.com/coachedai/tailscale-quick-repair/main/updates/latest.json`

The client compares `versionCode`, not display-version text.

## Manifest fields

- `schema`: update protocol schema.
- `channel`: `stable`, `preview`, or another explicit channel.
- `version`: display version.
- `versionCode`: monotonically increasing integer.
- `published`: only `true` manifests are installable.
- `publishedAt`: UTC ISO-8601 timestamp.
- `mandatory`: reserved for critical future releases; the client still asks the user before installing unless explicitly changed later.
- `notes`: concise release notes.
- `package.url`: public GitHub Release asset URL.
- `package.sha256`: lowercase SHA-256 of the ZIP.
- `package.size`: package size in bytes.

## Update bundle

Each ZIP contains a `package-manifest.json` plus application files.

`package-manifest.json` records the release version, versionCode and SHA-256 of every file in the bundle. The future updater verifies both the outer ZIP hash from `latest.json` and every inner file hash.

## Installer behavior

1. Download to a unique staging directory.
2. Verify outer SHA-256.
3. Extract to staging.
4. Verify every inner file against `package-manifest.json`.
5. Parse PowerShell scripts.
6. Load the WPF XAML in a test window.
7. Self-test the native host.
8. Create a rollback checkpoint.
9. Stop only Quick Repair processes/tasks required for replacement.
10. Commit the update.
11. Verify installed files.
12. Relaunch Quick Repair.
13. Restore the rollback checkpoint if commit or verification fails.

The update channel never contains credentials and the public client never embeds a GitHub token.
