# Phase 6.4 field acceptance

This is the one-time developer field/bootstrap path for **3.0.0-rc.1 / 30001001**. RC1 is published only to the opt-in Early-access channel; Stable `main` and `updates/latest.json` remain on 3.0.0-phase5.2.1. The helper is not part of the shipping Quick Repair packages.

## Why a field helper exists

The released 5.2.1 application and the accepted 6.4.0 field build predate the in-app Early-access selector, so they cannot discover the dedicated Preview manifest themselves. The helper provides a narrowly allowlisted bridge to RC1 without exposing the candidate through Stable.

Hosted Windows acceptance already proves that the genuine released 5.2.1 updater can apply the exact user-level bridge. The field helper reuses that installed updater core against the exact CI-produced bridge package, then uses the refreshed Setup core against the exact local protected package. The only production network-fetch step replaced by the helper is the unpublished manifest/download lookup.

The helper never changes the product trust policy, never adds a local-package switch to the shipping updater or Setup executable, and is excluded from both public packages.

## Before running

- Start from the genuine installed 5.2.1 release, an explicitly allowlisted accepted preview (**3.0.0-phase6.4.0-preview / 30000740** or **3.0.0-phase6.4.3-preview / 30000743**) with a matching Guardian known-good integrity record, or an already-staged RC1 bridge left after intentionally cancelling the UAC prompt.
- Exit Quick Repair from the tray menu before the first run.
- Leave **Auto Repair off** for the initial upgrade acceptance.
- Keep Tailscale signed in normally. Do not deliberately break networking for the first pass.
- Use the same Windows account to approve the administrator prompt. A different administrator account is intentionally refused.

## Run

Keep these files together in one folder:

- field-preview.ps1
- TailscaleQuickRepair-3.0.0-rc.1.zip
- its .sha256 sidecar
- TailscaleQuickRepair-SetupPackage-3.0.0-rc.1.zip
- its .sha256 sidecar

Open Windows PowerShell in that folder and run:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\field-preview.ps1 -OutputDirectory .
```

The helper verifies both outer SHA-256 sidecars, every inner package-manifest entry, the fixed RC1 version/code/channel, bridge/protected file boundaries, and the current Windows account before mutation. Previous-preview entry is exact-match only; no version ranges or arbitrary local packages are accepted.

For a long-lived installation that still contains the exact pre-protected Quick Repair 2.0 rollback/scripts layout, the refreshed Setup preserves those legacy entries intact in an administrator-only sibling archive before hardening the active protected directory. This compatibility path is available only during a validated protected-update handoff. It never executes legacy files, never treats arbitrary names as legacy, and unrelated or redirected content still fails closed before anything is moved.

The first stage uses the updater already installed by the accepted starting baseline to apply only the verified user-level bridge. For the previous-preview path, the helper first requires a clean restart/marker state and a Guardian known-good record matching the installed integrity manifest. The second stage requests normal Windows administrator approval and uses the **refreshed Setup core** to apply the local protected package. The helper loads that refreshed Setup core from a verified disposable TEMP copy, matching production Setup's self-relocation boundary so the installed Setup executable is not held open while the protected package replaces it.

The field helper itself is developer test tooling and is launched from Windows PowerShell. Any console belonging to the helper is therefore **not** evidence of a product console flash. The no-console requirement applies to normal Quick Repair, updater and Setup operation outside this helper path. The helper waits only for the direct elevated Setup child with a bounded timeout; the resident Quick Repair process relaunched by Setup is not treated as part of that wait.

A small phase6.4-field-result.json file is written beside the helper. Its path is converted to an absolute path before UAC so the elevated child cannot redirect the result by starting in a different Windows working directory. It contains only typed booleans (including whether a same-version bridge refresh occurred), the preview version/code, the current acceptance stage and a curated error message when applicable. Unexpected PowerShell exception text is never copied into that file. If the administrator-approved child process fails, the unelevated parent preserves the child's privacy-safe protected-stage name instead of replacing it with a generic UAC-stage result. It does not record the configured peer, Windows SID, usernames, IP addresses, device names or local paths.

## UAC cancellation test

Cancelling the Windows approval prompt is a valid test. Before staging anything, the helper requires the complete published protected baseline to be present. After cancellation it verifies every expected protected baseline file is still present with the same SHA-256, then leaves only the verified user-level bridge plus its protected-update marker staged. If the baseline is incomplete or any protected hash changes, the field run fails closed.

Run the same command again and approve the prompt. The helper recognises the already-staged bridge without replaying the original baseline -> RC1 transition. Before protected Setup continues, it reapplies the currently verified user-level preview package with the candidate updater so every same-version bridge byte (including the installed Setup host) matches the exact field pack. Hosted acceptance deliberately corrupts the staged Setup host and proves the retry refreshes it before entering the protected boundary. It also exercises the cancel/stage/retry state transition without claiming to reproduce the physical Windows UAC screen.

Same-version retries remain supported for an interrupted field attempt, but new installable preview payloads now receive a new version code. If a same-version field retry is ever required, a same-version field refresh also preserves the prior Guardian known-good record as its predecessor and retires the active record. Guardian itself remains strict: same version code plus different trusted bytes is still treated as suspicious during normal product operation. After the exact field candidate is installed, Guardian establishes a fresh known-good baseline only after its own integrity check passes.

For an already-completed exact field install, the developer helper can perform only this reconciliation without replaying Setup:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\field-preview.ps1 -OutputDirectory . -ReconcileFieldBaselineOnly
```

