---
name: pp-powerfx
description: House conventions for Power Apps canvas apps written in Power Fx and .pa.yaml - App.Formulas as a typed vocabulary (named constants, Type() definitions, pure functions, one-Flow.Run behaviour functions), the flow wrapper, central error handling through App.OnError, OnStart staging, screen state, naming and formatting, search and interaction patterns, responsive AutoLayout and mobile parity - plus the Power Fx and YAML traps that silently break an app. Includes app profiles for Telework, Gaslog Briefing Desk and Surveys. Use it whenever you edit or review App.pa.yaml, a screen or component .pa.yaml, App.Formulas, OnStart or OnError, a UDF, a gallery or layout, or patch formulas in an .msapp, in a project with a .claude/pp-project.yaml, even for a small UI tweak.
---

# Canvas apps the way this app is already written

## Before you touch anything

1. **Load the project config** (skill `pp-project-config`): the canvas app's `src` path, the repo `kind` and
   `commit_policy`, `rules.mobile_parity`, `rules.licensing`, `related_skills`, `project.style_profile`.
2. **Read the app's profile** - `references/telework.md`, `references/gaslog.md` or `references/surveys.md`. Error
   handling, state and naming differ per app; match the app you are in.
3. **Open the nearest sibling** (the UDF, handler or control that does the most similar job) and copy it.
4. **Know how the change will ship.** For a `dataverse-git` repo, a merged edit does not reach the app on its own: the
   whole loop (PR -> pull cycle -> publish -> verify) is in skill `pp-release`, `references/dataverse-git.md`. Editing
   the `.pa.yaml` sources by hand: `references/pa-yaml-editing.md`. For an app shipped as a package, patch the formula
   in every copy the package holds.
5. **Read the project documents** listed in `project.docs` (for example an architecture document with the app's
   contracts and permission rules) before a change that touches data, flows or permissions.
6. **If the change needs data the app does not fetch yet**, that is a stored procedure or flow change (pp-sql,
   pp-flows), not a YAML change - and every layer must move together: proc projection -> flow response -> `Type()` ->
   deserializer.

## App.Formulas is a typed vocabulary

| Kind | Examples | Rule |
|---|---|---|
| Named constants | colours, GUID ids (`RoleViewerID`, `SessionDraftStatusID`), id sets, lookup tables (`WorkTypeColors`), formats, menus, SVG icons | Never scatter literals. Ids are `GUID("...")` constants named `...ID` |
| Types | `EmployeeDataType`, `RolesDataType := Type([RoleDataType])` | The contract with the flow. Rework = a `V2` type |
| Pure functions | `ClearText`, `JsonText` / `JsonGuid`, `DeserializeX`, `CreateXObject`, `HasRole(Roles, RoleID)`, cache helpers that return a new table | Inputs in, value out |
| Behaviour functions | `GetX`, `InsertX`, `UpdateX`, `CancelX` | Exactly one `Flow.Run`; return a typed value or raise `Error()` |

**Never in Formulas:** `Set`, `Collect`, `ClearCollect`, `UpdateContext`, `Patch`, `Notify`, `Navigate`, `Reset` - and
no reads of globals (`MyRoles`, `MyEmployeeProfile`, lookup tables loaded in OnStart). Whatever a function needs comes
in as a parameter; the caller passes the global: `IsDepartmentManager(MyEmployeeProfile)`,
`TransformSession(item, Forms, EntityLookups, Vessels, Ranks)`. A new derived flag = a pure predicate in Formulas plus
a `Set()` of its result in OnStart. Before handing over, search the Formulas block for `Set(` and for global names.

## The flow wrapper

```
output: IfError(
    DBInsertSession.Run(
        JSON(
            InputSession,
            JSONFormat.Compact
        )
    ),
    Error(AllErrors);
    Blank()
)
...
If(
    IsSQLDuplicateKey(output.error),
    Error({Kind: ErrorKind.ConstraintViolated, Message: DuplicateSQLKeyMessage}),
    !IsBlank(ClearText(output.error)),
    Error({Kind: ErrorKind.Validation, Message: output.error}),
    !IsBlank(ClearText(output.session)),
    DeserializeSession(output.session)
)
```

- Build the payload inside `With({payload: ...})`, normalise inputs (`ClearText`, date helpers), send it compact.
- Check `error` before `data`. Bad arguments raise `ErrorKind.InvalidArgument` "Invalid Parameters".
- Decode lists through the deserializer (`ForAll(Table(ParseJSON(...)), DeserializeX(JSON(ThisRecord.Value)))`, or a
  typed `ParseJSON(x, XsDataType)` where the app does that); normalise blank data text to `"[]"`.
- Return the contract's shape: a table, a combined record, or the first row of a result set - don't assume.
- The `Json*` helpers tolerate blank input. That is leniency, not validation: a write path must not turn empty or
  malformed data into a false success.

## Errors

Default (Telework, Gaslog): errors are handled centrally. `App.OnError` reports -
`ForAll(AllErrors, Concurrent(<Trace ...>, Notify(ThisRecord.Message, NotificationType.Error)))`. Screens call UDFs
bare, with no local `IfError` / `Notify`:

```
UpdateContext({showSpinner: true});
With(
    {item: CancelSession(MyLocalSession)},
    If(
        !IsBlank(item),
        <apply the returned record>
    )
);
UpdateContext({showSpinner: false})
```

