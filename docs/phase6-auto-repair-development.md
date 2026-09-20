# Phase 6: Auto Repair 2.0 development

## Delivery status

This branch starts Phase 6 from the published 3.0.0-phase5.2.1 baseline. It is not a new release and does not complete Phase 6. The first implementation contains the isolated native AutoRepairPolicy decision/state component and AutoRepairLocalStatus read-only collector, each with Windows tests. Neither is yet compiled into the delivered Operations library or invoked by Auto-Repair-Monitor.ps1. Existing protected workers, tasks, UI, version files, manifests and live update metadata remain unchanged. Development stays publish:false with read-only workflow repository permissions.

The development workflow rebuilds both existing delivery paths and preserves every existing packaged runtime suite. Those baseline package passes are regression evidence, not evidence that the new monitor is installed. The two additional suites compile the new components on native .NET Framework and exercise native file/process behavior separately. No generated baseline package is a Phase 6 installer.

## Findings requiring actual integration work

Review of the baseline identified four important gaps:

- The monitor casts settings.enabled to bool. A nonempty string can be mistaken for opt-in. The UI's old settings reader can also remove malformed settings. Replace those behaviors with strict typed settings and preserve invalid evidence.
- A missing BackendState can become Running, and Unknown can be called healthy. Missing, timed-out or malformed local status must instead remain unconfirmed.
- The legacy monitor starts the general on-demand repair task. That task can subsequently inspect a remote peer and perform peer-path recovery. The new automatic path must be truly local-only; do not simply relabel this existing dispatch as local-only.
- The current status named repaired means a task was started, not that recovery succeeded. Preserve the existing notification correction, then integrate separately evidenced actions and outcomes.

These are reviewed source findings, not proof that a fault occurred on a user's computer. The manual Tailscale-only repair engine remains unchanged by this development increment.

## Implemented policy contract

Only fixed local service, startup, client and backend observations are inputs. No peer status, address, route, latency, raw error or diagnostic result can authorize an automatic action. A decision is not an action, and a persisted reservation is not a success report.

Opt-out and busy-operation observations do not consume the budget. Intentional disconnection, sign-in, approval and other-user backend states require attention rather than automated recovery. A recorded intentional/authentication hold survives later service loss; only an explicit later Running backend observation releases it. Missing installation or a disabled service requires attention. Unknown evidence is neither healthy nor sufficient to reopen a client.

Candidate local faults need two comparable observations separated by at least 30 seconds for service/client faults or 60 seconds for a Starting/NoState backend. A gap over ten minutes or intervening unconfirmed evidence breaks comparison continuity. These are conservative product policies, not guarantees about the underlying network. This component does not create a timer or extra probe.

Attempts reserve escalating 15-, 30- and 60-minute backoff. Three unresolved reservations stop automatic retries pending attention or sustained observed health. App restarts and preference toggles do not clear the budget. Three spaced explicit healthy samples over at least ten minutes can establish a new incident budget; rapid event bursts cannot manufacture that recovery. Clock rollback fails closed. A killed process after a committed reservation cannot make the next invocation immediately dispatch again.

The policy store is capped at 16 KiB with one predecessor. Its fixed field names and types exclude arbitrary messages and identifiers. Strict settings allow enabled and an optional valid round-trip UTC updatedUtc only. Escaped property aliases and duplicate keys are rejected. Damaged, locked, oversized or inconsistent records are preserved. A missing primary with a surviving predecessor, including an unexpected directory at that path, cannot silently create a clean retry budget. Writes flush a unique scratch file before atomic replacement. The persistent lock file is never deleted to acquire ownership.

This is bounded local-state protection, not a trust root against a malicious local administrator. It cannot infer a user-intent transition that was never observed. It does not prove whole-PC power-loss recovery, protected dispatch correlation or real service/task integration. Passing a busy flag to an isolated policy is not a substitute for acquiring the actual operation lease before protected actions.

## Implemented local observation component

AutoRepairLocalStatus accepts an absolute executable path and a bounded timeout. It starts only the fixed read-only command status --json --peers=false, without a shell, target argument or fallback peer probe. Installed CLI discovery and provenance remain integration requirements; a caller-supplied executable path is not independently certified by this component.

Stdout and stderr are drained concurrently in bounded byte chunks, not unbounded ReadLine buffers. Retention is capped at 64 KiB, including newline-free output. Timed-out, truncated, malformed, nonzero-exit or otherwise incomplete results cannot supply a Running backend. The parser rejects duplicate or escaped top-level property aliases. Unrecognized BackendState values remain Unknown. No raw stdout, stderr, peer data, host names, paths or authentication URLs are returned in the observation or written to disk.

The native process uses CreateNoWindow and fixed arguments. Timeout cleanup targets only the exact child created by that call. The collector has no service-changing, task-dispatch, repair, notification or peer-polling implementation. Tests cover native hidden-window behavior and owned-process cleanup with synthetic executables; they do not claim acceptance of a real installed Tailscale service or every Windows process-lifecycle failure.

## Verified development evidence

