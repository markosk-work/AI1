# Release profile: Surveys

## Environments
- InTTrust DEV (`environments.dev`): development and current source, unmanaged.
- Customer QA (`environments.qa`): the "QA" build, unmanaged. Customer PROD (`environments.prod`): managed, the
  customer's users. Customer environments are acted on only on an explicit instruction naming the environment; the
  deployer account is `environments.prod.deploy_account`.
- `Root/Surveys` in git lagged live for over a year; DEV is now committed to it through Source control (where it
  stands: `repos.app.notes`). DEV can still be ahead (imports are not committed until someone commits): for current
  code run a read-only export from DEV; never assume a baseline - read `Version:` or `pac solution list` every time.

## The owner's build script: `SurveysDeployment/MakeSurveys.ps1`
- Processes every `Surveys*.zip` in the repo root. A name containing `managed` builds for Production (managed);
  anything else builds for QA (unmanaged).
- For each zip: `pac solution unpack` -> `pac canvas unpack` -> set `EnableInstrumentation` and the environment's App
  Insights key in `CanvasManifest.json` and `AppInsightsKey.json` -> repack as `<name>.final.<Env>.zip` -> move the input
  into `<name>/`.
- No parameters, no error handling, and it moves and deletes files: run it only on explicit request, from the repo
  root, with `pwsh` (Windows PowerShell 5.1 writes the JSON as ANSI). Keep this script-based process.
- Release folders: `Surveys[_Patch_<id>]_<ver>/` (QA) and `..._managed/` (Production), each with the Dataverse export
  and the `.final` build, all committed. QA and PROD are separate exports with consecutive versions; PROD hotfixes have
  shipped as solution patches.
- Releases are now `release/<ver>` branches (since which release: the project's memory), each based on the previous
  release branch with its own PR to `master`, and `..._managed/RELEASE-NOTES.md` lists every file with its SHA-256,
  how it was built, where and when it was applied, and "Where the folder convention is not followed". A release built
  by patching (below) has no managed Dataverse export, and its `Surveys_<ver>.zip` is the built package imported into
  DEV, not an export - read the notes before treating a folder's zip as an export.

## Customer (QA / PROD) packages: patch the previous `final` package
- Inside the `.msapp` the only environment-specific part is `Properties.json` (`EnableInstrumentation`,
  `InstrumentationKey`, `ConnectionString` = that environment's App Insights key); data sources and connections are
  the same as DEV's. The `final` package also carries that environment's flow states and, for Production, the managed
  flag, and no environment-variable values.
- Packages have been built this way instead of with `MakeSurveys.ps1` (procedure: SKILL.md "Per-environment
  packages"). The project's patch scripts (one for flows only, one for a canvas change) are listed in its memory; reuse
  them - each refuses if more than the intended entries differ and prints the package SHA-256.
- Canvas change: `Src\<Screen>.pa.yaml` and `Controls\<n>.json` (that screen's control tree) from the new DEV `.msapp`;
  `checksum.json` re-stamped with `ChecksumMaker.GetChecksum` from pac's `Microsoft.PowerPlatform.Formulas.Tools.dll`
  under pwsh 7 (Windows PowerShell 5.1 orders strings differently - don't use it). Entry names are stored with
  backslashes; Python's `zipfile` shows them with `/` on Windows - write `orig_filename` back.

## Packing locally
`pac solution pack --folder Root/Surveys --zipfile <path outside both repos> --packagetype Unmanaged` needs pac 2.4.1+
(YAML support). It leaves an untracked `canvasapps/inttrust_surveys_270d7/..._DocumentUri.msapp` - delete it, never
commit it. The solution repo is shared with other projects' folders (`Root/KnowledgeBaseApp`, `Root/RemoteWorkDays`,
`Root/dev_AccessRequests`): keep Surveys work inside `Root/Surveys`; anything pushed to `main` shows up as incoming
changes in the Git-bound environment, so push only on explicit request.

## Committing DEV to `Root/Surveys`
Solutions > Surveys > Source control > Commit in DEV (ask first); the integration's commits show as "PowerPlatform
User" and land as two commits plus a merge on `main`. A commit can stop on conflicts (`dataverse-git.md`). DEV's
environment-variable values are in git (`solution.env_var_values_in_git`) - check them before each commit.

## Import and after an import
- Customer imports: plain update (PROD managed, no stage-and-upgrade) with `--publish-changes`, through the project's
  import script (SKILL.md "Running an import": deploy account and environment from `pac org who`, SHA-256, version
  before and after, a log, PAC profile restored; where it lives: the project's memory).
- Importing re-activates the flows; a connection whose sign-in expired or was revoked leaves them Draft - check
  Connections first, then flow states. Expected: PROD all On except `RetrieveReports`; QA also
  `SurveysCreateAndSendReports` (v1) Off, as the `final` packages set them. PROD check afterwards (GET only, the
  project's post-import check script): version, flow states, the change present in the live flow definitions, env var
  values unchanged, and the V2 run-only share to the team in `environments.prod.app_users_teams` that holds it still
  present.
- A PROD fix is packaged with: the new package, a rollback export of the live version, and any SQL as
  preview-by-default scripts (skill pp-test-verify).
