# Phase 6.2 development: event lifecycle and bounded background History

## Development delivery only

The current development version is **3.0.0-phase6.2.0-dev**, code **30000720**, with **publish:false** and **requiresSetup:true**. No release or live update-channel change is part of this checkpoint. The published 5.2.1 installation remains the supported field baseline. This increment extends the already integrated local-only automatic worker; it does not change the manual repair backend or broaden automatic repair permissions.

## Implemented behavior

The protected worker records a reservation, each specifically completed local action, and a confirmed or unconfirmed final outcome into the existing typed History. These records can be produced by the protected process while the UI is fully exited. Routine healthy observations are silent. Action names are never guessed from an aggregate count, a task launch or a generic success label.

Schema-3 worker results add a reservation UTC stamp and at most three allowlisted completed actions with their UTC stamps. The parser validates action counts, vocabulary and chronology. Previous development schema-2 records remain readable, but are not turned into invented exact-action events. Raw worker output, private exception text, addresses, device names, paths and authentication data do not enter the new History projection.

Stable event identities derived from a run/slot pair make repeated reconciliation idempotent. New typed codes remain inside the existing five-field History format and the shared 40-event, 32 KiB and 30-day limits. Existing coalescing behavior is retained. Reconciliation does not resurrect older events already evicted by newer retained activity. Corrupt History and predecessor files are preserved, and a missing primary with a surviving predecessor is not silently accepted as a new empty store.

Replay is bounded to the current and previous worker snapshots. It is deliberately not an unlimited outbox or lossless audit service: a prolonged locked/corrupt History can outlast the available snapshots. History is secondary and cannot turn a real successful recovery into a connection failure. A UI read cannot classify live progress as an interrupted attempt. Only a verified new maintenance-operation owner can reconcile a former nonterminal snapshot as having no recorded completion.

The existing History column can reconcile and display recorded background actions on reopening. Reconciliation failure has a separate inline message from a failed History append, and that message clears when the evidence becomes readable. There is no new dashboard panel. New-schema notifications retain strict recovery confirmation, opt-in, deduplication, freshness and cold-start non-replay. Banners are not sent by the fully exited UI; saved History is the evidence available on return.

Resident UI event episodes use a monotonic clock: a 10-30-second settling interval, burst coalescing, a minimum thirty-second dispatch spacing retained across preference toggles, one sixty-second follow-up and a two-minute episode limit. Busy operations defer the check; long dispatcher pauses settle again; opt-out cancels the pending episode. A timer dispatches the verified local monitor route, never a peer probe or direct mutation. Scheduled worker calls also suppress fresh observation inside thirty seconds of the previous recorded check while retaining the real operation lease and all normal repair-policy checks.

Native Setup now constructs four triggers on the existing protected auto-monitor task: an indefinite five-minute fallback, current-user logon with settling, delayed System events for resume/Tailscale service state, and delayed NetworkProfile events. Event repetitions are bounded independently of the fallback. The task does not wake the PC, restart itself after failure or require network availability to check local health. Fully exited UI sessions do not gain process-exit auditing or a continuously resident monitor; event support/delivery varies, so unobserved client/backend failures still rely on the fallback.

## Native evidence

Code run **35520157515**, source **f61da7aa60f45bee6e3183bfe55591280ccc874e**, completed successfully on native Windows PowerShell 5.1 / WPF / .NET Framework. Both package builds, exact repository/remote checks, source/package privacy scans, the unchanged HTTPS gates and final no-publication/source-unchanged checks passed.

The downloaded evidence artifact **10608116367** matched SHA-256 **c48da63dcd055ae37ede83b627bcb5853a63393d6ad8043953c9f4db6c899b48**. Its source-commit marker and all **77 archived source files** matched the exact reviewed source. All **13 suite reports** were inspected and contained **679 passing checks**:

- 319 original packaged regressions.
- 79 policy/state checks.
- 104 bounded local-status checks.
- 86 integrated worker/UI checks.
- 91 new background lifecycle, History, event, notification and scheduler checks.

The new suite loads the actual protected package assembly and checks both its normalized location and file hash. Real child PowerShell processes execute the delivered monitor entry with only the OS machine constructor replaced by a harmless fixture. They demonstrate saved background action/outcome History without a resident UI. Tests cover cancellation between stop/start, locked/damaged History, preserved predecessors, schema compatibility, invalid action injection, replay idempotence, retention and refusal to classify live work as interrupted.

Actual final packaged WPF functions and the native DispatcherTimer execute event dispatch/cancellation and History presentation. The real notification adapter is exercised for historical cold-start suppression, fresh confirmed recovery, duplicate suppression, opt-out and invalid string-valued confirmation. Its notification sink is harmless; physical banner visibility and Windows quiet-mode behavior are separate acceptance.

The actual packaged Setup schedule-construction method is invoked on a real COM task definition. Tests inspect all four triggers, fixed delays and repetition settings. A uniquely named harmless task is registered in a dedicated test folder, its first fallback time trigger is observed firing with no Quick Repair UI, and only that test task/folder is removed. The fixture advances the initial start time so it fires promptly; it does not shorten the five-minute repetition interval. Other event triggers are disabled in that firing fixture, and no real suspend/network/service event is deliberately generated. This is native scheduler construction/registration/first-firing evidence, not proof of every OS event or a full repeated five-minute cycle.

The package artifact **10607254801** independently matched SHA-256 **70cbedbd6ab4b0ea72daf0a85ca080065753ce4328cc5e462ef3f8ffb15cbe8c**. Every inner-manifest path, size and SHA-256 and the exact package file sets were checked after Windows ZIP path normalization. The two final UIs match. Full Setup's app/program Operations DLL bytes match. The ordinary package contains no protected program files. The protected monitor matches source, and the manual backend remains byte-for-byte identical to the preceding verified 6.1 package. Integrity coverage remains five app files for ordinary delivery and six for Setup; neither count is a signed trust root over every protected component.

## Retained first-run failure

Run **35519771409** passed builds, the prior application regressions and integrated worker suite, then failed the second new background assertion while comparing an unnormalized file path to Assembly.Location. The failed evidence artifact **10607059609**, digest **ebaa3cbb3228f0ef03f4940e547721f6a487ceef1b5bddfed4570c56ae495f36**, was retained, downloaded and verified. The test now normalizes both full Windows paths and additionally verifies the loaded file's hash. No location assertion or prior regression was removed. The follow-up also added the separate History reconciliation feedback and new-schema notification cases described above.

A documentation-only follow-up must pass the same full workflow at its own exact head before final branch-head verification is recorded. A previous code-run pass is not automatically a final-head pass.

## Still open

Real service/client mutations and installed CLI discovery, production task identity/permissions, actual resume/network/service/logon events, sustained fallback recurrence, extended concurrency/interruption cases, physical tray/notification/DPI behavior, elevated Setup, alternate-admin identity, upgrade/uninstall/rollback and whole-PC power-loss acceptance remain separate gates. Reconciliation is bounded, not guaranteed lossless. The remaining Phase 6 requirements and the Phase 7-11 master roadmap are unchanged. No user installation, marker deletion or deliberate outage is required at this development checkpoint.

Primary API references: https://learn.microsoft.com/en-us/windows/win32/taskschd/eventtrigger ; https://learn.microsoft.com/en-us/windows/win32/taskschd/logontrigger ; https://learn.microsoft.com/en-us/windows/win32/taskschd/trigger-repetition ; https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-startwhenavailable .