Run **35510136140**, source commit **4154ce2870238ce282e1e1e4e870d520382e7dec**, completed successfully on Windows PowerShell 5.1 / WPF / .NET Framework. Both baseline delivery packages built, the unchanged HTTPS gate passed, and source/package privacy, repository isolation and no-publication checks passed.

The downloaded evidence archive was verified against its GitHub artifact digest: 30b90eaf45fdef1f4ed23112b4bcfba97d0b651243b3848650d124d0274162ad. Its source-commit record and archived component/test files matched the tested commit. Eleven suite reports contain **502 passing checks**:

- **319 existing packaged checks** across Guardian/ownership, backend reporting, History, update routing, connection quality, notifications, diagnostics/scrolling, repeated-check progress and support export.
- **79 new policy/state checks**, including real concurrent Windows child processes reserving one slot, persistence after killing a disposable reservation owner, corrupt/locked/missing state preservation and strict settings validation.
- **104 new local-status checks**, including native synthetic CLI processes, fixed local-only arguments, hidden console verification, timeout, large unterminated stdout/stderr, malformed/unknown JSON and exclusion of raw identifiers.

This is component-level native acceptance plus regression coverage of the existing packages. It is not integrated monitor, protected execution, Setup/UAC, user-desktop or whole-PC power-loss acceptance. The documentation-only follow-up must pass the same workflow before this branch is considered green at its final head.

## Retained development failures

The first workflow bootstrap run preceded the new test file and correctly failed rather than skipping the missing gate. Run **35509216334** passed the existing 319 packaged checks, then passed 66 new policy assertions before the extra-settings-field assertion rejected the implementation. That assertion was retained; the implementation was corrected to reject unknown keys, wrong timestamp types and escaped duplicate aliases.

Run **35509483290** stopped at the unchanged native updater HTTPS self-test, exit 21, before the new policy suite. Its failed logs and source artifact remain retained. Later successful runs passed the same gate without bypassing TLS verification.

Run **35509761696** passed the existing packaged checks and all 77 policy assertions then failed during fixture cleanup because Add-Type -Path kept the compiled test DLL mapped. The tests now load the same native-compiled assembly bytes in memory; the cleanup requirement remains. Two predecessor-directory assertions were also added, giving the final 79 policy checks. No product acceptance assertion was removed or weakened to obtain the passing result.

## Required before any Phase 6 release

1. **Integrate bounded local observation.** Wire the verified collector into the actual monitor using validated installed CLI discovery. Preserve strict unknown/intent handling and no raw output persistence. Test the final packaged caller, including missing or unsupported CLI behavior. Do not require remote reachability.
2. **Local-only protected execution.** Integrate the policy with the actual shared operation coordinator. Recheck enabled state and fresh intentional/authentication state under the acquired lease immediately before mutation. Avoid a check-then-dispatch race with manual repair, update or Setup. Record a request distinctly from accepted ownership, actions and observed outcome. Do not invoke the peer-repair path. Preserve manual repair decisions, unrelated VPN software, adapters and network settings. No broad Windows resets.
3. **Events and five-minute fallback.** Implement and verify cheap event-triggered checks alongside the fallback, with settling, duplicate suppression and cooldown after resume/network/VPN changes. Do not add busy remote polling. Test foreground, tray and fully exited UI behavior. Stop when human action is required rather than hammering the task scheduler.
4. **Accurate local history and optional notifications.** Record bounded typed background events without identifiers. Distinguish recovery requested, action performed, outcome observed and unconfirmed/failed recovery. Preserve existing opt-in, quiet-state and rate limits; do not infer recovery from task launch. Preserve raw-state evidence on read/write failures.
5. **Native UI and installer integration.** Keep the existing compact Automation area, correct off/waiting/cooldown/attention presentation, settings preservation, and no console flashes. Ordinary updates must not silently deliver protected changes. A protected release requires matching native Setup, legitimate elevation, protected file/version verification and existing package parity/integrity gates.
6. **Integrated failure acceptance.** Exercise the final packaged monitor and actual event/UI dispatch, not only these isolated components. Use disposable Windows processes/tasks/fixtures for overlapping automatic/manual work, task launch failures, killed owners, persisted reservations, user disabling during a pending attempt, changed intent before mutation, locked/corrupt files, task time limits and child cleanup. Record precisely which OS boundaries are fixtures. Real elevated Setup/logon/alternate-admin and whole-PC interruption gates remain distinct; do not claim them from harmless dispatch probes.
7. **Final release gates.** Preserve source and exact-package privacy scans, repository/remote identity checks, all earlier regression suites, final artifact digests and publication validation. Keep the existing installation unchanged until those gates pass. Do not publish this component-only branch as a finished Auto Repair release.

## Roadmap retained

Phase 6 remains Auto Repair 2.0. Then: Phase 7 Startup/Passive Health, Phase 8 Update Guardian 2.0, Phase 9 UI/Product Polish, Phase 10 Failure Lab/3.0 Acceptance, and Phase 11 3.0 Stable. Earlier outstanding protected run correlation/provenance, background coverage, longer-term connection intelligence, interrupted Setup/update recovery, alternate-admin identity and restart acknowledgement remain explicitly open. Existing Phase 5 export desktop clipboard/picker acceptance is separate from the screenshots confirming installation, integrity, connection checks and diagnostics.
