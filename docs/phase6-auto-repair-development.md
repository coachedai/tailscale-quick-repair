# Phase 6: Auto Repair 2.0

## Current candidate

**3.0.0-rc.1 / 30001001** is now published only as the opt-in GitHub **prerelease / Early-access** release. Stable remains **3.0.0-phase5.2.1** on `main` and `updates/latest.json`.

The frozen RC1 release target is **2555bf4af30845d2c722964e289cfdfe15a412bf**. Workflow **36186476031** passed the full native Windows verification, genuine released-5.2.1 upgrade, interrupted-Setup recovery and protected-handoff gates before the publisher created the prerelease and dedicated Preview manifest. Publication then disarmed itself.

Post-publication compatibility commit **d16c8107aa1cf2403e52fe66a6c82b221b2918d5** passed workflow **36189240040**. Its developer field helper exact-allows the physically accepted **3.0.0-phase6.4.0-preview / 30000740** and **3.0.0-phase6.4.3-preview / 30000743** identities only, and still requires a Guardian known-good record matching the installed integrity manifest. The accepted 6.4.0 path now has explicit cancel/retry/protected-completion acceptance.

CI also pins the already-published RC1 package assets by tag, release target, size and SHA-256 before privacy-scanning and rerunning field acceptance. This guards the field pack against same-version rebuilt bytes.
## What Phase 6 now includes

Automatic repair is local-only. Policy inputs are limited to the Tailscale service, service startup mode, the local Tailscale client and local backend state. Peer reachability, latency, routes, diagnostics and arbitrary error text cannot authorise automatic recovery.

Intentional disconnect, sign-in, device approval and another-user states require attention and are preserved across later service loss. A disabled service is left disabled. Missing or uncertain installation state cannot mutate Windows. Automatic repair does not run `tailscale up`, reset adapters, alter DNS/routes, perform broad Windows network resets or change unrelated VPN settings. VPN brand or protocol is not a policy input. The separate manual adapter-recovery boundary is fail-closed to the exact Tailscale tunnel interface and passes the selected adapter object directly to Windows; friendly-name matching cannot widen that scope.

Candidate faults require repeated comparable observations before action. Retry reservations use increasing cooldowns and stop after the incident retry limit. Recovery is reported only after explicit healthy local evidence; starting a task or completing a service action is not labelled as recovery.

The protected monitor runs through a highest-interactive scheduled task registered for the same Windows user. Ordinary app use can request that task but cannot rewrite protected files or task definitions. Manual and event-driven launch failures now show a truthful local-check failure state instead of leaving the interface on a false “checking” message.

Background checks use an indefinite five-minute fallback plus delayed local service/network/logon triggers. Missed time occurrences are **not** replayed later (`StartWhenAvailable=false`), preventing duplicate catch-up runs. Resume/network/logon have their own delayed local triggers. The real five-minute recurrence is checked with both UTC and an independent monotonic clock plus Task Scheduler instance attribution.

History is bounded and typed: at most 40 records, 32 KiB and 30 days. Background reconciliation covers current/previous worker snapshots rather than promising a lossless unlimited audit log. Notifications remain opt-in, rate-limited and are not replayed from historical recoveries when the UI starts cold.

## Upgrade and recovery

Existing 5.2.1 installs use a staged protected handoff. The released updater first applies only user-level files, including the refreshed Setup host and a short-lived version marker. After restart, the refreshed app requests normal Windows administrator approval and launches only the installed Setup host in fixed upgrade mode. The old updater never writes the protected backend or protected task files.

Setup validates the marker and the initiating Windows SID. Approval by a different Windows account is intentionally refused rather than migrating per-user state into the wrong profile. RC1 therefore requires administrator approval to use the **same Windows account that launched Quick Repair**.

Protected Setup keeps a machine-protected file transaction before replacing payload files. A killed Setup can restore the previous published file hashes; recovery itself can be killed and resumed. After every new file is verified, the transaction is durably marked committed before old backups are removed, so interrupted cleanup does not roll a valid new payload backwards. Recovery journals are tied to the initiating SID.

