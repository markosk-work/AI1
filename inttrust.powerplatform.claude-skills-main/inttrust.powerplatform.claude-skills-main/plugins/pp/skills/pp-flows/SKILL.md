---
name: pp-flows
description: House conventions for Power Automate cloud flows in Power Platform solutions - Power Apps V2 triggers with JSON text input, caller identity from the x-ms-user-id header, the {data, error} text response contract, catch and error-text expressions, designer-default action names, stored-procedure calls, expressions to use and avoid, Production-vs-test routing, feature switches, schedules, child flows, e-mail and Adobe Sign steps, what must be checked after a flow change lands (state, sharing), and how to start an app-called flow without the app (Power Apps gateway call, inputs from run history, bulk re-run limits). Includes codebase profiles for Telework, Gaslog Briefing Desk and Surveys. Use it whenever you create, edit, review, repoint, debug or re-run a flow or its definition (modernflows/*.json, workflow.yml), add an e-mail, notification or reminder flow, resend what a flow failed to send, or wire a stored procedure into a flow, in a project with a .claude/pp-project.yaml.
---

# Flows the way this solution already builds them

## Before you touch anything

1. **Load the project config** (skill `pp-project-config`): solution, environments, `environment_switch_var`,
   `rules.new_feature`, `rules.mail_outside_production`, and `project.style_profile`.
2. **Read the profile** for this codebase - `references/telework.md`, `references/gaslog.md` or
   `references/surveys.md`. Flow structure differs per codebase; copy the one you are in.
3. **Open the nearest sibling flow** in the same solution and copy it action by action. Read its trigger and
   `Parse_JSON` first: internal input names are designer defaults (`text`, `text_2`, `text_4`) and differ from the
   labels you see. **Prefer a sibling the owner built in the designer.** Flows authored in git by an assistant (the
   profile lists them) are not the reference: when the nearest one by function is such a flow, take the serialisation
   and shapes from a designer-made sibling and only the behaviour (switch, schedule) from the other.
4. **Don't overwrite someone else's designer edits.** Owners edit flows in DEV and commit them from the source-control
   pane. Fetch first (if you cannot, note the `FETCH_HEAD` date and treat the result as provisional), let them finish,
   and rebase your PR on their commit.
5. **Write flow JSON the way the designer serialises it.** Then a later pane Commit writes back the same text instead
   of churning the file. When regenerating `definition.actions` with a script: keep key order, 2-space indent, no
   trailing newline, and existing `operationMetadataId`s (new actions don't need one); assert that only the intended
   actions changed.
   - **Line endings:** files the pane committed are CRLF in the index (`git ls-files --eol` shows `i/crlf`), and edits
     to them stay CRLF. A NEW file added with `core.autocrlf=true` is stored as LF. Add new flow files with
     `git -c core.autocrlf=false add <file>` from a CRLF working copy so they match.
   - **A new flow in a Dataverse-git solution is more than its JSON:** the flow folder, the solution's root-component
     and solution-component entries, any env var definition, and a `solution.yml` version bump (profile lists the files).
6. **Other layers:** a new or changed proc -> skill `pp-sql` (with the SP approver's OK); shipping, versioning and the
   PROD hand-off -> `pp-release`; a new switch -> add it to `solution.feature_switch_vars` in the project config.

## The contract every app-called flow keeps

- **Trigger:** Power Apps V2 with, usually, one text input carrying JSON. Input descriptions read "Please enter X".
- **Caller:** `@triggerOutputs()?['headers']?['x-ms-user-id']` goes to the stored procedure's `@User`. The payload
  names the target; never accept a client-editable `User` field as the actor. Child flows receive the caller as an
  explicit `User` input.

Scheduled flows have no caller: the profile says what they pass instead (a systemic user, or procs that take no user).
They return nothing to an app, so a failure shows only as a failed run - no `{data, error}` Response, and no sharing
with app users is needed.
- **Response:** text `data` + text `error` (other field names only where the sibling uses them). Every Response action
  of the same status has an identical schema.
- **A green run proves nothing.** Business failures come back as HTTP 200 with `error` filled, and an error branch can
  end in `Terminate` with status Succeeded. The app wrapper checks `error` before `data`.
- **Error text for a single action:**

```
@coalesce(outputs('Execute_stored_procedure_(V2)')?['body']?['error']?['innerError']?['error']?['message'],
          outputs('Execute_stored_procedure_(V2)')?['body']?['error']?['message'],
          'Unhandled SQL/connector error')
```

  A throttled call (429) carries its text in `body.message`, which this expression does not read - it then surfaces
  as the fallback. When you touch an error branch, consider reading `body.message` too.

## Names and calls

- Keep designer default action names: `Execute_stored_procedure_(V2)`, `Get_rows_(V2)`, `Parse_JSON`, `Select`,
  `Filter_array`, `Apply_to_each`, `Respond_to_a_Power_App_or_flow`, `Run_a_Child_Flow`. Two actions of the same type
  get the default plus a suffix (`Parse_JSON_EmployeesToNotify`, `Parse_JSON_ModeratorsToNotify`). Other renames use
  Title_Case with underscores (`Try_Scope`, `Condition_for_Production_ONLY`, `Check_if_eSignatureID_exists`). Don't
  invent descriptive names such as `Compose_UpnToEmail`.
- Flow names follow the family in the solution (profile): `DB<Verb><Entity>` for SQL-backed flows, `<App>Environment`,
  `<App>Export...`, `<App>Notification...`, `Adobe...`, `...ChildFlow`; a replacement is `...V2`.
- Stored-procedure calls: parameters appear in alphabetical order (as the designer saves them); `retryPolicy: none` on
  every SQL call - never add automatic replay of a mutation; connection references use server and database `default`.
  Never embed endpoints.
- Use: `coalesce`, `first`, `empty`, `if(not(empty(x)), ..., null)`, `concat`, `join`, `formatDateTime`. Conditions are
  the designer's rows. OData filters put each `and` on its own line.
- Avoid: `actions()`, `json('[]')`, `createArray`, `contains`, `toUpper`, `union` - none appear in the owner's
  designer-made flows. A few git-authored flows use them (profile); don't copy those parts. (General advice from other
  projects such as "union() not concat()" does not apply here.)

## Environments, switches, mail

- One text environment variable (`solution.environment_switch_var`, default "Test") decides Production vs test.
  Outside Production, an app-called flow mails the caller; a scheduled flow mails a fixed test address or nothing.
  A fixed test address in a flow definition is the tester's own (from their `safety.test_email_allowlist`) - a
  coworker testing the same flow changes it to theirs.
- Keep environment variables to a minimum; an unneeded one was removed from a codebase before. Their values are set per
  environment and stay out of the solution and git ("Export value = No" breaks the pane's Check for updates).
- New features follow `rules.new_feature` when the config sets it (for example: a separate plug-and-play flow with its
  own String switch, default `'false'`, tested as `toLower(...) = 'true'`). Add only the switches the lead asks for.
- New e-mails copy the wording and structure of the existing ones. Recipients during development and tests: only the
  local config's `safety.test_email_allowlist` (skill pp-test-verify).
- New schedules set `timeZone` explicitly (`GTB Standard Time` for Athens) and a start time; some existing schedules
  have no time zone and run in UTC - read them before comparing times. Never run a notification or export flow during
  a read-only investigation.

## After the change lands in an environment

- **A brand-new flow authored in git arrives Off** - turn it on as the connection owner (pac cannot).
- **Share it.** An app-called flow needs Read shared with the app users' team (`environments.<env>.app_users_team(s)`);
  a flow nobody shared fails for plain users with `0x80048306 ... does not have ReadAccess ... Process`. Sharing is per
  environment, and imports can reset run-only sharing - read it back after each one.
- **Check the state of every flow after every pull or import** - pulls and imports have turned existing flows Off or
  left them Draft (for example when a connection's sign-in was revoked by a password change).
- **A flow calling a new proc** needs that proc (and its grants) on the target database first, or activation fails with
  `WorkflowOperationParametersExtraParameter`.
- Designer "Test -> Manually" runs of Power Apps V2 flows carry `x-ms-user-id`, so a flow can be exercised without the
  app. Prove what ran from the run's trigger payload, not from the UI.
- Ids: an app's `DataSources.json` `FlowNameId` is the flow's `workflowidunique`; FetchXML readbacks of a flow filter
  on `workflowid`.

## Starting an app-called flow without the app (re-runs, recovery)

- **Read the whole button first.** Its `OnSelect` often does more than `Flow.Run` - for example a `Select()` of another
  button that sends mails from the presser's mailbox. List those side effects before replacing presses with direct
  starts, and say which ones the direct route leaves out.
- **Run history holds every real call.** `GET .../flows/<id>/runs?api-version=2016-11-01` pages with `nextLink` (about
  28 days kept). A run's `properties.trigger.outputsLink.uri` (no token needed) returns its exact `body` inputs and
  headers, including the presser's `x-ms-user-email`; `.../runs/<run>/actions/<name>` and its `inputsLink` show what an
  action sent (a mail's To/Cc). Dataverse `flowruns`: skill pp-prod-diagnosis.
- **Prove the inputs before the first start:** rebuild them for records the app already ran and compare with those
  runs' trigger inputs until all are identical (random ids aside). It catches values the app takes from the presser.
- **A Power Apps V2 trigger accepts only the Power Apps connector gateway.** Its callback URL (`listCallbackUrl`)
  answers 401 `DirectApiAuthorizationRequired`, and 403 `MisMatchingOAuthClaims` with a Flow token; the management API
  `.../triggers/manual/run` answers 400 `TriggerInputSchemaMismatch` whatever wrapper the body has. What works: POST the
  inputs (`{"text": ..., "text_1": ...}`) to the app's gateway URL, which is the `x-ms-apim-referrer` header of a real
  app run (`https://<env>...azure-apihub.net/apim/logicflows/<binding>/triggers/manual/run?api-version=...`), with the
  starting account's own token for `https://apihub.azure.com`. The gateway sets `x-ms-user-*` from that token, so the
  run is recorded as that account's; the run name comes back in `x-ms-workflow-run-id`.
- **Bulk re-runs:** dry run by default; re-check each record live right before its start and skip it if it no longer
  needs one; stop new starts on the first failed or timed-out run, or one that succeeded without its effect; log every
  start with its run name so a restart follows those runs instead of starting them again. Keep runs in flight within
  the busiest connector's limit, shared with live users: OneDrive for Business allows 100 calls per connection per
  60 s (a report flow making ~6 calls per run: 10-15 runs at a time); Outlook ~30 mails per minute per mailbox, and it
  rejects the whole mail when one recipient is malformed - validate addresses first.

## Hand-over checklist

- [ ] Copied from the nearest sibling; structure matches the profile (scopes or branches).
- [ ] App-called flows: caller from `x-ms-user-id`; `{data, error}` responses with identical schemas; error text as
      above. Scheduled flows: the profile's identity rule; failures visible as failed runs.
- [ ] Designer names; SP parameters alphabetical; `retryPolicy: none`; `default` connection references.
- [ ] No `actions()` / `json('[]')` / `createArray` / `contains` / `toUpper` / `union`.
- [ ] Production-vs-test routing present; no mail outside the allowlist in tests.
- [ ] New flow files complete (folder, manifests, env var definition, version bump); new files added with CRLF.
- [ ] After landing: state On, shared with the app users' team (app-called flows), run verified from its payload.
