# Phase 6.3: genuine released payload and task upgrade acceptance

## Verified released-upgrade checkpoint

The new job consumes the exact protected package produced by the successful native verification job in the same workflow. It does not rebuild the candidate. It downloads the genuine published 3.0.0-phase5.2.1 Setup ZIP and pins its size (140164) and SHA-256 (bad4deb522afd9442e918cacde1f58cc1509635de3be172626846060516df470). Both old and new ZIP paths, exact file sets, sizes and inner-manifest hashes are checked before use.

A clean GitHub-hosted Windows runner installs the actual released payload and tasks using its compiled old Setup core. Old and new libraries are loaded in separate native PowerShell processes to avoid assembly-identity substitution or locked installed executables. The old UI writer, History writer, notification policy and state writer create typed fixture state. Missing, explicit-off and explicit-on preferences are separate scenarios; each completed installation is preserved by same-volume rename before the next. The synthetic old reservation is labelled test state and is not evidence of a real past repair.

The actual new Setup file/task routines upgrade each released installation without deleting its tasks first. Tests require exact payload digests, preserved selected preference/History bytes, retained target and startup options, correct task identity and explicit task read/run grants, migration from the old single trigger to the new four-trigger definition, matching protected/user libraries and accurate first migrated-monitor behavior. The native installed monitor must preserve a legacy reservation without manufacturing confirmed recovery. Missing/off preferences must not create a new retry policy or overwrite prior evidence. Test-owned old tasks are quiesced before the upgrade; running-operation migration is not covered.

## Important delivery distinction

This is acceptance of the NEW Setup executable upgrading an existing genuine release. Source review shows the installed 5.2.1 Setup detaches a copy of itself and executes its own compiled installation/task routines; fetching a new payload does not replace the code already executing in that process. It predates protected-directory hardening and the new event-trigger construction. Therefore a successful new-host core upgrade cannot certify the old in-app --upgrade route.

The released-upgrade workflow completed successfully at the checkpoint immediately before the handoff work: the full workflow passed **964 assertions across 17 aggregate suites**, including the genuine 5.2.1 upgrade scenarios described above. That result proves the new Setup core can upgrade the released files and tasks; it does not prove that the old in-app update route executes the new Setup core.

The current branch therefore adds the missing staged handoff. Existing 5.2.1 clients receive a user-level bridge through their existing updater, then the refreshed application starts the refreshed Setup program in fixed upgrade mode. The bridge uses **protectedHandoff:true** and **requiresSetup:false** so the 5.2.1 updater does not reject the user-level package. Protected files remain untouched until the refreshed Setup runs. This handoff is under its own Windows verification and is not declared complete until those exact-source checks pass.

Development stays 3.0.0-phase6.3.0-dev, 30000730 and publish:false. The live channel stays 5.2.1. Product source, UI layout, manual backend, repair actions and schedule are unchanged by this test increment. Counts and results belong to the exact workflow reports once inspected, not predictions in this document. All earlier failed timing observations, unfinished scope and Phases 7-11 remain binding.

Primary references: https://learn.microsoft.com/en-us/dotnet/framework/deployment/best-practices-for-assembly-loading ; https://learn.microsoft.com/en-us/windows/win32/taskschd/taskfolder-registertaskdefinition .
