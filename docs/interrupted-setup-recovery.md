# Interrupted Setup recovery

Protected updates change both application files and Windows integration. Quick Repair treats those as two distinct recovery problems.

## Payload files

Before replacing payload files, Setup creates a bounded recovery transaction under ProgramData. The recovery directory is restricted to Administrators and SYSTEM. The journal contains only fixed package-relative paths, the initiating Windows SID, whether each target previously existed, and old/new file size and SHA-256 metadata.

No product file is replaced until the prepared journal and required backups are flushed and verified.

A prepared transaction restores the previous file set. Recovery itself is restartable: once the old files are verified, the journal is marked `rolledBack` before backups are removed. If Setup is killed during that cleanup, a later run validates the restored files and finishes cleanup without requiring a backup that was already deleted.

After every candidate file has been installed and verified, the transaction is marked `committed` before old backups are deleted. A later interruption therefore keeps the verified candidate payload and only resumes cleanup; it does not roll the new version backwards.

Recovery refuses malformed journals, unexpected files/directories, redirected paths, unsupported link layouts and journals belonging to another Windows SID. Refusal preserves the evidence.

## Windows integration

Tasks, startup registration, Start menu shortcut, local target configuration and restart acknowledgement are applied by one fixed replayable Setup sequence after the payload is committed.

For protected upgrades, the handoff marker is removed last. If Setup is interrupted earlier, rerunning the refreshed Setup program replays the same desired integration state. The sequence is designed to converge to the candidate release rather than roll task/startup/shortcut state back to the older release.

The development acceptance starts from the genuine published 5.2.1 package and deliberately kills only fixture-owned Setup processes at known file and integration boundaries.

## Limits

This work does not claim storage-controller durability or whole-PC power-loss certification. It does not make local administrator access a security boundary. Physical desktop/UAC approval and approval with a separate administrator account remain separate acceptance work. The exact pass/fail result for each source revision is recorded by the Windows workflow and pull-request verification notes.
