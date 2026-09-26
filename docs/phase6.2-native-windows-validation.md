# Phase 6.2: real installed Windows acceptance

## Development status

This checkpoint adds a required guarded native Windows acceptance suite to the existing development workflow. Product source and development version remain unchanged at **3.0.0-phase6.2.0-dev**, code **30000720**, `publish:false`, `requiresSetup:true`. The draft remains unpublished; the user's live update channel is still 5.2.1. This is not full Phase 6, full installer, or 3.0 Stable acceptance.

## Real boundaries exercised

The suite refuses to run outside an empty, interactive, administrator-capable GitHub-hosted Windows X64 runner for the exact repository/branch/run. It refuses pre-existing product/vendor directories, service registration, vendor policy and production task names. It verifies the development Setup ZIP's exact file set, paths, sizes and digests before invoking the actual packaged Setup verification, application and task-registration methods. Those methods are not replaced by copied installation algorithms. Installed file hashes and app/protected DLL parity are then verified.

The fixed official Tailscale 1.102.3 AMD64 MSI is downloaded through bounded HTTPS reads, matched to its official checksum response and validated by Windows Authenticode with the expected publisher. Its observed SHA-256 is **03ac8183c6e3ce276e9b44281ebe7e4c02aef28a971034ca170c4b665df42dce**. No authentication key, login, tailnet join or remote peer is supplied. Vendor support logging is opted out before the first service start. Private transient vendor files and raw output are not uploaded.

The installed production Windows machine adapter and worker, with no OS-machine substitution, observed the real unauthenticated backend as NeedsLogin. The worker took no repair action. After a controlled stop of only this lab's vendor service, the same policy retained that observed sign-in hold. A separately tested disabled service remained disabled.

A distinct new state fixture models a first observation of an eligible stopped service without any previously recorded intent. The original sign-in state is preserved; no marker, result or retry budget is deleted to manufacture permission. The first real observation waits. After 32 actual seconds, the real worker starts the real service under its operation lease. The resulting NeedsLogin state is not called recovery: the worker records one completed service-start action and an unconfirmed outcome in bounded History.

The genuine installed highest-interactive scheduled monitor is invoked separately. It executes the unmodified protected entry and produces a fresh attention result with exit code 20. After persisted opt-out, the same task exits 0 without rewriting its previous result. A real service transition also causes the exact native Setup system-event subscription to fire a harmless action in a separate test task. This does not claim that every OS event path has been exercised end to end.

For recurrence, a separate harmless task uses the actual Setup construction, its unmodified initial one-minute start and PT5M repetition. It is created after installation activity. No manual Run request or accelerated clock is used for this task. Two observed firings are separated by **301.0351972 seconds**. Scheduled start was 16:39:00 UTC; observed firings were 16:39:00.5458073 and 16:44:01.5810045 UTC on 20 September 2026. Both times and the 0.5458073-second first-start delay are retained in the typed report. This is one real repeated cycle, not a real-time scheduling guarantee under all loads or power states.

## Evidence

Code run **35523195671**, source **18b75def7bf181ffb7f86581dfe720fed5847446**, passed **723 checks across 14 suites**: the existing 679 checks plus **44 real Windows assertions**. Both package builds, source/package privacy, repository/remote/source identity, existing HTTPS gates and final no-publication/source-unchanged checks passed.

Downloaded evidence artifact **10608887637** matched SHA-256 **721d63f453dc7ee8667b02b42f32664becfe9bf926610ffcf69dcb71ada71ce8**. Every suite report and all 79 archived source files were inspected and matched the reviewed source. No report in the successful run contains a failed assertion. Development package artifact **10608702769** matched **a4f7880c792303ac0b446cd8896d217a361e2b56e5b0a63a7534ae921c119a4f**; exact inner-manifest file sets/hashes and unchanged manual backend were checked independently. A documentation-only follow-up must still pass the same workflow at its own exact head.

## Failed runs retained, not reclassified

Runs **35521987485** and **35522276266** were blocked by the test's reflection argument binding. Private CLR objects needed unwrapping, and using an output-producing PowerShell branch flattened the native generic installation-file list. Direct assignment preserves the actual CLR collection. The native Setup methods and acceptance assertions were not altered. The second report's cleanup overwrote its stage label; its raw log identifies ApplyFiles. The helper now freezes original failed-stage evidence before cleanup.

Run **35522633614** passed the real installation, vendor verification, service/intent/disabled-state, History, actual scheduled monitor and service-event checks, but the first two fallback markers were **241.7370919 seconds** apart. It is a failed recurrence result and is not counted as a five-minute pass. The original report does not establish the precise cause of that timing. The test now separates recurrence from MSI activity, retains actual scheduled/observed timestamps, and uses the unmodified initial delay. The required 290-345-second measurement range is unchanged; no failed assertion was removed, widened or treated as success.

Failed evidence ZIP digests, retained independently:

- 35521987485 / 10608627162: `31422a0ea2d3c8620d37fcf46e8ff366726dbdd0e47585a23e1791a898ac9eb9`.
- 35522276266 / 10608357048: `952a340a19ad8be0aa30d1e2dadd7311c4d963a24a169abfeb3b632054dd9074`.
- 35522633614 / 10608897785: `69b14aa82ba5c42969a665c2fd2e8d438792f542fcbdc969861da22d3a52f229`.

## Remaining gates

This is Windows Server 2025 on a hosted runner with one same-user elevated session, not all supported desktops. Interactive Setup Main/download/configuration/relaunch, UAC and alternate-administrator identity, reduced-token/standard-user permissions and protected file/task access controls, actual client reopening and sustained-backend stop/start recovery, authenticated connectivity, dependency failures, resume/logon/network/VPN transitions, loaded/suspended/missed-trigger timing, broad concurrency/interruption cases, physical tray/banner/DPI behavior, supported upgrade/downgrade/uninstall, restart acknowledgement, rollback and whole-PC power loss remain open. Vendor Authenticode validation in this test does not establish a signed trust root for every product component. The native suite is currently enforced by the development workflow; equivalent exact-artifact acceptance must be enforced on the publication path before any release. The main release workflow has not been silently certified by this development run.

Background replay remains bounded to current/previous snapshots and is not guaranteed lossless during prolonged History failure. Earlier unfinished requirements and Phases 7-11 remain binding. Nothing from this lab is a user installation instruction or permission to test outages on a working connection.

Primary references used: https://tailscale.com/docs/install/windows/msi ; https://tailscale.com/docs/features/logging ; https://learn.microsoft.com/en-us/windows/win32/taskschd/repeating-a-task ; https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-startwhenavailable .
