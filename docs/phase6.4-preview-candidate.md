# 3.0.0 Phase 6.4.1 preview candidate

This candidate packages the Phase 6 engineering work into a uniquely versioned preview for final field acceptance. It is not the public stable release and is not published to the live update channel.

## Highlights

- Local-only automatic repair with confirmation, cooldown and retry limits.
- Intentional disconnect/sign-in/approval states are preserved.
- Real local Tailscale service start and client reopen boundaries are verified.
- Event-driven checks plus a five-minute fallback without missed-run replay.
- Truthful status when a protected background check cannot be launched.
- Read/run-only protected files and scheduled tasks for ordinary users.
- Genuine 5.2.1 → current upgrade compatibility.
- Protected update handoff through refreshed native Setup.
- Persistent restart acknowledgement before reporting an update as installed.
- File transaction recovery after killed Setup/recovery processes.
- Replay-safe Windows task/startup/shortcut integration after interrupted Setup.

## Field acceptance before public release

The preview is intended to close the few behaviors that hosted Windows runners cannot fully certify: physical UAC approve/cancel/retry, real desktop suspend/resume and vendor-neutral VPN/network transitions, and authenticated local-backend recovery.

The approving administrator must currently be the same Windows account that launched Quick Repair. Using separate administrator credentials is intentionally refused so per-user state is never written into the wrong profile.

Automatic repair should remain off during the initial field-upgrade check. Enable it only after the installed version, local status and protected-update completion are confirmed.

## Developer-only field artifact

The development workflow validates a separate field helper on a disposable hosted Windows runner before it emits a `phase6.4.1-field-preview` artifact. The artifact contains the helper, the field instructions, and only the exact validated ordinary and protected candidate ZIPs with their SHA-256 sidecars plus the exact source commit identifier.

The helper is explicitly checked to be absent from both shipping packages. It does not add a local-package mode to the production updater or Setup executable, does not alter `main` or the live update manifest, and does not publish a GitHub Release.

Hosted acceptance exercises the same released-5.2.1 updater core and refreshed protected Setup core without displaying a UAC prompt. It also simulates the pre-protected cancellation boundary, verifies the complete protected baseline remains byte-for-byte unchanged, and then retries from the staged bridge. This certifies cancellation/retry state handling, not the physical Windows UAC screen itself. Physical UAC presentation/interaction and real desktop lifecycle checks remain field acceptance.


## Preview-to-preview field transition

The physically accepted 3.0.0-phase6.4.0-preview / 30000740 build is an allowed developer field baseline for 3.0.0-phase6.4.1-preview / 30000741 only when its protected handoff and restart acknowledgement are complete and its Guardian known-good record matches the installed integrity manifest. The field helper refuses arbitrary, stale or half-finished preview state. New installable preview payloads advance the version code rather than reusing trusted identity across different bytes.
