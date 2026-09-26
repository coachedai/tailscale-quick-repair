# Phase 6.3: independently timed, attributed native recurrence

## Status and scope

Development remains 3.0.0-phase6.3.0-dev / 30000730, publish:false, requiresSetup:true. No merge, installation or live-channel change is part of this checkpoint. The published channel remains 5.2.1. The product source, manual backend, repair policy, protected permission implementation and UI are unchanged by this tracing increment.

The full development workflow at source **0b728ac46f6cc77a1f00799e1e63c7d4a918734f**, run **35530635079**, passed **784 assertions across 15 suites**. This is a single exact-source workflow result, not the sum of the old 723 result and an unrelated permission run: it includes all 679 preceding regressions, 46 native Windows cases and all 59 aggregate permission cases on the same package set. The separately retained original 52-case permission child report is not double-counted.

This pass does **not** explain or reclassify the previous early recurrences. The prior failures at approximately 242, 83 and 153 seconds remain unresolved historical observations; the old UTC-only evidence is insufficient to determine their cause. The work now provides stronger diagnostic evidence for subsequent observations rather than declaring that an unobserved defect has been fixed. Broader timing acceptance remains open before release.

## What was added

The existing harmless PowerShell action behind the native WScript launcher records UTC and QueryPerformanceCounter-based Stopwatch timestamps before querying its own process and the exact running test-task instance. Both the original UTC marker and bounded supplemental data are retained locally. The published report includes relative instance numbers, clock readings, fixed numeric event identifiers and process-match booleans, not raw process identifiers, task paths, user/device identities or event messages.

Parent sampling compares UTC with monotonic elapsed time and records the native NextRunTime. The diagnostic query is scoped to the uniquely named fixture task, bounded to 128 event records, and projects only selected fields. The TaskScheduler Operational channel is enabled only on the already guarded disposable runner when needed; its previous enabled state is restored and logs are not cleared. No production task schedule, external time synchronization, live network, tailnet or user desktop is changed for this diagnostic.

The original **290-345 second UTC gate and PT5M schedule remain unchanged**. An independent monotonic interval gate uses the same range. The parent test deadline is monotonic so a wall-clock adjustment cannot extend or prematurely finish the wait. No test task is manually run to produce fallback markers and no repetition interval is accelerated.

## Observed evidence in 35530635079

Marker UTC interval: **300.982797 seconds**. Independent QPC interval: **300.976179 seconds**. Their difference was **0.006618 seconds**. The two markers were recorded at **18:59:18.1287957** and **19:04:19.1115927 UTC** on 20 September 2026. Thirty-seven bounded parent samples had a maximum adjacent UTC/QPC disagreement of approximately **0.000620 seconds**. No large clock discontinuity was observed in this run; that does not prove historical runs had no clock changes.

Each marker was associated with a different real running task instance. The scoped Windows event trace contains the corresponding time-trigger event 107, task-start event 100 and action-start event 200 for each instance; action process attribution matches the marker's own process ancestry. No manual/event/logon trigger substituted for these observed starts. Inspection of the actual registered trigger collection shows only the PT5M TimeTrigger enabled, with the logon and both event triggers disabled for this independent fallback fixture. The real installed monitor and service event routes are exercised separately by the existing native suite.

This proves the measured cycle and its attribution in this run. It is not a guarantee of all future Task Scheduler timing, of every power/network state, or of exactly-once behavior under interruption. In particular, one clean trace is not a fix for the earlier failures.

## Independent artifact verification

Evidence artifact **10611385974**, SHA-256 **12c165b65d1f4aa1f2e94185b89d31a9d614bc661e3d817565b47c85b0df77cc**, was downloaded and inspected. Its source marker matches the tested commit. Its 86 source files reconstruct Git tree **1b63f1f1c336ffcf4b6662a2809421503b9edf93** after repository-defined text normalization. All 15 aggregate suite reports passed, with no failed assertion in this run. The clock and event report is supplemental evidence, not an additional passing suite.

Package artifact **10611470859**, SHA-256 **9f088146155ff3701defcb664c8a363e10dca6af476c961ea0473d4c23b548f9**, was downloaded and independently checked. Exact inner-manifest file sets, paths, sizes and hashes match. The ordinary and Setup UIs match; Setup app/protected Operations DLLs match; the ordinary package has no protected program files. The delivered manual backend retains SHA-256 **7c8bbf788194f78a8068a480011a3b55ec1e822de90a753b724d950ed7ec3533**. The new test tracer is absent from both product packages.

## Follow-up acceptance at the next exact head

The subsequent change adds a mandatory post-native attribution gate: two distinct marker instances must each match exactly one scheduled trigger, task start and process-attributed action start; unrelated manual/event/logon starts must be absent; only the indefinite PT5M trigger may be enabled; and both clocks must agree without a detected discontinuity. This prevents a mere registration event or ambiguous marker from satisfying the attribution gate. It does not remove or widen either interval assertion. The actual result of that final source must be read from its workflow evidence and PR verification comment, not inferred from the preceding pass.

Continue controlled reproduction and extended recurrence/event/load/clock-discontinuity coverage with this evidence available. Preserve old and new failures; do not retry until a lucky green run is substituted for diagnosis. Full Setup/UAC/alternate-admin, prior-install and hostile-path/provenance, client/authenticated/stuck-backend recovery, physical UI and wider Windows lifecycle, rollback/power-loss, earlier unfinished requirements and publication-path enforcement remain separate gates. Phases 7-11 remain unchanged; this is not Phase 6 completion or 3.0 Stable.

Primary API references: https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps ; https://learn.microsoft.com/en-us/windows/win32/taskschd/runningtask ; https://learn.microsoft.com/en-us/windows/win32/taskschd/repeating-a-task .
