# App profile: Gaslog Briefing Desk (`itt_interviews_56360`)

Source: `canvasapps/itt_interviews_56360/..._DocumentUri/Src/` in the solution repo (Dataverse Git-integration format;
tablet form factor). The app shows no comments anywhere in Formulas - add none.

## Types: two layers
- `XDBDataType`: flat, mirrors the SQL row - GUID foreign keys, `CreatedBy/On`, `ModifiedBy/On`.
- `XDataType`: the screen shape with nested records (`Form: FormDataType`, `Status: EntityLookupDataType`,
  `Created: AuditDataType`). Plural table types `XsDataType := Type([XDataType])`.
- Converters, all pure and in Formulas:
  - `DeserializeX(Value:Text):XDBDataType` - `If(!IsBlank(ClearText(Value)), With({item: IfError(ParseJSON(Value), Blank())}, If(!IsBlank(item), {...})))`;
  - `TransformX(InputX:XDBDataType, Forms, EntityLookups, Vessels, Ranks):XDataType` - lookups passed in;
  - `CreateXDBObject(InputX:XDataType):XDBDataType` - flattens nested records to ids;
  - `CreateXObject(InputA, InputB, ...)` - positional parameters prefixed `Input`, in field order;
  - nested JSON columns (travel documents) via `SerializeX` / typed `ParseJSON(Input, XDataType)`.
- A new related list (for example agreement participants) is typed in the parent type, deserialised once in
  `TransformSession` and serialised back in `CreateSessionDBObject` - the way travel documents are.

## Constants
- GUID ids `...ID` for roles, form types, statuses, comment types, relation types, document types, entities
  (`RoleCoordinatorID`, `FormTypeBriefingID`, `SessionDraftStatusID`, `CommentTypeDepartmentalID`).
- Id sets (`SessionTerminationStatuses`), colour tables keyed by id (`ColoredSessionStatuses`), `SidebarMenu` /
  `SidebarMenuAdmin`, messages (`DuplicateSQLKeyMessage`).
- New states are new GUID constants compared with `exactin`; never compare names or display strings, and UDFs do not
  return display text for states.

## Errors, state, screens
- `App.OnError` always traces (no production check) and notifies.
- Screens call behaviour UDFs bare inside `With({item: ...}, If(!IsBlank(item), ...))`, bracketed by
  `UpdateContext({showSpinner: true})` / `({showSpinner: false})`; the only screen `Notify` is an else-branch message.
- Screens may `Set` the current record so it travels between screens: `Set(MyLocalSession, TransformSession(item, Forms,
  EntityLookups, Vessels, Ranks)); Select(UpdateVariablesBtn)`. Local names: `MyLocal*`, `showSpinner`, `showcriteria`,
  `resetValue`, `EditingAllowed`; `With` locals `output`, `item`, `_seafarer`.
- OnStart: `EnvironmentSetup`, `ApplicationURL`, `CurrentUserUPN`, `IsDebug`, `Users`, `MyUser` one at a time, then
  lookups in parallel, derived filters in parallel, flags last. Deep link:
  `StartScreen = If(And(!IsBlank(Param("ID")), !IsError(GUID(Param("ID")))), SessionScreen, HomeScreen)`.
- Production flag `label = "Production"`; test recipients `If(IsProductionEnvironment, Seafarer.Email, MyUser.Profile.mail)`.
- Collections are rare; the session list uses an upsert (`Patch(... LookUp ...)`, else `Collect`).
- Validation: a bad field turns its `BorderColor` red; Save is disabled while
  `Color.Red exactin [<ctl>.BorderColor, ...]`. Picker guard:
  `If(And(!IsBlank(C.SelectedItems), !IsEmpty(C.SelectedItems)), C.Selected)`.
- Comments merge through `CreateCommentObject`; one `Sort` at the end, not several fetches glued with `Table()`.
- Strings with `Concatenate()` / `Text()`; no tooltips.

## Shipping a formula-only change as a package
Patch the formula in every copy the msapp holds, assert each edit matches exactly once in each copy, keep the original
msapp for rollback, and check App checker still shows the baseline count afterwards.
