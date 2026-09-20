# Protected update handoff

Some releases update files that Windows protects with administrator permissions. Existing 5.2.1 installations use an older Setup program, so the update path needs a safe handoff before protected files are changed.

The ordinary update package now carries a small version marker and the current Setup program. The existing updater is allowed to replace only user-level application files. It does not modify the protected backend or protected task files. When Quick Repair restarts, the updated interface sees the marker and opens the refreshed Setup program in upgrade mode. Setup validates that the marker matches the release before continuing and removes it only after the protected installation completes.

This keeps the normal Update button as the starting point while ensuring that protected changes are performed by the installer version that was tested for that release.

## Safety rules

- The old updater remains limited to user-level application files.
- The handoff marker contains only a schema number and release code.
- A missing, malformed or wrong-version marker cannot authorise protected installation.
- The updated interface starts only the installed Setup executable with the fixed `--upgrade` mode.
- Setup reuses the existing target and startup preference; it does not ask users to re-enter them during an upgrade.
- The marker is kept if protected installation does not complete, so the app can continue to show that attention is required.
- No live release channel changes are made by development tests.

The native test installs the genuine published 5.2.1 package, applies the tested ordinary package through the published updater core, confirms that protected files are untouched, checks the refreshed Setup file and handoff marker, and verifies the fixed upgrade route. Full user approval, cancellation, restart and rollback tests remain required before release.
