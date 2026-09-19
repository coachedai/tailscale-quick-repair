# Phase 4.2.1: Smart Notifications foundation

## User-visible behavior

Smart notifications is opt-in and lives in the existing Automation area. The adjacent Test action is disabled until the preference is saved. Routine healthy checks and an ordinary reachable relay never trigger a notification. Except for an explicit Test, the window must be hidden in its tray; events already seen in the foreground or during a blocked Windows state are dropped, not queued for a later burst.

The policy limits attempts to one per two minutes globally, one per thirty minutes per event category, and three per rolling hour. The limits survive app restarts and preference toggles. The Test action shares the budget. The local policy record holds only the boolean preference, allowlisted event codes and timestamps, bounded to 16 KiB and 64 retained attempt records, with one previous copy. It does not hold peer names/addresses, file paths, raw monitor messages, tokens or notification text. Damaged/unreadable policy files are preserved and notifications fail closed.

The current event adapters observe completed peer checks, the passive connection-quality result, Auto Repair's existing local state file, validated update-check results and Guardian attention results. Auto Repair's legacy status named `repaired` actually means the task was started: this release labels that state `recovery started` and never announces recovery from it. A later monitor result must explicitly report client, service and backend Running, after a recent observed recovery attempt, before a local recovery notification is eligible.

No remote-monitoring feature is enabled by opting in. There are no extra network calls, peer probes, scheduled tasks or timers; the existing five-second local UI-state tick reads a bounded monitor file when opted in. Exited apps cannot emit these notifications. Cold-start results are not replayed. Update success/failure remains inline and in History; a banner is eligible only when a fresh result is observed during the running tray session. Specific proven rollback-completion notifications await Update Guardian evidence rather than inferring a rollback from a generic failure.

Clicking a banner can only restore the existing Quick Repair window; it does not follow a URL, start a repair or approve elevation.

## Windows behavior

Before requesting a banner, the shell must report QUNS_ACCEPTS_NOTIFICATIONS. Locked/unavailable, full-screen, presentation, quiet-time and unknown/query-failure states suppress the request. Windows controls whether a banner is displayed and its timing/sound; the app never overrides notification settings or claims every version of Focus Assist/Do Not Disturb can be exhaustively detected by this legacy shell API. A recorded attempt is not proof of delivery.

Primary references:
- https://learn.microsoft.com/en-us/windows/win32/api/shellapi/ne-shellapi-query_user_notification_state
- https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.notifyicon.showballoontip

## Package and regression gates

The new class is compiled into the existing app library without changing protected repair/monitor workers or the operation-lock protocol. This is an ordinary four-file app update; matching six-file fresh-install Setup assets remain available.

Existing Guardian, process ownership, local history, update routing, repair-report and passive-quality suites remain mandatory. New native Windows tests exercise default-off/persistent preference, foreground and shell suppression, stale/duplicate/future data, persistent rate limits, clock rollback, data minimization, atomic predecessor preservation, damaged/locked policy state and the actual final packaged WPF preference/Test events and signal adapters. The shell availability query runs natively, but the banner sink is a fixture so unattended CI does not spam its desktop. Actual banner visibility, clicking it and Windows sound/Do Not Disturb presentation require field acceptance.

No whole-PC power-loss or interrupted protected-Setup guarantee is made by these tests. Those recovery gates remain outstanding. This first increment does not silently turn on continuous monitoring or mark the remainder of Phase 4 complete.

## Field acceptance

Update from 4.1.1 using Maintenance. Check integrity twice, expecting Healthy with four delivered app files. Existing baselines and saved History should still work. Smart notifications should initially be off. Enable it, click Test once, and verify the generic notification if Windows allows it; clicking the banner should restore Quick Repair. Do not generate real outages or stop services to test alerts on the working PC. Disable/re-enable and fully exit/reopen to verify the preference persists; repeated Test requests are intentionally rate-limited.
