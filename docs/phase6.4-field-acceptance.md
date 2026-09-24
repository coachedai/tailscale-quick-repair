# Phase 6.4 field acceptance

This is the final real-PC acceptance path for 3.0.0-phase6.4.0-preview before any public release. It does not change the live GitHub update manifest and it is not part of the public Quick Repair packages.

## Why a field helper exists

The released 5.2.1 application intentionally trusts only main/updates/latest.json. Publishing the 6.4 preview there merely to test UAC would expose an unfinished release to the public update channel.

Hosted Windows acceptance already proves that the genuine released 5.2.1 updater can apply the exact user-level bridge. The field helper reuses that installed updater core against the exact CI-produced bridge package, then uses the refreshed Setup core against the exact local protected package. The only production network-fetch step replaced by the helper is the unpublished manifest/download lookup.

The helper never changes the product trust policy, never adds a local-package switch to the shipping updater or Setup executable, and is excluded from both public packages.

## Before running

- Start from the genuine installed 5.2.1 release, or from a 6.4 bridge left staged after intentionally cancelling the UAC prompt.
- Exit Quick Repair from the tray menu before the first run.
- Leave **Auto Repair off** for the initial upgrade acceptance.
- Keep Tailscale signed in normally. Do not deliberately break networking for the first pass.
- Use the same Windows account to approve the administrator prompt. A different administrator account is intentionally refused.

## Run

Keep these files together in one folder:

- field-preview.ps1
- TailscaleQuickRepair-3.0.0-phase6.4.0-preview.zip
- its .sha256 sidecar
- TailscaleQuickRepair-SetupPackage-3.0.0-phase6.4.0-preview.zip
- its .sha256 sidecar

Open Windows PowerShell in that folder and run:

powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\field-preview.ps1 -OutputDirectory .


The helper verifies both outer SHA-256 sidecars, every inner package-manifest entry, the fixed 6.4 version/code, bridge/protected file boundaries, and the current Windows account before mutation.

The first stage uses the **installed released 5.2.1 updater core** to apply only the user-level bridge. The second stage requests normal Windows administrator approval and uses the **refreshed Setup core** to apply the local protected package.

A small phase6.4-field-result.json file is written beside the helper. It contains only typed booleans, the preview version/code, the current acceptance stage and an error message when applicable. It does not record the configured peer, Windows SID, usernames, IP addresses, device names or local paths.

## UAC cancellation test

Cancelling the Windows approval prompt is a valid test. The helper reports that approval was cancelled, verifies the protected baseline hashes are unchanged, and leaves the verified bridge plus its protected-update marker staged. If that protected-file check fails, the field run fails closed.

Run the same command again and approve the prompt. The helper recognises the already-staged bridge and continues at the protected boundary instead of trying to reapply 5.2.1 -> 6.4.

## Passing first field upgrade

The first pass is complete only when:

- the same-account UAC approval succeeds;
- the protected marker is removed by protected completion;
- the installed version is exactly 3.0.0-phase6.4.0-preview / 30000740;
- Quick Repair reopens normally;
- the restart acknowledgement is cleared by that reopened candidate;
- there are no PowerShell/console flashes from normal product operation;
- the existing target and startup preference are preserved;
- Tailscale remains signed in and ProtonVPN/network settings are untouched;
- Auto Repair remains off until the initial installed state is checked.

## Follow-up physical acceptance

After the first upgrade passes, test UAC cancel/retry, normal close-to-tray and tray Exit, reboot/logon, sleep/resume, Wi-Fi transitions, ProtonVPN disconnect/reconnect/transition behavior, authenticated local-backend recovery, and finally guarded Auto Repair behavior.

Do not interpret remote peer unavailability as a repair trigger. Optional diagnostics remain read-only and must not influence core health or automatic recovery.
