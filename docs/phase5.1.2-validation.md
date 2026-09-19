# Phase 5.1.2: repeated-check progress isolation

## User-visible repair

The previous main-check reader accepted a file written as early as one second before a new launch and cleared its file watermark when starting. An existing completed result could therefore briefly repaint a fully completed rail before a new worker published. Attachment also used an arbitrary one-minute lookback. The final packaged UI now checks the embedded round-trip UTC timestamp before calling Apply-State. A new requested check establishes a strict time boundary; accepted timestamps/file watermarks survive subsequent clicks. Old, out-of-order, future, malformed or explicitly wrong-peer records cannot refresh the UI, complete the pending check or trigger its History/notification path. The result file itself is not deleted.

Attachment to a running or queued check uses the verified operation owner's process start when readable, otherwise accepts only newly observed results. A result already shown for an existing worker finishing cleanup remains steady. Attachment does not start another worker. The peer-stage dot explicitly returns to pending when its new measurement is not ready.

Diagnostics reset the value and rendered fill before exposing their starting state, preserve the old result file behind a fresh run ID, and use a scoped determinate ProgressBar template with no native completion transition. The existing two-pixel bar remains in place. No new dashboard panel, fake delay or simulated percentage was added.

## Scope and limitations

This is an ordinary app-only update: five release files in the ordinary manifest, six in the full Setup profile. No protected repair worker, Auto Repair monitor, operation-lock protocol, saved History data, notification preference, target configuration or network-repair decision was changed. History scrollbar polish and Diagnostics 2.0 from 5.1.1 remain present.

The main repair worker currently emits legacy timestamps rather than an authenticated/request-correlated run ID. These changes fix freshness and repeat-render errors for that supported format; they are not a new security boundary against another process writing fabricated local state. Independent protected run-ID work and whole-PC/interrupted-Setup acceptance remain outstanding. Diagnostics already have independent run IDs.

## Verification

Development run 35474136354 attempt 2 passed 260 checks across eight suites. The 31 new progress assertions execute the actual final PowerShell 5.1/WPF start/reset functions, state-timer callback, timestamp gate, Apply-State, main renderer and diagnostic button/timer/child-launch path. Scheduler, lease and side-effect destinations use controlled fixtures; no user's live Tailscale service is altered. Existing suites remain mandatory for Guardian, process ownership, History, update routing, diagnostics, notifications and connection quality.

Cases include an unseen terminal result inside the old one-second window; rapid repeat clicks; preserved previous evidence; retouched/out-of-order/partial/invalid/future state; genuinely fast completed checks without an intermediate poll; running-worker attachment using a real synthetic process start; and preserving the completed result while that worker exits. Two actual diagnostic starts with a delayed synthetic worker verify that old completed result IDs cannot repaint the new bar. Ten sampled WPF layout frames reported value 0 and actual fill width 0 before new measurements, with a nonzero 912-DIP track.

The first development attempt failed the unchanged updater HTTPS self-test before reaching these new tests. Its failed logs were retained; the completed failed attempt was retried without bypassing or weakening that gate. Attempt 2 passed the normal build, both packages, native gates and privacy/isolation scans. Final publication must independently pass the normal release workflow; development evidence alone is not proof of publication or user-desktop acceptance.

## Field acceptance

Update from the app's Maintenance controls. No administrator prompt is expected for this ordinary update. Check System integrity twice: expect Healthy with five verified app files, then a confirmed baseline. Run the normal check again immediately after completion and verify the rail starts pending instead of flashing the old full result. Re-run optional diagnostics and verify the thin progress bar starts empty. Saved History and Smart notification preferences should remain intact. Do not disconnect the working PC or delete markers/results to perform these checks.

## Roadmap continuation

The next planned Phase 5 increment is privacy-safe diagnostic export. Auto Repair 2.0, passive startup health, Update Guardian, broader UI polish, failure-lab acceptance and the stable-release gates remain on the master roadmap; this maintenance update does not mark them completed.

Primary UI reference: https://learn.microsoft.com/en-us/dotnet/desktop/wpf/controls/progressbar . The dedicated template uses the standard PART_Track and PART_Indicator while preserving native value-to-fill layout.
