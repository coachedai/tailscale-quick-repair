# Phase 6.3 permission evidence checkpoint

## Later full-workflow checkpoint

Full run **35530635079** at **0b728ac46f6cc77a1f00799e1e63c7d4a918734f** subsequently passed all **784 assertions in 15 suites**, including the permission suite on the same exact package set and new independent monotonic/instance tracing. See **phase6.3-recurrence-observability.md** for checked digests, observed clock/event evidence and limitations. Earlier early-recurrence failures are not explained or reclassified by that pass. The following paragraphs retain the historical isolated-permission and HTTPS-blocked checkpoints at their own sources. Release and broader timing acceptance remain open.

## Historical isolated-permission checkpoint

At source c6b08b71977163fcaf8277f5f2fe1a579ed63b23, isolated permission run 35528931040 completed successfully. All 59 aggregate assertions passed. The 52 child assertions are included within that aggregate and must not be counted a second time from the separately retained original child report.

Artifact 10611080729 was downloaded and verified against SHA-256 0db5ad146863c966a5e0d82bca5e3fa0fb458a4e9ab3a196aa1e84fb36591782. Its source marker matches the tested commit; its protected Setup source blob is 7a5ad44f2bad03d5262d3b7211f9978700cfea23. All 84 source files were retained. The permission test script is byte-for-byte identical to the baseline script that completed its probes and exposed exactly two directory-creation permissions. The actual product Setup code, not the assertions, changed to address that finding.

The baseline and implementation details are recorded in phase6.3-permissions-validation.md. Real access-denied checks cover protected-file content/append/delete/permission/ownership rights and root add-file/add-directory/delete-child/permission/ownership rights. The same-user restricted process retains ordinary preference writes, task inspection and actual installed UI dispatch to the protected monitor. Native Windows denies the unchanged task write requests. File-byte verification confirms the probes do not modify protected payloads.

Full workflow 35528930998 subsequently failed at the unchanged updater HTTPS self-test, exit 21, before packaged suites. Its source artifact 10611026233 was preserved and downloaded; SHA-256 ea7bd912aa49040848e903e0f82f4c178c95b93f0515d42350602bb4b75be0e1. The underlying network failure was not diagnosed by that exit code and is not declared harmless. Its permission step did not run. The isolated pass cannot replace this failed full workflow, and the historical 723 total is not a current whole-build pass.

The documentation-only follow-up at that checkpoint left the tested product and test source unchanged and used the same complete required workflow. Its actual outcome is retained in the corresponding exact-head reports and PR verification comment; it is not reclassified here. No HTTPS check, timing bound, permission denial or prior suite is bypassed. No active workflow is restarted or cancelled to get green.

Development remains 3.0.0-phase6.3.0-dev / 30000730, publish:false and requiresSetup:true; live remains 5.2.1. The full Phase 6 and earlier carried scope, standard/split-token/other-user/alternate-admin, hostile path and migration cases, complete Setup/UAC/relaunch, supported upgrades/rollback/power-loss and publication-path enforcement remain open. The restricted process uses private test USER objects and is not physical desktop acceptance. Nothing here is an instruction to change a working user installation.
