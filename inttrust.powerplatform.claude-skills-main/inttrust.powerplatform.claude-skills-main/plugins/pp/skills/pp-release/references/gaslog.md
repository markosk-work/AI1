# Release profile: Gaslog Briefing Desk

## The owner's release script
`Gaslog-Briefing-Desk-Deployment/PPSolutionDeploymentScript/BriefingDesk/Export-Import-Solution.ps1`, with thin
wrappers `Export-Import-Solution - UAT.ps1` and `... - Production.ps1` that hold the org URLs and env var values.

- `-TargetEnvironment` is mandatory (`ValidateSet("QA","Production")`); `-SourceEnvironmentUrl` only for QA; one
  `-EnvVar<Name>` parameter per environment variable (numbers regex-validated; an omitted one leaves the target's value
  unchanged); `-UseDeviceCode` for device-code sign-in.
- **Build once, promote the same artifact.** The QA run publishes DEV, reads the version from a temporary managed
  export, increments the 4th segment, writes it back to DEV with `pac solution online-version`, and exports
  `<Solution>_managed_<ver>.zip`. The Production run exports nothing: it takes the newest `_managed_*.zip` in the output
  folder, or fails with "Run with -TargetEnvironment QA first".
- Managed in QA and Production. Values go into a temporary `deployment-settings.json` (`--settings-file`, deleted after
  the import); `--activate-plugins true`.
- Named PAC profiles (`source-env`, `target-env-qa`, `target-env-production`), reused if present. QA and Production are
  in the customer's tenant: device code in a private browser window.
- `Set-StrictMode -Version Latest`, `$ErrorActionPreference = "Stop"`, `$LASTEXITCODE` checked after every pac call;
  colour-coded console output only.
- Every exported managed zip is committed to the deployment repo (`GaslogInterviewsSolution_Output/`) - that folder is
  the release record.
- Known issue: a bare `return` makes the script's App Insights block unreachable. Report it; don't rely on that step.
- A new env var gets a parameter in the same pattern, and its value stays out of the main solution so QA/Prod keep the
  default until the script passes the value.

## DEV work on a feature
- The solution repo is in Dataverse Git-integration format and is committed from the maker portal's Source control
  (ask first). Never `pac solution unpack` over it. Check whether DEV is ahead of the repo before building; sync first.
- Build and import small carrier solutions in phases (child flows first, then callers, then switch on), each named by
  version, phase and switch state; build scripts and packages live in `paths.work_outside_repos`, not in the owner's
  repos.
- DEV imports: `pac solution import --environment <DEV url> --path <zip> --async --max-async-wait-time 60
  --activate-plugins`, no `--publish-changes` (DEV is shared). Check flow states after each import; `pac` cannot turn
  flows on.
- A broken connection behind a connection reference can be re-bound at import with a settings file.
- Finishing: add the new flows (type 29) and env var definitions (type 380) to the main solution with
  `pac solution add-solution-component`, leave env var values out, then Source control commit (ask), then clean up the
  carrier and POC components.
- Do not deploy the main solution to QA/Prod until the SQL migration exists there and every component is in the solution.
