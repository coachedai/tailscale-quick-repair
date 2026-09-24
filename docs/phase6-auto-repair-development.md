# Phase 6: Auto Repair 2.0

## Current candidate

Development has advanced to **3.0.0-phase6.4.0-preview**, code **30000740**. It remains **unpublished** (`publish:false`) on the preview channel. The live public release remains **3.0.0-phase5.2.1**.

The source immediately before this version-only candidate was verified at **1b897e6da2cf69042274d52feed1a22ded064764** in workflow **35930299174**. Both Windows jobs completed successfully. The retained reports contain **1,107 passing assertions across 19 aggregate suites**: 836 native/package/Windows assertions, 135 genuine 5.2.1 upgrade assertions, 67 interrupted-Setup/integration assertions and 69 protected-handoff assertions. Nested child reports are evidence only and are not counted again.

The preview version bump does not change repair permissions, network behavior or the protected backend. Its purpose is to produce one clearly named installable candidate for final field acceptance.

## What Phase 6 now includes

Automatic repair is local-only. Policy inputs are limited to the Tailscale service, service startup mode, the local Tailscale client and local backend state. Peer reachability, latency, routes, diagnostics and arbitrary error text cannot authorise automatic recovery.

Intentional disconnect, sign-in, device approval and another-user states require attention and are preserved across later service loss. A disabled service is left disabled. Missing or uncertain installation state cannot mutate Windows. Automatic repair does not run `tailscale up`, reset adapters, perform broad Windows network resets or change unrelated VPN settings.

Candidate faults require repeated comparable observations before action. Retry reservations use increasing cooldowns and stop after the incident retry limit. Recovery is reported only after explicit healthy local evidence; starting a task or completing a service action is not labelled as recovery.

The protected monitor runs through a highest-interactive scheduled task registered for the same Windows user. Ordinary app use can request that task but cannot rewrite protected files or task definitions. Manual and event-driven launch failures now show a truthful local-check failure state instead of leaving the interface on a false “checking” message.

Background checks use an indefinite five-minute fallback plus delayed local service/network/logon triggers. Missed time occurrences are **not** replayed later (`StartWhenAvailable=false`), preventing duplicate catch-up runs. Resume/network/logon have their own delayed local triggers. The real five-minute recurrence is checked with both UTC and an independent monotonic clock plus Task Scheduler instance attribution.

History is bounded and typed: at most 40 records, 32 KiB and 30 days. Background reconciliation covers current/previous worker snapshots rather than promising a lossless unlimited audit log. Notifications remain opt-in, rate-limited and are not replayed from historical recoveries when the UI starts cold.

## Upgrade and recovery

Existing 5.2.1 installs use a staged protected handoff. The released updater first applies only user-level files, including the refreshed Setup host and a short-lived version marker. After restart, the refreshed app requests normal Windows administrator approval and launches only the installed Setup host in fixed upgrade mode. The old updater never writes the protected backend or protected task files.

Setup validates the marker and the initiating Windows SID. Approval by a different Windows account is intentionally refused rather than migrating per-user state into the wrong profile. The current preview therefore requires the administrator approval to use the **same Windows account that launched Quick Repair**.

Protected Setup keeps a machine-protected file transaction before replacing payload files. A killed Setup can restore the previous published file hashes; recovery itself can be killed and resumed. After every new file is verified, the transaction is durably marked committed before old backups are removed, so interrupted cleanup does not roll a valid new payload backwards. Recovery journals are tied to the initiating SID.

Post-file Windows integration is replay-safe: target configuration, repair task, automatic monitor task, startup registration, Start-menu shortcut, restart acknowledgement and final marker removal converge to the same candidate state after an early or late Setup kill. Installed success is recorded only after the matching restarted app clears the persistent restart acknowledgement.

## Verified boundaries

Current native acceptance covers the genuine published 5.2.1 package, exact package hashes, protected/user-level package separation, local service start, disabled-service preservation, unauthenticated intent hold, the real local Tailscale client reopen boundary, ordinary-user protected file/task permissions, task migration, protected handoff, restart acknowledgement, killed payload application/recovery, replay-safe Windows integration and exact-artifact release-pipeline wiring.

Earlier failed runs remain preserved in the pull-request history. In particular, Task Scheduler catch-up behavior was traced to Event 114 and fixed by disabling missed-run replay; the timing gate itself was not widened.

## Final Phase 6 acceptance still required

The remaining work is intentionally narrow:

- physical desktop/UAC field acceptance of approve, cancel, retry and relaunch behavior;
- actual authenticated local-backend recovery and sustained-backend restart behavior without using a real user tailnet in automated CI;
- broader suspend/resume and VPN/network lifecycle acceptance on a real desktop;
- whole-PC/storage-interruption acceptance beyond the process-kill transaction tests;
- decide whether separate-administrator credential support is added or remains an explicit same-account limitation;
- final release-candidate review before Phase 6 is closed.

These are field/real-environment gates, not permission to weaken the existing Windows, package, privacy or recovery tests.

## Roadmap retained

After Phase 6: **Phase 7 Startup / Passive Health**, **Phase 8 Update Guardian 2.0**, **Phase 9 UI / Product Polish**, **Phase 10 Failure Lab / 3.0 Acceptance**, then **Phase 11 3.0 Stable**. Advancing the preview version does not mark those phases complete.
