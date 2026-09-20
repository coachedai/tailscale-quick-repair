# Phase 6: Auto Repair 2.0 development

## Current checkpoint: protected worker integration, not a release

The development branch now builds **3.0.0-phase6.1.0-dev**, code **30000710**, with **publish:false** and **requiresSetup:true**. The policy, bounded local-status collector and local-only automatic worker are compiled into the actual packaged Operations library. The full Setup package delivers the protected monitor entry and matching protected library. The final UI routes requests to the existing protected auto-monitor task rather than starting a user-level monitor or invoking the general peer-repair task.

This supersedes the earlier component-only checkpoint. The live update channel remains **3.0.0-phase5.2.1**. This branch is not a supported user installation and is not ready for publication or a claim that Phase 6 is complete. Development workflow permissions remain read-only. The manual repair backend and the existing Setup host source are unchanged.

See **phase6.1-worker-validation.md** for exact integration evidence, its limits and the retained failed run. The existing 502-check foundation is preserved; the new packaged worker suite adds 86 assertions. The verified integration source passed **588 checks across 12 suites**.

## Safety contract retained

Only fixed local service, startup, client and backend observations are policy inputs. No peer availability, address, route, latency, diagnostic result or arbitrary error text can authorize automatic recovery. A decision/reservation is not an action; starting a task is not recovery. Missing or unconfirmed evidence is not Healthy.

Intentional disconnection, sign-in, approval and other-user states require attention. An observed intent/authentication hold survives later service loss until explicit Running evidence releases it. A disabled service is not re-enabled automatically. Missing installation or uncertain installed-path/service registration prevents mutation. The production boundary uses fixed installed paths, not a user-writable PATH fallback, and performs no self-elevation, login/up command, peer probe, adapter reset or broad Windows network reset. Other VPN and network settings remain outside the action set.

Candidate faults need two comparable observations separated by at least 30 seconds for service/client faults or 60 seconds for Starting/NoState. A gap over ten minutes or intervening missing evidence breaks continuity. Reservations use 15-, 30- and 60-minute backoff, with three unresolved attempts before attention is required. Three spaced healthy observations over ten minutes may reset the incident budget; rapid events and preference toggles do not. These timings are conservative product policy, not network guarantees.

The policy store is bounded to 16 KiB and one predecessor. Settings accept only a boolean enabled and optional round-trip UTC updatedUtc. Duplicate/escaped aliases, wrong types and unknown fields are rejected. Invalid, locked, oversized or inconsistent state is preserved, never reset to manufacture permission. The new settings writer uses a separate persistent lock and flushed atomic replacement. Migration preserves a legacy last-attempt cooldown without promoting the legacy repaired label to success.

The local collector uses only status --json --peers=false, hidden child processes and bounded concurrent byte reads. Output retention is capped at 64 KiB, including newline-free output. Timed-out, truncated, malformed or failed reads cannot become Running. Raw output and identifiers are not returned or persisted by the collector. Installed path/registration checks are not cryptographic publisher provenance.

The worker acquires the real shared operation lease before observation and retains it through recovery and publication. Existing marker schema and kinds are preserved; a read-only IsCurrent check verifies lease ID, PID and process start. The worker checks ownership, opt-in, environment and fresh intent again at each final action boundary. Service stop/start are individually authorized. Cancellation after a completed stop does not override opt-out by blindly dispatching start; the partial action is reported honestly. Current schema-2 results have fixed vocabulary, counters, UTC stamps and a run ID, bounded to 8 KiB with one predecessor. They are not written over corrupt or foreign-owner evidence.

These protections are not a local-administrator security boundary, an atomic guarantee against all external user/network changes, or proof of whole-PC power-loss recovery.

## Earlier foundation evidence and retained failures

The component-only checkpoint passed 502 checks at source 8e4c6de528889e5fe1016966b6bdf8da52ec24f8 in run 35510418246: 319 existing package regressions, 79 policy/state assertions and 104 bounded local-status assertions. Those assertions remain required after integration.

The initial workflow bootstrap correctly failed when the new test file had not yet been added. Run 35509216334 passed 66 policy assertions before an extra-settings-field assertion rejected the implementation. That test was retained and the parser corrected. Run 35509483290 stopped at the unchanged updater HTTPS self-test, exit 21; later runs passed the same gate without bypassing TLS. Run 35509761696 passed the then-77 policy assertions but failed fixture cleanup because a loaded DLL remained mapped. Loading the same native-compiled test assembly bytes fixed the fixture without removing cleanup; two predecessor-directory assertions brought the policy suite to 79.

## Work still required before a Phase 6 release

1. **Event and fallback acceptance.** Verify the existing five-minute scheduled fallback together with event-triggered behavior, settling, coalescing and cooldown after resume/network/VPN changes. Cover foreground, tray and fully exited UI. The present worker tests do not simulate every real Windows event or actual scheduled trigger.
2. **Background History and notification completion.** Persist bounded typed automatic activity while the UI is exited, distinguish reservation/action/outcome, and reconcile it without duplicate history or stale/replayed notifications. Preserve opt-in, shell suppression and persistent rate limits. The schema-2 notification guard prevents unconfirmed recovery claims; full background lifecycle coverage remains open.
3. **Actual Windows boundary acceptance.** Exercise validated installed-CLI discovery, protected execution, task registration/identity, relevant service/dependency failures and GUI process behavior in disposable Windows environments. Current native worker tests substitute only the service/process/environment boundary and scheduler with harmless fixtures; they do not mutate a real Tailscale service.
4. **Settings, UI and Setup edge cases.** Complete supported upgrade/default preservation, real task launch failure feedback, user disable during pending work, supported desktop/DPI/lifecycle behavior and both installation routes. Protected files require genuine Setup elevation, not an ordinary update overlay. Alternate-administrator identity, logon, reboot during Setup and restart acknowledgement are separate acceptance gates.
5. **Failure and release gates.** Retain all existing package/Guardian/coordinator/History/diagnostic/progress/export tests, final source/package privacy scans, exact repository/remote checks, exact artifact digests and independent publication checks. Include full interruption, rollback and power-loss work rather than substituting atomic local-file tests for it. Do not publish this development build before its required gates are satisfied.

## Master roadmap retained

Phase 6 remains Auto Repair 2.0; then Phase 7 Startup/Passive Health, Phase 8 Update Guardian 2.0, Phase 9 UI/Product Polish, Phase 10 Failure Lab/3.0 Acceptance and Phase 11 3.0 Stable. Earlier outstanding protected manual-run correlation/provenance, longer-term connection intelligence, background coverage, interrupted Setup/update recovery, alternate-admin identity and restart acknowledgement remain open. Phase 5 export desktop clipboard/picker acceptance is distinct from installed-version, integrity and diagnostic screenshots. No earlier requirement is completed merely by advancing the development version.
