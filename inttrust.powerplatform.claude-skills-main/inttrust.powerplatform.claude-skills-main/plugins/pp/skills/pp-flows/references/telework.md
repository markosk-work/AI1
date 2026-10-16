# Flow profile: Telework

Flows live in the solution repo under `Root/RemoteWorkDays/modernflows/<workflow-guid>/<Name>-<GUID>.json`; the folder
GUID is the flow id (`make.powerautomate.com/environments/<env>/flows/<guid>/details`). The full flow inventory with
UDFs, procs and response fields is in the project document `Architecture.md` (config `project.docs`).

## Which flows are the reference
Designer-made flows (imported 9376590 or pane-committed) are the owner's style. Two were authored in git by an
assistant and are NOT references: `TeleworkGetLeaves` (92bbf21; uses `actions()`, `json(concat(...))`) and
`TeleworkNotificationUnusedRemoteDays` (1923bbd; uses `json('[]')`, `union()`, descriptive action names). For a new
scheduled mail, copy `TeleworkNotificationRegistration` (`d7745bf8`) and take only the switch and the time zone from
the unused-days reminder.

## Adding a flow in git (what 1923bbd had to contain)
`Root/RemoteWorkDays/modernflows/<guid>/<Name>-<GUID>.json` and `.../<guid>/workflow.yml`; its lines in
`solutions/RemoteWorkDays/rootcomponents.yml` (type 29) and `solutioncomponents.yml`; the switch's
`environmentvariabledefinitions/<name>/environmentvariabledefinition.yml` (definition only, no value); a `solution.yml`
version bump. It arrives Off after the pull; the switch value is set per environment.

## Structure
- Original style: success and error branches directly after the SQL action, each ending in its own Response with
  identical schemas; parse errors and data errors get their own branch (`..._with_parsing_error` returns
  "Invalid Input", `..._with_data_error`). Error branches end in `Terminate` with status Succeeded.
- Some newer flows use Try/Catch scopes. Copy the sibling you extend. For the leaves flow the lead asked for branches,
  not scopes ("handle the success or the error of the actual actions"), so prefer branches for a new flow unless its
  nearest sibling uses scopes. A multi-step flow may set an error variable after the chain that names the failed step.
- Wire names: `text` (search, update employee), `text_4` (insert workday), `text_2` (remove workday). Read the trigger
  before changing a call.
- Pass tables from the app as JSON and convert inside the flow; filter an external API call itself (headers such as
  `PreferredUsernamesList`, `FromDate`, `ToDate`) instead of fetching everything and filtering later.

## Naming
Mixed and historical - match the family you extend: `DBGetHolidays`, `DbGetWorkDaysWithCriteria`,
`TeleworkDBGetRoles`, `TeleworkGetEmployeesWithCriteria`, `TeleworkNotification<What>`, `TeleworkExport<What>`.

## Scheduled flows and timing
- Telework's scheduled procs take no `@User` (for example `GetEmployeesToNotify`); there is no systemic user.
- The weekly reminder's Recurrence has no `timeZone`, so it runs in UTC (Thursday 07:00 UTC). New schedules set
  `GTB Standard Time` explicitly.
- Bookings for next week close on Thursday 18:00 Athens (`dbo.GetFirstAllowedRegistrationDate`). A list of "next week"
  sent before Thursday evening is partial - say so, or send this week's (final) list instead.
- App starts peak on Thursday morning after the reminder (the 2026-09-24 incident): keep new schedules out of
  Thursday 07:00-08:30 UTC.

## Environment routing and mail
- `inttrust_TeleworkAppEnvironment`: "Production" unlocks real behaviour. The weekly reminder sends only inside
  `Condition_for_Production_ONLY`; outside Production the newer reminder mails only the tester's own address (embedded
  in its test branch - a coworker changes it to theirs).
- Mails are signed "Human Resources Department"; new wording copies the existing mails, and the lead says who signs it
  off.
- Feature switches (`inttrust_TeleworkLeavesEnabled`, `inttrust_TeleworkNotificationUnusedRemoteDaysEnabled`): String,
  default `'false'`, value per environment, the whole flow wrapped in the condition. The lead's rule for every new
  feature: a separate plug-and-play flow with such a switch.
- Mail: SMTP `SendEmailV3` from `ergani@inttrust.gr`, importance High, recipients joined with `;`.
- Reminder e-mails are generic, not personal: one mail per team leader, "Dear Team", the week range, no names or
  counts; people without a team leader get their own mail. (Reports that list bookings name people, of course - the
  rule is for reminders.)
- Scheduled reminders run Thursday (registration peak): keep new schedules away from the morning burst.

## Connections
- PROD flows are owned by the PROD service account and historically shared ONE SQL connection = one throttle bucket.
  The plan in force is a split into a small number of connections (read / read / write) created by the lead, not one
  per flow. Repointing a flow changes only its connection block - prove the diff is limited to it.
- End users are on standard licences: no premium connector in the app; flows are the only SQL gateway.

## Sharing
- DEV: app flows are shared Read with the team in `environments.dev.app_users_team`. PROD: with both teams in
  `environments.prod.app_users_teams`. A flow added after the app was shared is not shared automatically - share it
  before enabling the feature.

## Known facts
- The Leave API identifies people by UPN, not mailbox (`vguser@` vs `vgiourousis@`): send UPNs, map results back to
  mailboxes in the flow.
- `TeleworkUpdateEmployee`'s SQL-error response does not run when the SQL action is Skipped - inspect the error path
  before copying it.
- The simple CSV export replaces every comma with a semicolon - do not reuse it for fields with commas or quotes.
- A null CC is accepted by the SMTP connector (probed).
