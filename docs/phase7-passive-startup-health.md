# Phase 7: Startup / Passive Health

## Current candidate

**3.0.0-rc.3 / 30001003** is the current **unpublished** Phase 7 Early-access candidate.

The live Early-access baseline remains **3.0.0-rc.2**. Stable remains **3.0.0-phase5.2.1**.

## Purpose

Phase 7 makes Quick Repair useful immediately after launch without turning startup into a full connection check.

Startup/passive health is **local-only and read-only**. It must not ping the configured peer, inspect peer reachability, measure latency, classify routes, run Advanced diagnostics, start a repair, change the Tailscale service, reopen the Tailscale client, or alter any unrelated VPN/network state.

Automatic Repair remains the only background policy that can request a Tailscale recovery, and its existing confirmation/cooldown/intent rules remain unchanged.

## Passive inputs

The startup observation is deliberately small:

- expected local Quick Repair app components are present, non-empty and not reparse points;
- the existing repair-engine/task integration check passes;
- local target configuration is classified only as **Configured**, **Missing**, **Invalid** or **Unknown**; the target value is never passed into the passive-health policy;
- the existing bounded native local observer reads:
  - Tailscale Windows service state;
  - service startup mode;
  - local Tailscale desktop client state;
  - local backend state through the fixed installed Tailscale CLI command `status --json --peers=false`.

The bounded CLI collector returns only the backend state. Raw stdout/stderr, peer data, addresses and device information are not returned or persisted.

## Decision model

The typed `PassiveStartupHealth` policy is pure: it has no filesystem, process, service, network, timer, persistence or repair access.

- Fully healthy local service/client/backend is silent.
- A missing target does **not** turn healthy local Tailscale into a fault; it simply means a full peer check is not configured yet.
- Invalid local target configuration, missing Quick Repair components, broken repair integration, missing/disabled Tailscale, sign-in, device approval and another-user states are actionable attention states.
- Intentional Tailscale disconnect remains **Paused** and does not notify or trigger repair.
- Stopped service, closed desktop client, backend starting/no-state/unknown and other uncertain states remain **Waiting** and do not notify or mutate anything.
- Passive health never labels a repair as successful because it never performs one.

## Presentation and notifications

Before any full peer check, the Local card and tray can show a compact local state such as **Local healthy**, **Local attention**, **Local disconnected** or **Local check pending**.

A completed full connection check remains authoritative and replaces the passive tray summary.

Smart notifications are still opt-in, rate-limited, tray-only and typed. Phase 7 adds generic actionable startup codes only for:

- Quick Repair maintenance;
- invalid local target configuration;
- missing Tailscale;
- disabled Tailscale service;
- Tailscale sign-in;
- device approval;
- another Windows user owning the Tailscale session.

Routine healthy startup, intentional disconnect and transient local states are silent.

## Acceptance

RC3 must pass:

- pure typed policy cases for every supported local state;
- final packaged PowerShell/WPF parsing;
- proof that the startup function contains no peer-reachability, route, latency, Advanced diagnostics or repair-dispatch path;
- proof that startup uses the existing bounded local machine observer and typed passive policy;
- exact package/integrity/privacy gates;
- existing Auto Repair/native recurrence/permissions/migration gates;
- the generic published-RC1 -> current-RC Preview upgrade path;
- the all-ref Git-history privacy audit.

Real-machine screenshots, logs, paths, addresses, device names and per-machine acceptance evidence remain off GitHub.
