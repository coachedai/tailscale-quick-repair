# Phase 6.3: permission migration and preserved failure evidence

## Starting verified checkpoint

Full native run 35531632049 at 8847fbb5edeff559cbb03d4b2f2d89f0f2f693da passed 784 assertions across 15 aggregate suites, plus the separate mandatory exact-trigger attribution workflow gate. The original 52-case restricted child report is included in the aggregate permission result, not counted twice. Its downloaded evidence artifact 10611362140 matched SHA-256 07d7d0332c1d69064fcfe3b197ac83016c0a76f2270fc7ce9476a45a916f7a9a. All reports were inspected. The 87 archived source files reconstruct Git tree 6536489ede5257f3ce77bd6838fbf1197b693b2d after repository text normalization.

The latest observed recurrence was 301.0024024 seconds by UTC and 300.9946702 seconds by the independent monotonic counter. Both running instances match their own scheduled-trigger, task-start and process-attributed action events. This is an attributed successful measurement, not a diagnosis or retrospective pass for the previous unexplained early firings. Those failures remain open. The previous main development document describes its older blocked checkpoint; this document and the latest PR verification comments record the subsequent evidence.

## New acceptance work

This increment adds a required native test after same-run real installation and restricted-user permission acceptance. It makes no product-code, UI, repair-policy, schedule or version change. Development stays 3.0.0-phase6.3.0-dev / 30000730, publish:false, requiresSetup:true. The source introduced here is not declared accepted until its own complete workflow and artifacts have been inspected.

The script refuses every environment except the exact repository/branch on an empty GitHub-hosted Windows X64 runner, with the same commit's successful prior installation and permission reports. It checks that the earlier lab removed its vendor service and both product tasks. It acquires the actual packaged Setup operation lease, then preserves the original owned protected directory by a same-volume rename. It neither clears an ownership marker nor recursively deletes failed evidence.

The tests invoke the actual compiled Setup permission-preparation method and file-application methods, not a duplicate implementation. A deliberately permissive, same-user-owned prior-layout fixture must migrate to the exact protected owner/DACL while preserving every known file's bytes. Repeating preparation must be idempotent. This fixture is not a claim that every historical release had those precise rights, nor is it a complete older-version upgrade test.

Unknown files, an interrupted-copy scratch file, nested content, a locked protected input, a hard link, a file symbolic link, a redirected root and a regular file occupying the expected directory must be refused. The tests compare bytes and security descriptors of the affected fixture/independent target before and after refusal. A refusal caused by an unrelated reflection or compiler error cannot count as a pass. Every failed or successful fixture is retained in a separate test-owned directory. Link targets and their descriptors are not modified or deleted to make the test succeed.

After restoring the original installation, the actual Setup file-application method reapplies the exact same verified package twice. Every declared payload digest, protected-root/file permission and pre-existing selected preference/evidence digest must remain correct. This is same-package reapplication of the native file core, not full interactive Setup, task migration, rollback or older-version compatibility acceptance. The existing ordinary-user permission suite remains mandatory and is not replaced by static descriptor comparisons here.

## Evidence limits and continuation

Only typed result assertions and fixed failure codes are uploaded. Native fixture paths, ACL identities, private state and outside-target content remain local to the disposable runner. Native execution results belong to protected-migration-results.json and the final exact-source PR verification comment; this document predicts no count or success.

Concurrent hostile path replacement, reduced-token migration, separate-user/alternate-admin identities, signed provenance, genuine previous-version upgrade/downgrade, task migration, interactive Setup/UAC/relaunch, actual client/authenticated/stuck-backend recovery, broader Windows event/timing cases, physical UI/banner/DPI, rollback and whole-PC power loss remain separate gates. The main publication path still needs equivalent exact-artifact acceptance before release. All prior failed timing evidence and unfinished requirements, including Phases 7-11, remain binding. No user installation or working-PC test is requested.

Primary API references: https://learn.microsoft.com/en-us/windows/win32/fileio/file-security-and-access-rights ; https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createhardlinkw ; https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks .
