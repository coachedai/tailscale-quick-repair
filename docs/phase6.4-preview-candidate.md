# Tailscale Quick Repair 3.0.0 RC1

RC1 is the first full Phase 6 release candidate intended for the opt-in Early-access update channel. Stable remains unchanged until RC acceptance is complete.

It includes guarded local-only Auto Repair 2.0, vendor-neutral VPN coexistence, exact Tailscale-adapter recovery scope, protected update handoff and interruption recovery, System Integrity Guardian, privacy-safe support export, connection intelligence, and true no-window startup-in-tray.

The candidate is **not published by this commit**. `release/preview-publish.json` remains disarmed. CI must pass verify + released-upgrade first, then a separate explicit arm commit may publish a GitHub prerelease and update only the dedicated `preview` branch manifest.

The developer field helper treats the physically accepted 3.0.0-phase6.4.3-preview / 30000743 bootstrap as its previous-preview baseline for RC1 / 30001001.