Post-file Windows integration is replay-safe: target configuration, repair task, automatic monitor task, startup registration, Start-menu shortcut, restart acknowledgement and final marker removal converge to the same candidate state after an early or late Setup kill. Installed success is recorded only after the matching restarted app clears the persistent restart acknowledgement.

## Verified boundaries

Current native acceptance covers the genuine published 5.2.1 package, exact package hashes, protected/user-level package separation, local service start, disabled-service preservation, unauthenticated intent hold, the real local Tailscale client reopen boundary, ordinary-user protected file/task permissions, task migration, protected handoff, restart acknowledgement, killed payload application/recovery, replay-safe Windows integration and exact-artifact release-pipeline wiring.

Earlier failed runs remain preserved in the pull-request history. In particular, Task Scheduler catch-up behavior was traced to Event 114 and fixed by disabling missed-run replay; the timing gate itself was not widened.

## Hosted startup/logon simulation

A disposable Windows runner now simulates the software-side reboot/logon path without rebooting a user's PC. It invokes the actual Setup startup-registration core, launches the exact packaged GUI with `--start-in-tray`, samples for visible top-level windows, verifies no console/script-host child process appears, and inspects the protected delayed same-user logon trigger. The fixture is removed afterward.

This is supporting evidence only. It does **not** certify a real Windows reboot, real sign-out/sign-in, real sleep/resume, firmware/driver resume behavior, or interactions with unrelated desktop applications. Those physical lifecycle gates remain deferred until a suitable real-machine test window is available.

## Final Phase 6 acceptance still required

The remaining work is intentionally narrow:

- physical desktop/UAC field acceptance of approve, cancel, retry and relaunch behavior;
- actual authenticated local-backend recovery and sustained-backend restart behavior without using a real user tailnet in automated CI;
- broader suspend/resume and vendor-neutral VPN/network lifecycle acceptance on a real desktop; real reboot/logon and sleep/resume remain deferred physical gates even when hosted startup/logon simulation passes;
- whole-PC/storage-interruption acceptance beyond the process-kill transaction tests;
- decide whether separate-administrator credential support is added or remains an explicit same-account limitation;
- final release-candidate review before Phase 6 is closed.

These are field/real-environment gates, not permission to weaken the existing Windows, package, privacy or recovery tests.

## Roadmap retained

After Phase 6: **Phase 7 Startup / Passive Health**, **Phase 8 Update Guardian 2.0**, **Phase 9 UI / Product Polish**, **Phase 10 Failure Lab / 3.0 Acceptance**, then **Phase 11 3.0 Stable**. Advancing the preview version does not mark those phases complete.


### Quiet startup checkpoint

RC1 hardens `--start-in-tray` so the WPF main window is not passed to `Application.Run(window)` and therefore does not need to appear before being hidden. Hosted native acceptance launches the exact packaged executable, samples visible top-level windows, and requires no console/script-host child. Real reboot/logon remains a deferred physical gate.


### Guarded Preview RC publication

The development workflow has a separate Early-access publication gate controlled by `release/preview-publish.json`. It is disarmed by default and accepts only versions matching `3.0.0-rc.N`. When deliberately armed, publication remains blocked until both the full development verification job and released-upgrade/recovery job pass for the exact same commit.

The publisher reuses the exact validated package artifact, rechecks SHA-256 sidecars and privacy, creates a GitHub **prerelease**, then disarms its own publication intent before making `preview/updates/preview.json` live. Both branch pushes are non-force. If the development branch moves before publication/disarm, the job refuses. The Preview job has no code path to `main` or `updates/latest.json`.

This makes the release-candidate loop: trusted 5.2.1, 6.4.0 or 6.4.3 field baselines may use the one-time developer bridge to RC1; once RC1 is installed, enable **Early-access updates** and install later 3.0 RCs through the normal in-app updater.