An error value makes the `If` condition an error, the apply branch is skipped and OnError reports it once; a `;` chain
keeps running, so clearing the busy flag at the end is safe. `Confirm()` before anything destructive. Some apps handle
errors on the screen instead (Surveys) - the profile says which.

**OnStart:** adopt a result only when it is not blank - `With({x: Udf()}, If(!IsBlank(x), Set(g, x)))`. A bare
`Set(g, Udf())` stores the error value, and every control that reads `g` re-raises it; in one PROD incident that became
~500 identical error traces per session.

## State

- OnStart runs in stages: environment and the production flag -> independent loads in one `Concurrent` -> data that
  needs the user's profile -> role flags last. Keep that order when you add a dependency.
- Screen state with `UpdateContext` and `With`; which screens may `Set` globals is per app (profile).
- A hidden action button (`Visible: =false`) holds a routine that other events run with `Select()`.
- Reset inputs with `UpdateContext({resetValue: true}); UpdateContext({resetValue: false})` and `Reset: =resetValue`.
- Caches are returned as new tables by pure helpers; nothing invalidates them across sessions, so a new query dimension
  needs a new cache key or an explicit refresh.

## Style

- Studio "Format text" layout: one argument per line, single-field records inline (`{item: First(data.value)}`). Keep
  the tabs Studio wrote inside formula blocks.
- `And()`, `Or()`, `Not()`, `!IsBlank()` - not `&&` / `||` (except in an app that already uses them).
- Strings with `Concatenate()` or `Concat([...], Value, " ")`. Positive guards that let the missing branch be Blank:
  `If(!IsBlank(x), value)`.
- Compare ids with GUID constants, never names or display text; `exactin` for sets
  (`Status.ID exactin SessionTerminationStatuses`).
- Replace a field with `AddColumns(DropColumns(rec, Status), Status, SessionDraftStatusID)`.
- Controls named `<Context><Purpose><Type>` (`SessionStatusSearchComboBox`); give every new control a proper name.
- No explanatory comments; the owner strips them.

## Interaction

- One entry point per search: the search button's `OnSelect`. Filters change inputs and either wait for the button or
  run `Select(<button>)`, per app. `OnVisible` does not auto-search unless the screen is designed to.
- Reuse first: an existing UDF or flow, or data OnStart already loads, before adding a call.
- No unnecessary calls: update results in place (`UpdateIf`) instead of re-reading; adopt the record a write returns;
  no toast on a successful save.
- Edit rights come from each control's `DisplayMode`, mirroring the server rule. Don't re-check in a handler what
  `DisplayMode` already guarantees.

## Layout and mobile

- With `rules.mobile_parity`, every change must also work on the phone layout (`Screen.Size` Small/Medium): check the
  phone preview before handing over.
- Flexible AutoLayout rows (`FillPortions`, `LayoutMinWidth`), not pixel X/Y. For every AutoLayout container that is
  not flexible, set Height AND LayoutMinHeight (Width AND LayoutMinWidth), or it renders shorter than asked.
- A container nested inside a wrapping row can paint nothing - keep leaf controls as direct children of the row.
- Patterns that render reliably: `LayoutWrap: =<phone condition>` on a horizontal container; AutoHeight labels inside a
  fixed-height vertical container; a `FillPortions: 1` label with `VerticalAlign.Bottom` as the last child to pin text
  to the bottom of a scrolling pane.
- Use a control's own property before building a wrapper (the classic text input has `Clear`).
- Icons sized like their neighbours, centred, gap 5. No new legends or extra UI unless asked; leave the other layout
  untouched when changing one.

## Gates before handing over

1. Offline checks - they catch structure and names only:
   `node "<this skill's folder>/scripts/check-pa-yaml.mjs" <Src> --known <tests.pa_yaml_known_unresolved> --strict`,
   then a `pac canvas validate` diff against the pristine tree (details in `references/pa-yaml-editing.md`).
2. **Studio App checker -> Formulas (0)** after every change that lands: the only detector of type errors, and a type
   error silently disables a whole behaviour formula at runtime.
3. Run it (Studio Play) and click the real paths; fix problems in the source, not in Studio - a Studio fix puts the
   environment ahead of git.

## Traps (all seen in these apps)

- `If` / `IfError` arms must end in compatible types; a `;` chain's type is its last expression. Mixing a
  `Collect`/`Set` arm with a `Notify` arm is a compile error that silently disables the formula.
- `Self.WrapCount`, `Self.TemplateSize`, `Self.Items` are not readable inside a gallery's own `Height`; size wrapped
  galleries from constants.
- The classic Toggle fires `OnChange` when its `Default` changes in code - guard with `If(Self.Value <> loc, ...)`.
- A property on the wrong YAML node (for example `AccessibleLabel` outside `Properties:`) stops Studio opening the app;
  offline checks miss it. No `: ` inside plain YAML scalars - use the `|-` block form.
- Changing an existing control's `Variant` in YAML may not apply - rename the control so it is created fresh.
- Settings that are not formulas (App Insights connection string) live in `Properties.json` - change them in Studio.
- An untouched modern combobox reports a blank row - guard with `IsBlank(<picker>.Selected.Value)`.
- `Controls/*.json` and `_EditorState.pa.yaml` are not source; never edit them.
- A container `Height` that sums AutoHeight children grows without bound; give the container fixed heights
  (`If(<phone>, 96, 48)`) and let AutoHeight labels live inside it.
- A degraded session looks like a code bug: when OnStart hits a flow error, role globals stay unset and gated menu items
  can render as black tiles. Reload Studio for a fresh session before diagnosing rendering.
