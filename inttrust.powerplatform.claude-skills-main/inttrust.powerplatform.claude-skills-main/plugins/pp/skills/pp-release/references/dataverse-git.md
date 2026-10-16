# Shipping a change through Dataverse Git integration

For a solution bound to git through the maker portal's Source control (config: repo `kind: dataverse-git`,
`solution_folder`). Canvas app screens, App.Formulas, flows and solution metadata all travel this way. Values in
`<...>` come from the project config. How to drive the portal with a browser: `maker-portal-automation.md`.

## URLs (build them from the config)
- Source control pane: `https://make.powerapps.com/environments/<env_id>/solutions/<solution_id>/sourcecontrol`
- Studio (edit): `https://make.powerapps.com/e/<env_id>/canvas/?action=edit&app-id=%2Fproviders%2FMicrosoft.PowerApps%2Fapps%2F<app_id>`
  (no screen parameter - pick the screen in Tree view)
- Player: `https://apps.powerapps.com/play/e/<env_id>/a/<app_id>`
- App versions: `https://make.powerapps.com/environments/<env_id>/apps/<app_id>/versions`
- Flow: `https://make.powerautomate.com/environments/<env_id>/flows/<flow guid>/details` - the folder GUID under
  `modernflows/` is the flow id.
- Dataverse Web API: `<environments.<env>.url>/api/data/v9.2/`

## 0. Preconditions
1. **Nobody else holds editing control** in Studio ("someone else has editing control" in a Read-only session). Ask the
   user to close the other session; press Override only when the other sessions are known to be yours.
2. **Clone clean, on the branch, fetched**: `git status -sb`, `git pull --ff-only`.
3. **Pane shows Changes (0) and Conflicts (0).** Changes > 0 means the environment has edits git doesn't have - surface
   it to the user instead of resolving it yourself.
4. **Offline checks pass on the current tree** (skill pp-powerfx). A failure before your edit is pre-existing: report
   it and stop.

## 1. Commit through a PR (`commit_policy: pr`)
- Feature branch -> PR -> merge commit (`mergeStrategy: noFastForward`, `deleteSourceBranch: true`). Never push to
  `main`; never set `bypassPolicy`; stop on `conflicts` or `rejectedByPolicy`.
- Azure DevOps REST works with the stored git credential (Git Credential Manager): repo and PR endpoints return 200; the
  credential is git-scoped, so work-item and pipeline APIs return 401. Create:
  `POST <org>/<project>/_apis/git/repositories/<repo>/pullrequests?api-version=7.0` (sourceRefName, targetRefName,
  title, description); complete: `PATCH .../pullrequests/<id>` with `status: completed`,
  `lastMergeSourceCommit`, `completionOptions`. Completion is async - poll. Never echo any part of the credential
  (the auto-mode classifier blocks commands that do).
- If the git credential has no access, the same REST calls work from a browser tab of the maker account on the DevOps
  origin with `fetch(url, {credentials: 'include', headers: {Accept: 'application/json', 'X-TFS-FedAuthRedirect':
  'Suppress'}})`: create the branch (`POST refs`), the commit (`POST pushes`, `changeType: edit`, content taken from
  `git show <commit>:<path>`), the PR, the completion. Large payloads: gzip + base64 and inflate in the page with
  `DecompressionStream`. Verify each blob id against `git rev-parse <commit>:<path>`. Commits are then authored by the
  browser account - get the user's OK.
- Line endings: the working tree is CRLF under `core.autocrlf=true`. A `git diff --stat` that shows a whole file
  changed means the line endings were rewritten - redo the edit.
- The platform creates `tmp/main-<hash>` branches on every pull cycle; ignore them and never select one.

