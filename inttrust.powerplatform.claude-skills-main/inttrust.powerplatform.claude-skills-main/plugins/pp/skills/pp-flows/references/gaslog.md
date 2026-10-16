# Flow profile: Gaslog Briefing Desk

About 50 flows under `BriefingDeskSolution/ApplicationSolution/modernflows/`, each a `workflow.yml` plus
`<FlowName>-<GUID>.json`. The repo is in Dataverse Git-integration format: never `pac solution unpack` over it.

## Structure (every SQL-backed flow)

```
Parse_JSON -> Initialize_data_variable -> Initialize_error_variable
Try_Scope:   Execute_stored_procedure_(V2)        retryPolicy none, server/database "default"
             Set_data_variable = @first(outputs('Execute_stored_procedure_(V2)')?['body/ResultSets/Table1'])
Catch_Scope  (runAfter Try_Scope: Failed, TimedOut, Skipped): set the error variable
Respond_to_a_Power_App_or_flow  (runAfter Catch_Scope: Succeeded, Skipped): {session|data: @{variables('data')}, error: @{variables('error')}}
```

- Variables are initialised data first, then error.
- No `Terminate` anywhere (not in webhooks either).
- Multi-step catch: `Filter_array` over `@result('Try_Scope')` where `@equals(item()?['status'],'Failed')`, then

```
@concat(
    first(body('Filter_array'))?['name'],
    ' - ',
    coalesce(
        first(body('Filter_array'))?['error']?['message'],
        first(body('Filter_array'))?['outputs']?['body']?['error']?['message']
    )
)
```

- Adobe actions: read the connector's own message first, e.g. `coalesce(body('Cancel_an_agreement')?['message'], ...)`
  or `body('Get_the_status_of_an_agreement')?['message']`.
- Child flows: manual trigger with `text_N` inputs; the parent returns
  `coalesce(outputs('Run_a_Child_Flow')?['Body']?['error'], variables('Error'))`.

## Reads
Most app reads are flows running `Get rows (V2)` directly on a table or view (`DBGetSessionReport` on `[Session.View]`,
`DBGetComments`, `DBGetUsers`). A new read is usually a view plus `Get rows`, or an existing generic proc, not a new proc.

## Schedules and pollers
Recurrence (`Hour`, `timeZone "GTB Standard Time"`, start time) -> `Get_Systemic_User` -> `Get_rows_(V2)` with a
`$filter` (each `and` on its own line, e.g. `\nand eSignatureID eq null`) -> Condition on results -> `Apply_to_each`.

## Environment routing and mail
- `itt_InterviewsAppEnvironment` ("Test" by default). Recipient switch in the flow, not in SQL:
  `if(equals(parameters('InterviewsAppEnvironment (itt_InterviewsAppEnvironment)'),'Production'), <seafarer email>, <caller's x-ms-user-email>)`.
- Office 365 `SendEmailV2`; recipients looked up through Graph `getByIds` over the HTTP-with-Entra-ID connector.
- Number env vars for delays (`itt_SeafarerSignatureNotificationDelayHours`, `itt_UsersCommentNotificationDelayHours`).
- The original codebase has no kill-switch variables; the staged-signing feature added `itt_StagedSigningEnabled`
  (default no) and `itt_TestParticipantEmails` at the lead's request. Keep the values out of the main solution so
  QA/Prod stay off until the release script sets them.

## Adobe Acrobat Sign
- Legacy path: OneDrive CreateFile -> convert to PDF -> `CreateTransientDocument_V2` -> `CreateLibraryDocumentById_V2`
  -> Switch on the form-type GUID -> `CreateAgreementByTemplate_V2` (SIGNER, IN_PROCESS); webhook
  `CreateWebhookForAgreementStatusUpdated` -> get the PDF and form data -> shared completion child flow.
- FORM_FILLER is not enabled on the account; use APPROVER for comment steps. Adobe `comments` is not a multi-party
  comment model. The same e-mail may appear twice non-adjacent; plus-addressing works; text tags survive OneDrive
  HTML->PDF; multiline fields grow downward (leave room).
- `formDataList` holds one row per participant stamped with the creation time even before anyone acts - use it only
  when `hasFormFieldData` is true.
- Webhooks fast-exit for agreements that are not this app's; the DEV webhook may be suspended - a Retrieve button and
  a poller cover it.

## Activation
- `pac` cannot turn flows on, and an import leaves existing Draft flows Draft. Turn them on in make.powerautomate.com as
  the connection owner (the DEV maker account). With a hidden browser window, a JS `.click()` on
  `[data-automation-id=flowCommand-toggleFlowState]` works.

## Review findings to respect
Trigger descriptions "Please enter X"; designer default names (`Execute_stored_procedure_(V2)` for a single SP,
`Select`, `Cancel_an_agreement`); SP parameters alphabetical; no `actions()` / `json('[]')` / `createArray` /
`contains` / `toUpper`; designer Or rows; `AdobeCancelAgreement` cancels in the Yes branch.
