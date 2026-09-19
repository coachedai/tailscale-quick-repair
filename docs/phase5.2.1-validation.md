# Phase 5.2.1: privacy-safe support export

## User workflow

The existing Advanced diagnostics Copy report action becomes Share report. It remains available before diagnostics have run, and while another check is pending. Clicking opens a native, theme-matched WPF preview; it does not copy, save or upload automatically. The report is a frozen snapshot of observations available when that preview opened. Copy report copies that snapshot, and Save .txt opens a user-controlled Save As picker. Include recent history is off by default; selecting it adds at most ten eligible typed events from the last thirty days.

The preview inherits the existing palette and slim History scrollbar. No extra home dashboard panel is added. Closing the preview leaves Quick Repair running. An export or clipboard error is reported in the preview, not as a failed connection or a global UI crash.

## Contents and privacy boundary

The report contains Quick Repair/Tailscale versions; a completed main check's client, service, backend, peer reachability, path class and latency; whether repair actions were reported; the observed Guardian outcome, app-file count and baseline status; relevant independent read-only diagnostic results; and optional recorded activity. Pending, absent, incomplete, old or network/target-invalidated observations are labelled, not promoted to a fresh successful result. Diagnostic latency is separate from main-check latency.

The builder accepts only fixed status vocabulary, bounded/reformatted numbers, validated version strings and reformatted UTC timestamps. It does not export raw summary/error text and does not attempt to redact an unrestricted log dump. Addresses, host/device/user names, local paths, tokens, run IDs, history IDs, relay regions and detected VPN product names are omitted. Identifier exclusion cannot be disabled accidentally. Recent history uses predefined event descriptions, never arbitrary stored messages.

Versions, timings and health outcomes are intentionally visible; this is not a guarantee of anonymity or a defence against a malicious process deliberately fabricating observations. Review the preview before sharing. The new Share report path has this privacy contract; purposeful existing Copy peer IP and other copy actions are not silently redefined as redacted exports.

The report builder performs no network calls, diagnostics, service queries, repairs or directory enumeration. The collector uses current in-memory observations and one existing bounded typed history file. Reading history does not create a lock, rewrite the file, delete corrupt records or collect raw logs. Invalid/locked/oversized history becomes unavailable in the report. Input is capped at 64 KiB, history reads at 32 KiB, and generated text at 16 KiB characters.

## Saving

Save creates a new local .txt file. Existing filenames are refused, including a destination that appears after the picker closes. The writer flushes a unique temporary file in the chosen folder, then renames it without replacement, and cleans up its own temporary file. It does not delete old reports. UNC paths, alternate streams, non-text destinations and reparse-point paths are rejected. A normal local folder and a new filename are required. No automatic upload is implemented; external OS clipboard or folder-sync behavior remains outside Quick Repair's control.

## Native verification

Development run 35475838518 passed 319 checks across nine suites, including 59 new export assertions. Evidence includes a rendered preview and a synthetic sample report. Existing Guardian, operation ownership, History, update routing, repair-report, notification, diagnostics and repeated-progress suites remain mandatory. The first export run passed its privacy/file cases but failed to compile a test-only clipboard/picker fixture because PresentationCore was missing from that fixture's references. The reference was added; no product acceptance assertion was removed or weakened.

New tests cover injected identifiers and control characters; unknown/free-form values; historical, pending and incomplete observations; optional/bounded history; malformed/oversized input; locked history preservation; exact saved text; refusing existing destinations, UNC and alternate streams; and temporary-file cleanup. The actual native WPF preview, checkbox, Copy/Save events, scrolling, failure feedback, close behavior and final packaged Share button/modal are exercised. The test clipboard destination and Save As selection are controlled fixtures, while the file-writing implementation itself is native. User-desktop clipboard integration, native picker interaction and every DPI/touch configuration still need field acceptance.

## Package scope

Ordinary five-file app update from 5.1.2; matching full Setup still has six app files. Export classes are compiled into the existing app library. No protected repair worker, scheduled task, monitor, operation-lock protocol, target setting, notification preference, saved History retention or network setting changes. Both delivery paths build and pass existing package parity and integrity gates. Pre-publish privacy scans, repository isolation, exact artifact/digest checks and final release validation remain required.

## Field acceptance

Update through Details > Maintenance > Check for updates > Update now. No administrator prompt is expected for this ordinary update. Check integrity twice, expecting Healthy with five verified app files and then a confirmed baseline. Open Share report, inspect the preview, optionally include recent history, then Copy report or save a new .txt file. Confirm the contents match the preview and contain no addresses or device names. Closing the preview must leave the normal check, History and notification preferences intact. No deliberate outage or marker deletion is needed.

## Still outstanding

This implements the privacy-safe snapshot/export increment, not a raw-log archive or an automatic upload service. Auto Repair 2.0, passive startup health, Update Guardian, broader UI polish, interrupted-Setup/power-loss acceptance and the stable-release gates remain on the master roadmap. Do not equate successful export tests with those separate acceptance passes.

Primary API references: https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.savefiledialog and https://learn.microsoft.com/en-us/dotnet/api/system.windows.clipboard.settext .
