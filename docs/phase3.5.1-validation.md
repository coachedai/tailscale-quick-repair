# Phase 3.5.1: Local Health History and update-path verification

## Delivered behaviour

Activity gains a compact History toggle beside Copy. Session activity remains the default; History shows saved events in the same column, newest first, with an internal scroll area. Copy in History copies only the privacy-safe displayed history, not the separate diagnostic report.

The store accepts typed product event codes, timestamps, random event IDs and bounded numeric values only. It has no fields for peer addresses, device names, file paths, arbitrary exception text or raw logs. It makes no network requests. Current history is capped at 40 records and 32 KiB; records older than 30 days are excluded from the view and pruned on the next successful append. One bounded predecessor file is retained for write recovery. Identical consecutive events within a minute are coalesced, and repeated rendering of the same completed check is ignored.

This first delivery records events observed by the resident UI: completed check outcomes, performed repair actions, route changes, significant latency changes, integrity results, observed update results, target changes and network-environment invalidation. It does not poll the peer to manufacture history. It does not claim to capture every background event while the UI is fully exited; broader background recovery/Auto Repair history remains planned work.

A malformed or locked history file cannot overwrite the main repair result. Malformed data is preserved and the History view reports that it is unavailable; competing history access returns promptly rather than blocking the repair flow. Writes use a flushed scratch file and atomic replacement with one previous copy. This is bounded local-state protection, not proof of whole-update recovery from every power loss.

## Reporting and update fixes

- The backend maintained an internal RepairPerformed flag but omitted it from published state. The flag is now serialized, so the UI and history can distinguish performed repair actions from checks which made no changes. The actual repair decisions and networking commands are unchanged. History says "Repair actions performed", not that every attempted repair succeeded.
- The ordinary native updater previously ignored requiresSetup. It now reads that flag strictly and refuses to apply an ordinary package for a protected release. A direct Bootstrap invocation is not the migration route for this protected release; use the in-app Update now action or the release Setup installer.
- The packaged UI update route rejects a malformed protection flag without launching either helper. Both true and false routes are exercised using the actual final WPF Update now event and harmless native probe executables in a disposable runner.
- History is added only after all public/Setup UI transforms, before integrity hashes are generated. Both delivery profiles still have the same full UI. The new history code is included in the existing operation library rather than adding a separate visible process.

## Four versus six verified app files

Four is the ordinary-update manifest's app-file coverage; six is the protected Setup profile's coverage. A four-file Healthy result is valid for that manifest, but does not prove that protected workers were updated. In particular, the older 3.4.1 Setup-installed UI could route a protected release as an ordinary update, and the old standalone updater did not reject it. The user's screenshots are consistent with an ordinary overlay; they do not prove the complete installer path.

3.5.1 therefore deliberately requires Setup and publishes both Setup assets. This migration installs the protected backend reporting change and the matching shared library as well as the UI. Guardian's app-file count does not imply cryptographic coverage of every protected worker.

## Native evidence and publication gates

Development run 35464570211 passed all four suites on native Windows PowerShell 5.1 / WPF / .NET Framework:

- 38 package/Guardian/coordinator assertions, retaining the previous corruption, baseline and cross-process ownership gates.
- 24 history assertions covering typed privacy boundaries, retention, coalescing, corruption preservation, lock behaviour, actual packaged WPF History toggling, completed-result deduplication and route-change recording.
- 7 update-route assertions, including protected, ordinary and malformed-flag paths through the actual packaged UI action.
- 2 checks of the actual packaged backend state publisher for false and true repairPerformed.

Subsequent wording/source cleanup must pass the same suites before publication. The permanent release pipeline invokes all four suites through test-packaged-runtime.ps1 and retains four JSON evidence reports. Repository identity, privacy preflight, both package builds, exact assets, package scanning and SHA-256 publication checks remain mandatory.

The Guardian service/task probes are controlled fixtures. The update-route executables are harmless probes, not real UAC/install tests. The backend test invokes only its state publisher, never service or adapter repair. These are real native tests of their stated scopes, not a full Windows-logon, alternate-admin UAC or whole-PC crash acceptance claim.

## Field acceptance

Use Details > Maintenance > Check for updates > Update now. This release is protected, so normal Windows UAC approval is expected. Let Setup finish; do not manually delete any baseline or operation marker.

After relaunch: check System integrity twice, run one normal connection check, open Activity > History, then Exit from the tray and reopen to check the saved entries remain visible. Record whether the migration showed UAC and which integrity profile/file count is shown. Guardian returning to Ready to check on a new app session is intentional: integrity remains on demand.

Local History is the next roadmap increment, not a declaration that the entire Guardian/crash-recovery plan is finished. Background history coverage, stronger independent component provenance, full interrupted-Setup/update recovery and connection-baseline intelligence remain separate work.
