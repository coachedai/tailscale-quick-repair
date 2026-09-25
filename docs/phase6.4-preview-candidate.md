# Tailscale Quick Repair 3.0.0 RC1

RC1 is the first full Phase 6 release candidate on the opt-in **Early-access** update channel. It was published as GitHub prerelease `v3.0.0-rc.1` on 25 September 2026 from frozen source **2555bf4af30845d2c722964e289cfdfe15a412bf**. Stable remains **3.0.0-phase5.2.1**.

It includes guarded local-only Auto Repair 2.0, vendor-neutral VPN coexistence, exact Tailscale-adapter recovery scope, protected update handoff and interruption recovery, System Integrity Guardian, privacy-safe support export, connection intelligence, and true no-window startup-in-tray.

Workflow **36186476031** passed both Windows jobs before Preview publication. The publisher reused the exact validated package artifacts, created only the prerelease package ZIPs/sidecars, updated only the dedicated `preview/updates/preview.json` manifest, and disarmed its publication intent afterward. `main` and Stable `updates/latest.json` were not changed.

Post-publication compatibility commit **d16c8107aa1cf2403e52fe66a6c82b221b2918d5** passed workflow **36189240040**. The developer-only field helper now exact-allows these trusted previous-preview identities:

- **3.0.0-phase6.4.0-preview / 30000740**
- **3.0.0-phase6.4.3-preview / 30000743**

A previous preview is accepted only when its Guardian known-good record matches the installed integrity manifest. Arbitrary versions, version ranges, local package URLs and mismatched integrity records remain refused.

The post-publication pipeline also verifies the exact public RC1 release assets by frozen tag, target commit, size and SHA-256, privacy-scans the downloaded archives, and reruns the field acceptance against those already-published bytes. This is intentionally stronger than testing a freshly rebuilt package that merely shares the same version number.

Once RC1 is installed, future release-candidate delivery uses **Early-access updates → Check for updates → Update now** inside Quick Repair. The field helper remains developer-only and is excluded from shipping packages.
