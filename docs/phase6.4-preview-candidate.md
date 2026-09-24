# 3.0.0 Phase 6.4 preview candidate

This candidate packages the completed Phase 6 engineering work into a clearly versioned preview for final field acceptance. It is not the public stable release and is not published to the live update channel.

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

The preview is intended to close the few behaviors that hosted Windows runners cannot fully certify: physical UAC approve/cancel/retry, real desktop suspend/resume and VPN/network transitions, and authenticated local-backend recovery.

The approving administrator must currently be the same Windows account that launched Quick Repair. Using separate administrator credentials is intentionally refused so per-user state is never written into the wrong profile.

Automatic repair should remain off during the initial field-upgrade check. Enable it only after the installed version, local status and protected-update completion are confirmed.
