# Phase 4.1.1: passive Connection Intelligence 2.0 foundation

## Scope

The existing Remote insight gains a plain-English explanation. The old duplicate Session row in Remote details becomes Baseline. Its tooltip explains that these are completed checks from this app session, not continuous monitoring, a bandwidth test, packet jitter or an RDP test. Existing current route, reachability and latency fields remain.

The analysis performs no network requests, disk I/O, repairs, timers or notifications. It observes results already produced by the normal check. Peer keys and sample values remain in memory and are not added to the history file. The existing bounded privacy-safe event History remains available. This release does not claim background history coverage while the app is exited.

## Comparison policy

- At most 20 completed results within 30 minutes. Duplicate timestamps, out-of-order updates, future data and in-progress results are not samples.
- A baseline requires three valid comparable results and uses a median of up to six accepted observations. Direct, different DERP relay locations and peer relay paths are separate comparisons.
- A high reading is at least 35 ms and 70% above the recent baseline. A low reading is at least 25 ms and 30% below it. These are conservative product heuristics, not externally guaranteed network-quality thresholds.
- One excursion is described neutrally. Two consecutive comparable excursions confirm the latency change. Elevated readings are not immediately folded into the baseline and normalized away. A confirmed improvement can establish a lower reference.
- Observed path transitions, repeated Direct-to-Relay fallback and three or more transitions within the last eight observations receive factual explanations. A normal relayed connection is not itself declared broken.
- Reachable/unreachable transitions are taken from completed check outcomes. Online hints are not substituted for reachability or quality measurements.
- Network changes/resume and target changes reset the comparison state. Old results from before the network reset and state belonging to a prior target are rejected. A gap beyond 30 minutes requires a fresh baseline.

No quality assessment changes the main check's Healthy/Unreachable result or triggers recovery. Session Activity records meaningful transitions; the existing persistent History keeps its typed privacy boundary.

## Packaging and regression requirements

ConnectionQuality is compiled into the existing app operation library without modifying OperationGate or the protected repair workers. Both update and Setup packages are built and compared. An ordinary update therefore has four app files in its integrity profile; Setup has six. The two counts describe delivery coverage, not a claim that protected workers have a signed trust root.

The permanent packaged-runtime runner also invokes test-connection-quality.ps1, which exercises median formation, outlier handling, sustained increase/recovery, route separation, repeated switching, missing measurements, timestamp validation, locale-independent decimal parsing, target/network resets and bounded memory. It loads the final packaged XAML and executes the actual final analysis/presentation functions, checking that the main health result is untouched and that reserved layout height remains.

All existing Guardian, ownership, history, update-route and backend-report suites remain mandatory. Development runs must pass on native Windows PowerShell 5.1/WPF/.NET before promotion; source markers alone are not an acceptance pass. Live networking, user UAC, notifications and whole-PC power loss are outside this test scope.

## Field acceptance

From 3.5.1, use Maintenance > Check for updates > Update now. This is an ordinary app update; it changes no protected worker or operation-lock protocol and should not need administrator approval.

Check integrity twice; four delivered app files are expected for this ordinary-update profile. Run three normal connection checks and inspect the Remote baseline. A single fast measurement must not claim uninterrupted stability. Close to tray, fully exit, reopen, then verify the comparison begins fresh while saved History remains. Do not generate outages or intentionally stop network services on the working PC to test this feature.

## Remaining roadmap

This is the first Connection Intelligence 2.0 increment, not completion of Phase 4. Optional monitoring, independent longer-term connection baselines, deeper diagnostic path interpretation and Phase 4.2 rate-limited/user-disableable Smart Notifications remain planned. Full interrupted-Setup/update and power-loss acceptance gates are also still outstanding from the recovery work.

Technical reference used for the Direct/DERP/peer-relay distinction: https://tailscale.com/docs/reference/connection-types . The performance comparison policy above is explicitly our own observational heuristic.
