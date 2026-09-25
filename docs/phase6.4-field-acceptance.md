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

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\field-preview.ps1 -OutputDirectory .
```

The helper verifies both outer SHA-256 sidecars, every inner package-manifest entry, the fixed 6.4 version/code, bridge/protected file boundaries, and the current Windows account before mutation.

For a long-lived installation that still contains the exact pre-protected Quick Repair 2.0 rollback/scripts layout, the refreshed Setup preserves those legacy entries intact in an administrator-only sibling archive before hardening the active protected directory. This compatibility path is available only during a validated protected-update handoff. It never executes legacy files, never treats arbitrary names as legacy, and unrelated or redirected content still fails closed before anything is moved.

The first stage uses the **installed released 5.2.1 updater core** to apply only the user-level bridge. The second stage requests normal Windows administrator approval and uses the **refreshed Setup core** to apply the local protected package. The helper loads that refreshed Setup core from a verified disposable TEMP copy, matching production Setup's self-relocation boundary so the installed Setup executable is not held open while the protected package replaces it.

The field helper itself is developer test tooling and is launched from Windows PowerShell. Any console belonging to the helper is therefore **not** evidence of a product console flash. The no-console requirement applies to normal Quick Repair, updater and Setup operation outside this helper path. The helper waits only for the direct elevated Setup child with a bounded timeout; the resident Quick Repair process relaunched by Setup is not treated as part of that wait.

A small phase6.4-field-result.json file is written beside the helper. Its path is converted to an absolute path before UAC so the elevated child cannot redirect the result by starting in a different Windows working directory. It contains only typed booleans (including whether a same-version bridge refresh occurred), the preview version/code, the current acceptance stage and a curated error message when applicable. Unexpected PowerShell exception text is never copied into that file. If the administrator-approved child process fails, the unelevated parent preserves the child's privacy-safe protected-stage name instead of replacing it with a generic UAC-stage result. It does not record the configured peer, Windows SID, usernames, IP addresses, device names or local paths.

## UAC cancellation test

Cancelling the Windows approval prompt is a valid test. Before staging anything, the helper requires the complete published protected baseline to be present. After cancellation it verifies every expected protected baseline file is still present with the same SHA-256, then leaves only the verified user-level bridge plus its protected-update marker staged. If the baseline is incomplete or any protected hash changes, the field run fails closed.

Run the same command again and approve the prompt. The helper recognises the already-staged bridge without replaying the original 5.2.1 -> 6.4 transition. Before protected Setup continues, it reapplies the currently verified user-level preview package with the candidate updater so every same-version bridge byte (including the installed Setup host) matches the exact field pack. Hosted acceptance deliberately corrupts the staged Setup host and proves the retry refreshes it before entering the protected boundary. It also exercises the cancel/stage/retry state transition without claiming to reproduce the physical Windows UAC screen.

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
