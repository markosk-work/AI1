---
name: pp-test-verify
description: How to test and prove a Power Platform change (canvas app, Power Automate flow, SQL) before calling it done - e-mail safety with a test allowlist, rolled-back persona tests of stored procedures through @User, dry runs against temp-table copies, fixture / verify / cleanup scripts with markers, migration pre-check / apply / rollback, preview-then-apply data fixes, flow tests (switch-off test, throwaway probe flows, designer manual runs), runtime checks as a plain user, driving the app in Claude in Chrome on Windows without taking the user's focus, and evidence that the live app really changed (Studio Play vs player cache, flow-run payloads, database rows), with PARTIAL reporting when a check is blocked. Use it whenever you test, verify, UAT, seed fixtures, backfill data, run a migration, or are about to report a Power Apps, Power Automate or SQL change as done, in a project with a .claude/pp-project.yaml.
---

# Testing and proving a change

Load the project config first (skill `pp-project-config`): `tests.*`, `databases.*`, `safety.test_email_allowlist`
and the accounts in your local file.

## E-mail safety comes first

- During development and tests, mail may reach only the mailboxes in `safety.test_email_allowlist`. DEV databases
  often hold real addresses (employees, stations, customers), so a flow in "Production" mode or a wrong recipient
  mails real people.
- Before any test that can send mail, name the recipients it will produce and confirm them. Run notification and
  export flows only as part of an agreed test, never during an investigation.
- Check the environment switch (`solution.environment_switch_var`) is not "Production" in DEV before a mail test.

## SQL

- **Rolled-back persona tests.** A proc takes identity from `@User`, not from the SQL login, so `EXEC` it with each
  persona's Entra id inside `BEGIN TRAN ... ROLLBACK`. Snapshot the touched tables (`COUNT(*)` + `CHECKSUM_AGG`) before
  and after: any difference means a test leaked. Find personas by role in the data rather than hard-coding people, and
  pick a date range nobody has bookings in. `EXEC` parameters must be variables or literals, not expressions.
- A project harness (`tests.sql_harness`) is the reusable form: one transaction per case, always rolled back, expected
  results = the behaviour the team agreed, SKIP (not FAIL) when a persona is missing, a baseline mode that runs V1 beside
  V2, exit codes 0 pass / 1 fail / 2 data changed. Re-run it after every change to the procs it covers.
- **A test matrix is a decision document.** When replacing V1 with V2, list every case with the V1 and V2 result and
  mark CHANGED - it exposes regressions on real data before anything is repointed.
- **Dry-run new logic before the object exists:** run the new body as a rolled-back batch, or against `#Table` copies
  (`[dbo].[X]` -> `#X`), and compare with the live output for real personas, including an unknown and a terminated
  user. Record timing and payload size.
- **Fixtures** (for app or flow tests): a DEV-only guard that throws elsewhere, a marker value on every row, synthetic
  users with fixed ids, dates chosen so no scheduled flow fires, recipients only from the allowlist; a read-only verify
  script; a cleanup script that deletes by marker and removes synthetic users only when nothing references them.
- **Migrations:** a read-only pre-check (identity, permissions, blockers such as duplicates that would fail a unique
  index), an idempotent migration (`OBJECT_ID` / `COL_LENGTH` guards - in the migration only, never in the owner's
  master DDL), and a rollback that restores the captured live bodies.
- **Data fixes (backfills):** take a rollback export first; the script previews by default and ends in ROLLBACK; save
  the preview output; the apply script checks server and database, embeds the previewed set, throws if live differs,
  verifies counts and values inside the transaction, and reports what is still unfixed. Indexes:
  `IF NOT EXISTS ... WITH (ONLINE = ON)`.

## Flows

- **T0 - switch at its default:** with a feature switch at `'false'`, nothing runs and nothing is sent.
- **Throwaway probe flows** (name them `ZZ TEMP <what> - delete me`, outside the solution) to answer a platform
  question - does the connector accept a null CC, does a schedule fire - then turn them off and have them deleted.
  Turning on a flow and granting access can need the user's explicit go.
- **Designer "Test -> Manually"** runs of Power Apps V2 flows carry `x-ms-user-id`, so a flow can be exercised without
  the app. Read the run's trigger payload and each action's outputs.
- **Failure injection:** with a dependency off, the app should show exactly one error, not a cascade.

## Runtime

- **Test as a plain user too.** Testing only as a privileged account (owner, admin, manager) hides whole branches.
- **Prove which package ran.** Players cache the app: use Studio Play (it runs the current version), or refresh the
  player (after a publish it shows "You're using an old version" - Refresh; if "Leave site?" blocks that, open the
  player in a new tab with a cache-busting query such as `&v=<version>`) and confirm through a flow run's trigger
  payload. Don't judge from what the screen looks like.
- **A new app version asks for consent** ("Allow <app> to access your data?", the app's own connections). Accept it for
  the test account only when the user allows it; it covers no other consent or OAuth dialog.
- **Evidence is data, not screenshots.** Prove a UI test from what it wrote and started - database rows, flow run
  history - and keep screenshots for failures.
- **Restore everything a test touched** (bookings, records, flags) and say so. If reaching a case would mean deleting
  real data, leave it untested and say that instead.
- **Verify, don't assume.** Identifiers (UPN vs mailbox), what an API returns, which database a connection points at,
  whether a proc is deployed - check them live. Don't write a fix for something nobody has checked; report findings
  before implementing.

## Browser (Claude in Chrome on Windows)

- Chrome freezes hidden and background tabs: screenshots and clicks on them time out, and page scripts often do too.
  The extension can only drive the tabs in its own tab group, which lives in one window.
- Instead of asking the user to place Chrome side by side: keep one tab per window and reuse it by navigating, so the
  tab you need is its window's active tab. To show it, set `document.title = 'CLAUDE-<something>'` (again after load -
  Power Apps overwrites it) and run `& "<this skill's folder>\scripts\Show-ChromeTab.ps1" -Marker 'CLAUDE-<something>'`
  in-process (not `pwsh -File`): it raises that window without taking the user's keyboard focus (SWP_NOACTIVATE), on a
  secondary monitor if one is connected.
- Never switch tabs with keystrokes or UI Automation select - both activate Chrome and take the user's focus. Creating
  or navigating a tab can also bring Chrome to the front: check the foreground window afterwards.
- Closing or navigating away from a player tab can raise "Leave site?", which blocks the extension (closing the tab then
  hangs): avoid it, or ask the user to click Leave. Studio tabs: remove the iframes first (pp-release
  `references/maker-portal-automation.md`, which also has the Studio and maker-portal mechanics).

## Access

- Azure SQL firewalls often reject home networks - database work may need the office network or VPN; changing firewall
  rules is the owner's call.
- SQL tokens and one-batch SQL runs: skill pp-sql `scripts/Get-SqlToken.ps1` and `scripts/Invoke-Sql.ps1`, with the
  values from the config. Never print a token, never type a password; the user enters device codes. Delete token files
  when done.

## Done means

- [ ] Checked live (Studio Play or refreshed player, flow run payload, database row) - as a plain user where roles matter.
- [ ] App checker -> Formulas (0); every flow On; new flows shared.
- [ ] Test data restored; probe flows off / deleted; tokens deleted; no mail outside the allowlist.
- [ ] Report: what changed, the evidence, what is still open. **PARTIAL** when any live check was blocked, even if
      packaging and offline checks passed. Keep deployment proof separate from the user's own acceptance testing.
