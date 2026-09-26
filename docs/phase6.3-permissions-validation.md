# Phase 6.3 development: protected installation permissions

## Current state

This is unpublished development, not a field installation instruction. Version 3.0.0-phase6.3.0-dev, code 30000730, requiresSetup:true, publish:false. The live release stays 5.2.1. The manual repair backend and automatic repair decision/action set remain unchanged. The new Setup permissions implementation has not yet passed native acceptance at this document's introduction; final exact-head evidence must be recorded separately after all required workflows complete.

## Observed baseline gap

Isolated permission run 35528652993 at ee1d922594a131add60d0e6a5d78cb16eaf6a6be executed all 52 child assertions in a real same-user restricted primary process: Administrators deny-only, medium integrity and at most one remaining privilege. Two assertions failed: it could open the protected root with permission to add files and to add directories. Existing protected-file modification/deletion/ACL probes, task modification probes, ordinary preference writes and the actual installed UI's protected-monitor request passed in this specific configuration. The report is not evidence of exploitation or an all-desktop result.

Evidence artifact 10610477814 was downloaded and matched SHA-256 5a956bbcee45a4ba19c5151005ac549d6e0c6347f5c813a6c1b9ebfe92511966. It contains both the original typed child report and the aggregate permission result. Aggregate count is 59, including child completion, unchanged protected-byte checks and cleanup. Do not double-count the child report as an additional suite.

## Implemented change awaiting acceptance

Native Setup now applies explicit Administrators ownership and protected DACLs to only Quick Repair's fixed ProgramData directory and known protected files. SYSTEM and Administrators retain full access; ordinary users retain read/execute, not adding files, adding directories, content writes, deletion or ACL changes. The user-level app and preferences remain outside this permission change.

Task registration explicitly grants the current user read/run with Administrators ownership and SYSTEM/Administrators full control. TASK_DONT_ADD_PRINCIPAL_ACE prevents registration from silently adding broader rights; the resulting descriptor is checked. These task rules make the intended grant explicit, not a claim that the baseline task was empirically writable in the tested restricted configuration.

Preflight refuses unfamiliar or nested protected-root contents, reparse paths and linked files rather than recursively changing unrelated objects or erasing interrupted-install evidence. Known files receive explicit permissions after installation and on supported native integration repair. A permission failure fails Setup instead of being accepted as complete. Full interrupted Setup/rollback, adversarial races and trust provenance remain separate requirements.

## Native permission test

The test uses real access-handle requests without writing/truncating/deleting file content. Task write probes submit only unchanged descriptors/settings and expect access denied. A separate non-elevated process executes the actual installed UI settings and task-dispatch functions against real Task Scheduler; no scheduler substitute or elevation fallback is allowed. Its token restrictions are asserted inside the child.

A private test desktop/window station and default new-kernel-object permissions let the restricted child initialize on the hosted runner. Only new test objects and its scratch report directory are granted same-user access; existing Windows desktop ACLs and tested product/task ACLs are not relaxed. This is not a visual acceptance test on a normal user's desktop or a substitute for separate-account/alternate-admin testing.

The main development workflow still requires all preceding real-service/recurrence and package gates before permission acceptance. A faster isolated permission workflow builds a separate exact protected package in a fresh empty runner to diagnose failures; it cannot replace the full workflow or certify publication.

## Retained development failures

The initial permission harness could not obtain its child report. Native process-handle retention later exposed a child startup status of 0xC0000142; separate test USER objects and suitable default ownership for new token-created objects allowed initialization without restoring Administrator rights. A second harness issue assigned the parsed report to the case-insensitive string-constrained Report parameter. That incorrectly discarded typed report fields. The reader now uses a distinct childReport variable, copies the original typed evidence, requires all assertions and cannot pass on missing/partial reports. These harness failures are not protection passes or proof of a product vulnerability.

A full prerequisite run at 35527184574 failed the unchanged five-minute timing assertion with an observed 83.4509479-second interval. Its artifact 10609414735 and SHA-256 f72cc421dbf6d8a376f1a8c6b91b5ada6ec0a1d09a0ede0859296e4427ff9c33 are retained. It did not execute permission acceptance and is not reclassified as a full pass. The precise cause remains unestablished; the earlier timing failures also remain in their original records. No timing bound or permission assertion is to be relaxed to obtain a green result.

## Remaining scope

All earlier release gates remain: authenticated/client/stuck-backend and dependency cases; resume/logon/network/VPN and loaded/missed-trigger behavior; supported desktop/private-state trust and cross-user protections; full interactive Setup/UAC/alternate-admin/configuration/relaunch, upgrades/uninstall, restart acknowledgement, rollback and power loss; and equivalent exact-artifact gates on publication. No phase is completed merely by increasing a development version. Phases 7-11 and unfinished earlier scope remain binding.