## 2. Pull into the environment
- **Flow-only or solution-metadata change:** Check for updates -> Pull.
- **Canvas `Src/*.pa.yaml` change: it never shows under Updates on its own** (the pane reports "completed
  successfully" with Updates (0) forever - that means the check ran, not that anything changed). Run the full cycle:
  1. Git connection -> Disconnect solution from Git -> Continue (needs Changes (0); ~1 min; reload to see the result).
  2. Connect: org, project and repo are remembered; pick Branch exactly `<branch>` from the options; the Git folder box
     holds real prefilled text (`<solution_folder>`) - replace, don't append. Some tenants show "Enable this solution"
     first; click it, then Connect.
  3. Check for updates. Every component appears as a `Create` change first - **never press Commit now**: it would write
     the environment over your PR. They then resolve into Conflicts.
  4. Conflicts -> select all -> Accept incoming changes -> Ok, continue. The pane explains itself: solution and canvas
     components can show as conflicts even when unchanged.
  5. Pull, reloading between presses, until Updates is 0. One press can apply everything; a transient "Connect this
     solution to Git" state mid-pull is not a disconnection. The publisher row may stay as Updates (1) - a no-op.
  The whole cycle takes 5-9 minutes. Expected rows for a canvas change: solution, publisher, canvas app, plus any
  changed flows and env var definitions. Deletions or components you didn't touch -> stop and report.
- **Right after a fresh pane Commit** the app is re-baselined, and a Src PR that also bumps `solution.yml` (so the
  solution row is in the pull) can pull with a plain Check for updates.
- **"component ... of type 300 / 29 is not declared in the solution file as a root component"** = a pull without the
  solution row -> run the full cycle.
- **Web API `RefreshChangesFromGit` / `PullChangesFromGit`** (`{SolutionUniqueName, AdditionalParameters:
  {DeleteDeletedComponents: true}}`) is proven for component deletions only - not for canvas Src or flow updates, which
  it silently skips or fails.
- **Delete git-first**: a component deleted only in the environment comes back on the next Pull.
- Things that look like fixes and are not: bumping `AppVersion` in `canvasapp.yml` (not a source file), waiting, or
  closing the Studio editing lock.
- **Parallel sessions:** finish every merge before anyone pulls; one pull covers all of them. A PR merged while the
  pane already shows Conflicts is picked up by pressing Check for updates again.
- The auto-mode classifier may block the Disconnect or reconnect clicks: get the user's explicit go (naming org /
  project / repo / branch / folder) before disconnecting, or the solution can be left disconnected.

## 3. Publish and verify
- **A Pull marks the version "Live" but players keep the last Studio Publish.** Publish from Studio; publishing an
  unchanged version is a no-op, so make a trivial edit first (a `// published <date> (PRs <n>)` comment at the end of a
  screen's `Fill`), Save (ctrl+s), Publish -> "Publish this version". Then mirror the comment into git by a small PR so
  git and the environment carry the same formula. Publishing is the lead's call unless granted for this change set.
- **App checker -> Formulas (0)** after every pull (skill pp-powerfx), before any runtime test. Also check Tree view
  for red error badges, and select each changed control: the Properties pane header names its type and shows live
  values - the proof that the pull landed. Before concluding a pull did not land, search Tree view for the new control
  and Ctrl+F in App.Formulas.
- While testing in Studio, a dirtied draft is discarded with Cancel - never Save changes.
- **Verify what users run:** Studio Play runs the current saved version; the web player caches - press its "old
  version - Refresh" banner and prove the package from a flow run's trigger payload. The Versions tab shows which
  version is Live; read it after every pull.
- **After a Studio Publish** the pane shows Changes (1) for the canvas app (by SYSTEM): the environment is ahead of
  git. Close it out with a pane Commit (the lead's call) or by re-applying the same edit in git.
- **A pane Commit commits every listed row and writes the environment over the branch.** It has reverted PRs merged
  after the last pull, and can reset a language label of the solution display name. Before committing, read the Changes
  tab and diff origin against the last pulled commit; afterwards check `solution.yml` and re-apply anything lost.
- **Committing the environment's state** (Solutions > solution > Source control > Commit, for example after an
  import): read Changes, Updates and Conflicts first; Updates or Conflicts > 0 -> stop and ask. The commit also
  carries the environment's env var values and its deletions into git - check them against
  `solution.env_var_values_in_git` first. The commit itself can be split and stop on conflicts (solution, canvas app,
  env var definitions, attributes); with the lead's OK, "Keep current changes" keeps the environment's version, then
  Commit again. It can land as two commits plus a merge commit on the branch; check `solution.yml` `Version:` there
  afterwards.
- **`Controls/*.json` and `_EditorState` are not source.** Controls are refreshed only by a pane Commit and can lag
  `Src`; a pull with no Src delta can re-create the app from stale Controls. Never edit them to effect a change.
- **Flows after every pull:** check each flow's state; git-authored flows arrive Off; share app-called flows with the
  app users' team (skill pp-flows).
- **App settings that are not formulas** (App Insights connection string) live only in `Properties.json`: change them
  in Studio (App -> Properties), Save, Publish, then pane Commit.
- Close out "published and committed": environment content = branch content.

## 4. Hand back
Leave one browser tab on the changed screen in Studio and close the tabs you opened (a Studio tab with a pending
"Leave site?" dialog can't be closed by script - say so). Report in the user's terms: what changed, the PR link, how it
was verified, what is left.
