# Phase 6.1 development: protected local-only worker integration

## Delivered into development packages

The existing protected monitor entry now invokes AutoRepairWorker directly. The actual packaged Operations library contains the policy, bounded local-status reader, worker and Windows OS boundary. The full Setup package places the same library bytes in its app and protected program directories. The ordinary package does not deliver the protected monitor, and this development version requires native Setup. The published update manifest is unchanged.

The worker no longer dispatches the normal manual/peer-repair task. Its action set is limited to reopening the local Tailscale client, starting an eligible stopped Tailscale service, or an individually authorized service stop/start for a sustained Starting/NoState backend. It never tests the peer. Unknown, disabled-service, authentication and intentional-disconnect states are not repair permissions.

The real operation coordinator is acquired before health observation. A backward-compatible IsCurrent check verifies lease identity before each action and result write. Opt-in, environment continuity and fresh intent are checked again by a callback at the production action boundary. A stopped service is not blindly restarted after an opt-out/environment cancellation. Attempted and completed action counts remain separate; recoveryConfirmed requires a completed action plus a later explicit local Running observation. Generic exceptions and raw command output are not persisted.

The production service-stop implementation sends STOP directly to the service control manager without cascading to dependent services. Installed CLI/client paths are restricted to the fixed Program Files installation and matched to service registration; this is not Authenticode/provenance verification. No broad Windows networking command, adapter reset, other-VPN change, elevation request or remote target is part of the automatic worker.

The existing Automation UI uses strict settings reads and atomic preference writes. A failed disable write cannot visually promise Off. Its check action verifies the auto-monitor task's enabled state, current-user identity, interactive/highest principal, single fixed hidden-launcher action and working directory before dispatch. It does not fall back to ordinary repair or request elevation. New-schema notification observations require the typed result and actual recovery confirmation. The layout, manual check, diagnostics, progress, saved History and notification preference are not redesigned in this increment.

## Native verification

Run **35517294854**, commit **e2c378c2201c27de251bf528e8cc93de981f6360**, completed successfully on native Windows PowerShell 5.1 / WPF / .NET Framework. The source and package privacy scans, exact repository/remote checks, native builds and HTTPS checks, both package builds, all runtime suites and the final no-publication/source-unchanged check passed.

The evidence archive **10607675407** was downloaded and independently checked against SHA-256 **0b3c30292c6ec442dda860a3149166ecc2dd5ba6b6d2f905a7e678eb6839955c**. Its source commit and every archived source file matched the reviewed local files. Inspection of all suite reports found **588 passing checks across 12 suites**:

- 319 existing final-package regressions.
- 79 policy/state checks.
- 104 bounded local-status checks.
- 86 new packaged worker/UI integration assertions.

The new suite runs in a fresh native process and asserts the loaded assembly location equals the protected package DLL. It must not accidentally test a previously loaded ordinary-package assembly. It verifies the matching Setup app/program DLL bytes, exact protected monitor source, protected delivery requirement, completed-action/outcome distinction, late opt-out/intent/environment changes, cancellation between stop/start, existing owners, damaged/locked/oversized/missing records, legacy cooldown migration and no raw-error persistence.

Native child processes execute the actual delivered PowerShell entry with only its OS machine constructor substituted. A separate real child holds the actual operation lease at the final harmless action boundary. Another process is refused; killing the owner preserves the reservation and produces real coordinator recovery evidence. The final packaged WPF check action and settings functions are exercised with a native COM-shaped scheduler fixture, including wrong command, principal and run-level rejection.

The development package artifact was also downloaded and checked against SHA-256 **b6382d9b85186074055ef2864d69040d50142a1fc69087fb3b425e1557ce97ec**. Inspection validated inner manifest paths, sizes, hashes and exact file sets using the Windows ZIP path normalization. The two final UIs match, the Setup app/protected libraries match, and the delivered manual repair backend is byte-for-byte unchanged from the published 5.2.1 Setup package. The longstanding build transform that enables MagicDNS still explains its difference from the raw backend source; this increment did not alter it. Ordinary integrity coverage remains five app files; Setup coverage remains six. These are coverage profiles, not a signed trust root over all protected components.

## Retained first integration failure

Run **35517007277** passed both package builds and all existing 319 assertions, then passed 74 new worker assertions before failing the first UI task-routing assertion. The scheduler fixture used a dynamically scoped variable named scheduler, which collided with the product function's local scheduler variable. The fixture now uses an explicit script-scoped unique binding. The product implementation and dispatch assertion were not relaxed. The failed run and its evidence artifact remain retained.

The documentation follow-up must pass the same workflow at its own exact head; a previous code-run pass is not automatically final-head acceptance.

## Scope limits and next checkpoint

The actual packaged worker, coordinator, record writers, PowerShell entry and WPF functions execute natively. Service/client mutations, environment signals and scheduler dispatch are harmless fixtures. The production Windows boundary compiles but these tests do not certify actual service control, UAC/alternate-admin Setup, Windows logon, task trigger firing, physical tray/DPI behavior or whole-PC power loss. An operation lease and fresh checks do not create a security boundary against another privileged local process.

Next work is event/five-minute-fallback lifecycle verification and bounded background History/outcome reconciliation, followed by actual Windows/Setup failure acceptance and publication gates. Current development metadata stays publish:false. No user installation, marker deletion or deliberate outage is needed for this checkpoint. Full Phase 6 and the remaining master roadmap stay open.

Primary references used for the OS boundaries: https://learn.microsoft.com/en-us/windows/win32/services/stopping-a-service and https://tailscale.com/kb/1080/cli .