This mode refuses an unfinished protected marker or restart acknowledgement, verifies every installed candidate file against the exact protected package, requires Auto Repair off and Quick Repair exited, and never requests elevation.

## Passing first field upgrade

The first pass is complete only when:

- the same-account UAC approval succeeds;
- the protected marker is removed by protected completion;
- the installed version is exactly 3.0.0-rc.1 / 30001001;
- Quick Repair reopens normally;
- the restart acknowledgement is cleared by that reopened candidate;
- there are no PowerShell/console flashes from normal product operation;
- the existing target and startup preference are preserved;
- Tailscale remains signed in and other VPN/network settings are untouched;
- Auto Repair remains off until the initial installed state is checked.

## Follow-up physical acceptance

After the first upgrade passes, test UAC cancel/retry, normal close-to-tray and tray Exit, reboot/logon, sleep/resume, Wi-Fi transitions, VPN coexistence, authenticated local-backend recovery, and finally guarded Auto Repair behavior.

Real reboot/logon and sleep/resume may be **deferred** when disrupting the field machine is impractical. A hosted disposable-Windows simulation can validate startup registration, the exact `--start-in-tray` packaged launch, no console/script-host child, and the delayed logon trigger without restarting the user's PC. That simulation is supporting evidence only and must not be recorded as a physical reboot or resume pass.

VPN coexistence is **vendor-neutral**. Proton VPN may be used as one real-machine representative, but it is not a product dependency or special case. When practical, exercise representative transitions from more than one family: a WireGuard/Wintun-style client, an OpenVPN/TAP/TUN-style client, and a corporate/full-tunnel client. Split-tunnel/full-tunnel and kill-switch transitions are useful additional cases when the installed VPN supports them. Do not install or configure unrelated third-party VPN software merely to satisfy this field check.

A VPN transition may cause Quick Repair to settle and perform a delayed **local** recheck. It must not, by itself, authorise a repair. Passing coexistence means Quick Repair does not stop/restart another VPN service or process, change its adapter, route or DNS configuration, disable a kill switch, or perform a broad Windows network reset. An unrecognised VPN is still safe because VPN detection is optional read-only context and is not part of Auto Repair policy.

Do not interpret remote peer unavailability as a repair trigger. Optional diagnostics remain read-only and must not influence core health or automatic recovery.


## RC1 delivery note

Once RC1 is installed, future release-candidate updates use **Early-access updates -> Check for updates -> Update now** inside Quick Repair. The field helper remains a one-time developer bridge for trusted older baselines and is not the normal update mechanism.
