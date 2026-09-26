# Phase 7 validation follow-through

This change set is prepared for the existing unpublished RC3 candidate. It must
not be treated as Windows acceptance or release authorization.

## Changes

- Restore one complete monotonic RC version expression in the upgrade fixture;
  remove accidental duplicated script content rather than loosening acceptance.
- Parse source with native Windows PowerShell before build and before any
  upgrade fixture mutation. Parser evidence contains hashes and codes only.
- Guard passive startup presentation against active UI repair/update/shutdown
  and newer full-check state. Passive observation remains local-only and cannot
  authorize a repair or change another VPN.
- Make full-history privacy acceptance a direct dependency of the Preview
  publisher. Acknowledged historical findings remain failures, not exceptions.
- Scan every historical path alias, annotated tag and ref name; do not follow
  submodules or symlinks. Reject undecodable and binary-in-text content.
- Avoid echoing matched addresses, emails or potentially sensitive filenames
  into scan output, and do not archive rejected source snapshots.

## Verification boundaries

Offline Python tests exercise synthetic temporary Git repositories, history
scan output, and workflow/source structure. They do not execute PowerShell,
WPF, Setup, scheduled tasks, services, the updater or live network changes.

Before RC3 can be published, native Windows syntax, packaged runtime, passive
presentation, update compatibility, protected handoff, interruption recovery,
permissions and recurrence gates must pass for the exact final source. The
history audit must report no findings. Keep both publication switches off.

Non-blocking startup observation and real desktop behavior remain explicit
acceptance work; a static function check is not proof of UI responsiveness.

Real-device evidence stays off GitHub. Do not edit local versions, delete
Guardian records or bypass an acceptance gate to make a test pass.
