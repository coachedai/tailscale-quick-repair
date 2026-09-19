# Phase 5.1.1: Diagnostics 2.0 foundation and History polish

## Delivered changes

History keeps its native ScrollViewer behavior, with a scoped 12-DIP scrollbar, rounded thumb, transparent rail, theme brushes and hover/drag feedback. The bright system rail and arrow buttons are no longer painted. Short histories do not need a scrollbar. Opening History returns to the newest events; retention, local data and the Copy action are unchanged. A Windows high-contrast thumb brush is included; this is not a claim that the entire application now has a complete high-contrast or light-theme mode.

The optional diagnostic worker now recognizes direct endpoint-form replies as well as DERP and peer-relay replies. It distinguishes unsupported flags, timeouts, incomplete output, missing evidence and confirmed replies. A successful process exit alone is not treated as a peer reply. Direct path, discovery, tunnel, ICMP and Peer API observations are interpreted independently. A working relay, IPv6 absence or detected VPN software is not automatically called a broken connection.

The existing diagnostic area has one explanatory text slot and a measured latency row. Copy report includes observation time, duration and network-inspection completeness. Diagnostic results do not overwrite the main health result, trigger repair, modify network settings or start background polling.

CLI calls use fixed command types, validated peer arguments, no shell and hidden child processes. Network inspection has an 8-second command budget; peer commands normally have a 3-second outer budget and a 2-second CLI timeout. The worker uses a 20-second probe budget and the UI watchdog allows 30 seconds including startup/environment inspection. Output retained by the collector is capped at 64 KiB and marked incomplete when truncated; raw command output and direct endpoints are not saved in the report. The timeout cleanup targets only the specific child started by that call, never an unrelated Tailscale process.

Progress/result publication flushes a new file before atomic replacement. The Windows PowerShell 5.1 no-backup argument uses NullString.Value; a null String conversion had left the development worker's first progress result unreplaced. The native worker fixture now verifies that the final completed result replaces those progress states.

## Packaging

This is an ordinary app update from 4.2.1, with no protected backend or Auto Repair monitor change and no operation-lock protocol change. The unprivileged diagnostic script is now included in ordinary updates, not only Setup. The ordinary integrity profile therefore covers five delivered app files; the matching Setup profile still covers six. The count describes the delivery profile, not an end-to-end signed trust root over every protected component.

Notification preferences, saved local History, target configuration, protected tasks and the main repair decisions are preserved. Both delivery paths remain required build/runtime validation targets.

## Native evidence and test isolation

Development run 35472789860 passed all seven suites. Retained evidence includes the final diagnostic worker result, History layout/scroll offsets, top/end renderings, and each suite's JSON assertions. The suites total 227 assertions represented by case arrays plus two backend-report cases (229 checks in total). Test coverage includes:

- Existing Guardian integrity/baseline, operation ownership, History retention/privacy, update routing, connection-quality and notification suites.
- Diagnostic parsing, independent protocol explanations, unsupported/missing/invalid measurements and locale-independent latency values.
- Real hidden child processes using a synthetic CLI, time limits and output truncation.
- The delivered worker with only its CLI-discovery boundary substituted for that synthetic executable; the final structured report and privacy assertions remain real.
- The actual final packaged WPF layout, scrollbar page commands, mouse-wheel events, thumb drag events, oldest/newest offsets and automatic hiding for short content.
- Actual result renderer and run-ID filtering, copied observation metadata and main-health isolation.

The updater route test now drains and verifies its own deferred Close callback before leaving each fixture scope. Previously those test callbacks could close a later suite's window when its message loop ran, making that unloaded viewer appear unable to scroll. A plain WPF positive control and visual-ancestor trace established the distinction. No production scrolling assertion was removed or replaced with a static source-marker pass.

Visual evidence is generated from synthetic event text in a disposable runner, never from a user's desktop or local logs. The History test exercises routed input events; it does not certify every physical touch device or Windows DPI configuration. CLI/network responses use fixtures, not the user's real network. Full installation/elevation, whole-PC power loss and interrupted protected Setup/update recovery remain separate outstanding acceptance work.

## Field acceptance

From 4.2.1 use Details > Maintenance > Check for updates > Update now. No administrator prompt is expected for this app-only update. Run Guardian twice: Healthy, five delivered app files, then a confirmed known-good baseline. Open History and check wheel/drag scrolling; saved entries should still be present. Run optional diagnostics and inspect its measured path, latency and explanation while the main connection result remains unchanged. Do not deliberately disconnect the working machine, delete baselines or stop network services to test this release.

Technical references: Tailscale's ping-types reference and Microsoft's WPF ScrollBar/ScrollViewer documentation and dotnet/wpf source. Diagnostic labels describe observed evidence; they do not prove RDP availability, bandwidth or uninterrupted uptime.
