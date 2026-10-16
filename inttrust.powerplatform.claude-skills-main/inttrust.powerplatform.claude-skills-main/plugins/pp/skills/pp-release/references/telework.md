# Release profile: Telework

## DEV: Telework specifics of the Dataverse Git loop
The loop itself is `dataverse-git.md`. What is particular to Telework:

- The solution `RemoteWorkDays` is one of four solutions bound to the same repo (`Surveys Power Platform Solution`,
  ADO project ELPE Surveys) under `Root/` - only `RemoteWorkDays` is genuinely git-backed. The Git folder for the
  Connect dialog is `Root/RemoteWorkDays`, branch `main`. Renames of the ADO project or repo break the binding
  (the binding stores names, not ids) and need the DevOps admin.
- Typical Conflicts after a reconnect: solution, publisher, canvas app, plus any changed flows and the leaves env var
  definitions. A flow merged but never pulled reappears as a conflict on every cycle until pulled - accepting incoming
  is harmless.
- The InTTrust publisher row can stay under Updates (1) forever (dated d/M/yyyy in the Greek locale) - a no-op.
- Display name: `InTTrust - Remote Work` (labels 1032 and 1033 in `solutions/RemoteWorkDays/solution.yml`); the unique
  name `RemoteWorkDays` cannot change. A Studio Publish followed by a pane Commit has reset the 1032 label to
  `RemoteWorkDays` three times (not every time). Check the Solutions list after publish + commit; fix with a one-line
  PR on `solution.yml` and a pull. Don't leave it wrong at the end of a task.
- A PROD export bumps the DEV solution version: mirror the bump into `solution.yml` in the next PR; with the solution
  row in the pull, a Src-only PR can pull without the disconnect cycle.
- One environment serves DEV makers and DEV testers: flows are live for everyone the moment a pull lands (canvas
  versions are staged; flows are not).

## PROD
- PROD (`environments.prod`) is managed and belongs to the PROD owner, who imports and maps connections their own
  way. Prepare the hand-over; do not import.
- No PROD SQL on Thursdays (registration peak after the weekly reminder); imports Monday to Wednesday.
- Before an export for PROD: restore the App Insights connection string in DEV if it was cleared, and list everything
  since the last PROD build (flows, env var definitions, V2 procs, app settings).
- New procs must exist on the PROD database with the same grants as their predecessors before the import: a PROD
  import once left `DBInsertRegDay` / `DBRemoveRegDay` Off with `WorkflowOperationParametersExtraParameter` because the
  PROD connection could not see the V2 procs' parameters.
- After the import: every flow's state (`workflows?$filter=category eq 5`), sharing of new app flows with both PROD app
  teams, feature switches at their intended values (leaves are kept off in PROD on purpose).
- `DBInsertRegDay` / `DBRemoveRegDay` carry an unmanaged "Customized" layer in PROD, so a managed import does not
  override them - report it before relying on an import to change them.
- PROD flows are owned by the PROD service account; PROD diagnostics are read-only (skill pp-prod-diagnosis).
