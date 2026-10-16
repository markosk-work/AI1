---
name: pp-release
description: How changes move from git to DEV, QA and PROD for Power Platform solutions (Dataverse Git integration or unpacked solutions, deployment scripts, SQL databases) - who may do what (DEV by default, PROD only on explicit instruction and by the PROD owner), merged vs pulled vs published vs what users actually run, what a PROD import carries, versioning, environment-variable values per environment, grants for new procedures, flow state and sharing after every import or pull, rollback design, and the project's own release scripts. Includes profiles for Telework, Gaslog Briefing Desk (Export-Import-Solution.ps1) and Surveys (MakeSurveys.ps1). Use it whenever you export, import, pull, publish, promote, bump a solution version, hand PROD steps to the owner, or plan a release or rollback, in a project with a .claude/pp-project.yaml.
---

# Releasing without surprises

## Before any release step

1. **Load the project config** (skill `pp-project-config`): environments, roles, `rules` (default target, PROD rule,
   days to avoid, import days), repos and release scripts, and your local accounts and PAC profiles.
2. **State the target** (environment name and URL) and the authority for it. DEV is the default. PROD needs an explicit
   instruction for that specific action, and an old or DEV approval never extends to it. Features that need an admin
   approval stay in draft until it exists.
3. **Prove the identity** before any tenant action: the signed-in browser account from page evidence, the PAC profile
   from `pac auth who` - they are independent, and neither proves the other. Always pass `--environment`; never rely on
   whichever PAC profile happens to be active.
4. **Respect ownership.** The PROD database, PROD imports and PROD connection mapping belong to the PROD owner (config
   `roles.prod_owner`); prepare the steps for them rather than doing them. Avoid the days in `rules.no_prod_changes_on`.

## Four stages people confuse

1. **Merged is not shipped.** Canvas apps and flows run from Dataverse; git is a mirror. A merged PR reaches an
   environment only through a pull (source-control pane) or an import.
2. **Pulled is not published.** A pull marks the canvas version "Live", but players keep the last Studio Publish.
   Publishing an unchanged version is a no-op - make a trivial edit first. Publishing is the lead's call unless they
   granted it for this change set.
3. **Published is not what users run.** Players cache the package; the "old version - Refresh" banner must be used.
   Prove which package ran from a flow run's trigger payload, or use Studio Play.
4. **Close out "published and committed"**: environment content equal to git main, and git equal to the environment.

## Before a release

- **List everything the target does not have yet.** A PROD import carries every change since the last PROD build, not
  just yours - flows, env var definitions, procs the flows call, app settings. Restore any DEV-only setting first (for
  example an App Insights connection string that was cleared in DEV).
- **Version strictly higher** than every target environment; the same or lower only for an explicit rollback. When an
  export bumps the version in DEV, mirror it into `solution.yml`.
- **Environment-variable values per environment**, never in git or in the main solution. Values created through the
  Dataverse Web API land outside the solution - that is intended.
- **Procs and grants first.** Every proc a flow calls must exist on the target database, with the grants its
  predecessor has, before the import - or the flow fails activation.
- **Connections:** know which connection references need a connection on the target and who creates it (connections
  that need a password are created by the lead or the owner, never by Claude).
- **When the repo lags live**, build from a dated live export of the target solution, name packages by version, phase
  and switch state (`..._1_0_0_4_B1_callers_toggle-no.zip`), and keep the original for rollback.
- **Per-environment packages** (each target's package carries its own settings, such as the canvas app's App Insights
  key): build the next one from that target's last imported package, not from a fresh export. Replace only the changed
  entries, taken from the new DEV build - flow JSON under `Workflows/`, or inside the `.msapp` the changed
  `Src/*.pa.yaml` and its `Controls/<n>.json` with `checksum.json` re-stamped by pac's own checksum code - and
  `<Version>` in `solution.xml`. Every other entry (`Properties.json`, `customizations.xml`, unchanged flows) stays
  byte-identical, with the same names, order and dates. Prove first that the checksum code reproduces the old
  `checksum.json`; afterwards verify independently that exactly those entries changed.

## Running an import
Script it so it refuses: `pac org who --environment <url>` must name the expected account and environment, the
package's SHA-256 must equal the one recorded at build, and `pac solution list` must show the new version afterwards.
Log account, hash, versions before and after, and times. Select the deploy PAC profile inside the script and restore
the default one in a `finally`.

## After every import or pull

- App checker -> Formulas (0) in Studio.
- **Every flow's state** (`workflows?$filter=category eq 5`, or the solution's flow list): imports and pulls have left
  flows Off or Draft, and git-authored flows arrive Off; a package can carry its own flow states, so expect the
  package's, not the ones the target had. Turn on as the connection owner.
- **Sharing:** app-called flows shared Read with the app users' team(s) on that environment; imports can reset
  run-only sharing - read it back (`RetrieveSharedPrincipalsAndAccess(Target=@t)?@t={'@odata.id':'workflows(<id>)'}`).
- The solution display name (a pane Commit can reset one language label), env var values, and the player after Refresh.
- An unmanaged "Customized" layer on a managed component (PROD) means a managed import will not override it - report it.

## Rollback

- **Design it before the change**: the quickest route (re-bind a connection reference, set the switch to `false`) and
  the full route (revert the PR, delete git-first, owner drops the proc).
- A managed PROD cannot go back a version: fix forward. The lead prefers fixing forward over rolling back anything
  that would lose work.
- **Keep the old path until the new one has survived a peak** (for example an old connection reference kept until the
  new setup has passed a Thursday).
- **Delete git-first.** A pull re-creates anything that was deleted only in the environment.

## Handing PROD steps to the PROD owner

One page, in the owner's `language` from `people:` (English technical terms are fine), numbered steps only: what to
import or run, in which order, which connections to map, which switch values to set, and what to check afterwards
(flow states, sharing, one smoke test). Quote the exact object names; no background story.

## Recording a release
Commit exactly the files that were imported, each with its SHA-256 and how it was built. When the repo's folder
convention expects a file that does not exist (a managed Dataverse export when the PROD package was built from the
previous one), say so in the release notes under "where the folder convention is not followed" - never fill the slot
with a stand-in.

## Release machinery

Build pipelines only after the platform and the identities are decided: a release pipeline built ahead of both was
never used and had to be deleted. Until then, the project's own scripts (profile) are the process - preserve them.

## Shipping through Dataverse Git
For repos with `kind: dataverse-git`, follow `references/dataverse-git.md`: preconditions, the PR, the pull cycle
(disconnect / reconnect for canvas changes), publish, verification and hand-back. Driving Studio, the source-control
pane and the player from a browser: `references/maker-portal-automation.md`.

## Profiles
- `references/telework.md` - Telework's binding, display name, typical conflicts, PROD import by the owner, PROD
  grants, Thursday rule.
- `references/gaslog.md` - `Export-Import-Solution.ps1`, carrier packages, DEV imports, adding components.
- `references/surveys.md` - `MakeSurveys.ps1`, release folders and notes, patched QA / PROD packages, Source control
  commits, customer environments and their import checks.
