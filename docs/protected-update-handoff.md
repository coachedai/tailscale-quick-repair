# Protected update handoff

Some releases update files that Windows protects with administrator permissions. Existing 5.2.1 installations use an older Setup program, so the update path needs a safe handoff before protected files are changed.

The ordinary update package now carries a small version marker and the current Setup program. For this transition, the release manifest identifies the download as a normal user-level update and separately marks it as a protected handoff. That allows existing 5.2.1 updaters to accept the package without giving them permission to change protected files. The existing updater replaces only user-level application files; it does not modify the protected backend or protected task files. When Quick Repair restarts, the updated interface sees the marker and opens the refreshed Setup program in upgrade mode. Setup validates that the marker matches the release before continuing and removes it only after the protected installation completes.

Quick Repair does not report the protected update as fully installed at the user-level bridge stage. Setup stores the release code as a pending restart acknowledgement, and the refreshed app clears that acknowledgement only after its interface has loaded successfully. That is the point where the update can be shown in History as installed. If Windows approval is cancelled, the handoff marker remains and Quick Repair stays usable so the update can be tried again later.

This keeps the normal Update button as the starting point while ensuring that protected changes are performed by the installer version that was tested for that release.

## Safety rules

- The old updater remains limited to user-level application files.
- The transition uses a separate protected-handoff flag; it is not advertised to 5.2.1 as a direct protected update.
- The handoff marker contains only a schema number and release code.
- A missing, malformed or wrong-version marker cannot authorise protected installation.
- The updated interface starts only the installed Setup executable with the fixed `--upgrade` mode.
- Windows administrator approval is requested only when the protected part is ready to run.
- Cancelling that approval does not remove the marker, close the app or claim the update completed.
- Setup reuses the existing target and startup preference; it does not ask users to re-enter them during an upgrade.
- A successful protected install writes a pending restart version before the handoff marker is removed.
- Only the matching refreshed app can clear that pending restart value and report the update as installed.
- The marker is kept if protected installation does not complete, so the app can continue to show that attention is required.
- No live release channel changes are made by development tests.

The native test installs the genuine published 5.2.1 package, applies the tested ordinary package through the published updater core, confirms that protected files are untouched, checks the refreshed Setup file and handoff marker, and verifies the fixed upgrade route. Full user approval, cancellation, restart and rollback tests remain required before release.
