---
name: pp-prod-diagnosis
description: Read-only method for diagnosing production problems in Power Apps / Power Automate / SQL apps - "the app is slow", "not responsive", "users get errors", "someone is blocked", a wall of error toasts, a report that won't send - by separating database time from SQL-connector time, reading flow run history (flowruns) and App Insights telemetry, spotting error amplification, throttling and swallowed failures, ruling recent changes in or out with evidence, and naming who has to act. Use it whenever a PROD or customer incident, outage, slowness, permission or access complaint is reported for a Power Platform app, before changing anything - even when the fix looks obvious.
---

# Diagnosing production

**Read-only first.** No fixes, restarts, re-imports or data changes until the cause is shown and the lead says so.
Load the project config (skill `pp-project-config`) for environments, telemetry resources, and which of your accounts
can read what; verify each identity from evidence before using it.

## 1. Pin down the symptom
Who is affected (one user, a group, everyone), since when, which screen or button, the exact error text. A timeline
beats a description: first bad time, last good time, what else happened then (a scheduled reminder, a release, a
password change, a platform update).

## 2. Separate database time from connector time
- Database side: `sys.dm_exec_procedure_stats` (last_execution_time, last/max_elapsed_time), Query Store, CPU in
  `sys.resource_stats` / `sys.dm_db_resource_stats`. For a database you cannot reach, ask its owner for these numbers.
- Flow side: action durations and outputs in the run history.
- Compare the two: a proc that runs in milliseconds while the SQL action takes a minute means the delay is in the SQL
  connector path, not the database. Calls from different app starts released together point to one shared queue.
- Throttling: `429 Rate limit is exceeded` is per connection and based on time spent, so one connection shared by every
  user is one bucket. The message is in `body.message`; flows that read only `error.message` show a generic fallback.
- A control action with no connector (Compose + Response) that stays fast shows Power Automate itself is fine.
- `x-ms-apihub-cached-response: true` appears on every SQL connector response and means nothing.

## 3. Read the telemetry
- **Tokens for reading:** the saved SQL sign-in can be redeemed for other resources without touching its cache
  (pp-sql `scripts/Get-SqlToken.ps1 -Scope '<resource>//.default'`): the PROD Dataverse org, `https://service.flow.microsoft.com//.default`,
  `https://service.powerapps.com//.default`. Use it read-only, and only where that account is allowed to read.
- An empty Dataverse result can mean "no read permission", not "no rows": `flowruns` and `connectionreferences` of
  flows owned by another account come back empty with no error. Check who you are reading as before concluding.
- **Flow runs:** the Dataverse table `flowruns` on the environment (status, errorcode, duration, starttime; 28-day TTL;
  rows appear minutes after a run). `errorcode Terminated` with status Succeeded = an error branch ran. Action detail
  via the flow runs API (`.../flows/<id>/runs/<run>/actions`, then each action's outputs link).
- **App Insights:** `traces` from `App.OnError` / IfError handlers (Kind, Message, Source, Screen, Observed),
  `customEvents` DataRequestsSummary (request count, failures, latency) and SessionLoadSummary (time to full load).
  Compute rates per 1k page views and compare with a baseline window; know the chronic noise first. Cross-app KQL works
  with `union app('A').traces, app('B').traces`. Reserved words that bite: `last`, `views`.
- **Error amplification:** thousands of identical traces from a few users usually mean one failed call stored as an
  error value (`Set(g, Udf())` in OnStart) and re-raised by every control that reads it - one fault, not thousands.

## 4. Rule things in or out with evidence
- Your own recent changes: when they happened vs when the errors started, and whether the failing path touches them.
- Swallowed failures: `IsBlankOrError` / `IfError(..., Blank())` around a call hides the real failure and produces
  wrong data later. Look for where a value was fetched once and saved without a check.
- Permissions: `0x80048306 ... does not have ReadAccess ... Process` = the user cannot run a flow owned by someone else
  (missing sharing or a role such as App Opener). Compare the failing users' roles and team memberships with working ones.
- Identity: `AADSTS50053` (account locked), `AADSTS50173` (grant revoked by a password change - connections go into
  error), devices or Conditional Access for "register your device" / empty app lists.
- Platform: status pages list only major outages and Service health may be filtered by your role - "nothing listed" is
  not evidence. Check public reports, and have a tenant admin open a Microsoft case when the evidence points there.

## 5. Name who acts, and report
- Say whose problem it is: ours (code, flow, config), the DB or PROD owner's, the customer's admins, a partner's (a
  lockout on a partner's shared account is the partner's to fix; InTTrust confirms the diagnosis), or Microsoft's.
- Report in this order: what users see; the cause with the evidence (numbers, timestamps, run ids); what was ruled
  out and how; who has to act and what exactly; the next step. Label estimates as estimates, keep it short, and mark
  what could not be checked.
