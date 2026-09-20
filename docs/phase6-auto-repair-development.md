# Phase 6: Auto Repair 2.0 development

## Delivery status

This branch starts Phase 6 from the published 3.0.0-phase5.2.1 baseline. It is not a new release and does not complete Phase 6. The first implementation is the isolated native AutoRepairPolicy decision/state component plus Windows regression tests. It is not yet compiled into the delivered Operations library or invoked by Auto-Repair-Monitor.ps1. Existing protected workers, tasks, UI, manifests and live update metadata remain unchanged. Development stays publish:false with read-only repository permissions.

The development workflow rebuilds both existing delivery paths and preserves every existing packaged runtime suite. Those baseline package passes are regression evidence, not evidence that the new monitor is installed. The additional policy suite compiles the new component on native .NET Framework and exercises native file/process behavior separately. No generated baseline package is a Phase 6 installer.

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

The policy store is capped at 16 KiB with one predecessor. Its fixed field names and types exclude arbitrary messages and identifiers. Strict settings allow enabled and an optional valid round-trip UTC updatedUtc only. Escaped property aliases and duplicate keys are rejected. Damaged, locked, oversized or inconsistent records are preserved. A missing primary with a surviving predecessor cannot silently create a clean retry budget. Writes flush a unique scratch file before atomic replacement. The persistent lock file is never deleted to acquire ownership.

This is bounded local-state protection, not a trust root against a malicious local administrator. It cannot infer a user-intent transition that was never observed. It does not prove whole-PC power-loss recovery, protected dispatch correlation or real service/task integration.

## Development evidence and failures

Run 35509216334 passed the existing 319 packaged checks, then passed 66 new policy assertions before rejecting the implementation at the extra-settings-field test. The test was retained. The implementation was corrected to reject unknown keys, wrong timestamp types and escaped duplicate aliases. The first workflow bootstrap run preceded the new test file and correctly failed rather than skipping that missing gate.

Run 35509483290 stopped at the unchanged native updater HTTPS self-test, exit 21, before the new policy suite. Its failed logs and source artifact remain retained. A later green run must pass that same build gate; neither the assertion nor TLS verification is to be bypassed. Current acceptance is determined by the final exact-source run and retained JSON, not by this document predicting a pass.

## Required before any Phase 6 release

1. **Bounded local observation.** Replace the unbounded CLI call with a fixed, hidden, timeout/output-bounded local status request. Explicitly validate BackendState; keep raw output out of persistence. Real synthetic child processes must cover timeout, huge unterminated output, nonzero exit, invalid JSON, unsupported flags and unknown values. Do not require remote reachability.
2. **Local-only protected execution.** Integrate the policy with the actual shared operation coordinator. Recheck enabled state and fresh intentional/authentication state under the acquired lease immediately before mutation. Avoid a check-then-dispatch race with manual repair, update or Setup. Record a request distinctly from accepted ownership, actions and observed outcome. Do not invoke the peer-repair path. Preserve manual repair decisions, unrelated VPN software, adapters and network settings. No broad Windows resets.
3. **Events and five-minute fallback.** Preserve cheap event-triggered checks and the fallback, with settling, duplicate suppression and cooldown after resume/network/VPN changes. Do not add busy remote polling. Test foreground, tray and fully exited UI behavior. Stop when human action is required rather than hammering the task scheduler.
4. **Accurate local history and optional notifications.** Record bounded typed background events without identifiers. Distinguish recovery requested, action performed, outcome observed and unconfirmed/failed recovery. Preserve existing opt-in, quiet-state and rate limits; do not infer recovery from task launch. Preserve raw-state evidence on read/write failures.
5. **Native UI and installer integration.** Keep the existing compact Automation area, correct off/waiting/cooldown/attention presentation, settings preservation, and no console flashes. Ordinary updates must not silently deliver protected changes. A protected release requires matching native Setup, legitimate elevation, protected file/version verification and existing package parity/integrity gates.
6. **Integrated failure acceptance.** Exercise the final packaged monitor and actual event/UI dispatch, not only this pure policy module. Use disposable Windows processes/tasks/fixtures for overlapping automatic/manual work, task launch failures, killed owners, persisted reservations, user disabling during a pending attempt, changed intent before mutation, locked/corrupt files, task time limits and child cleanup. Record precisely which OS boundaries are fixtures. Real elevated Setup/logon/alternate-admin and whole-PC interruption gates remain distinct; do not claim them from harmless dispatch probes.
7. **Final release gates.** Preserve source and exact-package privacy scans, repository/remote identity checks, all earlier regression suites, final artifact digests and publication validation. Keep the existing installation unchanged until those gates pass. Do not publish this component-only branch as a finished Auto Repair release.

## Roadmap retained

Phase 6 remains Auto Repair 2.0. Then: Phase 7 Startup/Passive Health, Phase 8 Update Guardian 2.0, Phase 9 UI/Product Polish, Phase 10 Failure Lab/3.0 Acceptance, and Phase 11 3.0 Stable. Earlier outstanding protected run correlation/provenance, background coverage, longer-term connection intelligence, interrupted Setup/update recovery, alternate-admin identity and restart acknowledgement remain explicitly open. Existing Phase 5 export desktop clipboard/picker acceptance is separate from the screenshots confirming installation, integrity, connection checks and diagnostics.
