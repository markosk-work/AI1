# App profile: Surveys (`inttrust_surveys_270d7`)

Most of this app was written by a different developer from Telework and Gaslog, in a different style. Match the
Surveys screens and UDFs themselves; the central-error rule of the other two apps does not apply here.

## Differences to respect
- **Data path:** the app talks to SQL directly through the SQL connector and `Patch`es tables from screens and
  OnStart; stored procedures are called as `Surveys.dboX({...})`.
- **UDF pattern:** `With({result: Surveys.dboX({...})}, IfError(result, Error(FirstError), <value>))` - a new UDF copies
  the nearest one (for example `GetSurveyMaxScore(SurveyID:GUID):Number` was modelled on `GetSurveys`).
- **Errors on the screen:** `App.OnError` only traces
  (`Trace("Unhandled Error", TraceSeverity.Error, {Kind, Message, Observed, Screen: App.ActiveScreen.Name, Source, Details})`);
  screens catch their own:
  `IfError(<call>, Concurrent(Notify(FirstError.Message, NotificationType.Error), Trace("Handled Error", TraceSeverity.Error, {...})), <success>)`.
- Types: `SingleX := Type(RecordOf(X))`. The code uses `&&`, `||` and `Coalesce` freely - match the file you edit.
- Comments: only the "Logical Separator" markers (`/*Survey Statuses*/ ... /*Survey Statuses*/`); add none.
- A debug flag tied to one developer's login exists (`IsKC`); don't reuse or extend it.

## Stored procedures as data sources
- All stored procedures sit in ONE `Surveys` data source. Adding a proc later creates `Surveys_1`, so remove and re-add
  all of them at once.
- Only the read procs are ticked "safe for galleries"; write procs are not.
- Validation belongs in the proc, not in the UI (project rule): a new rule is a THROW in the proc, surfaced by the
  screen's IfError.

## Messages and telemetry
- User-facing messages are translation keys (`...ErrorKey`); a new key needs a row in the translations table, or the
  message falls back to English.
- Swallowed failures hide bugs: a value fetched once with `IsBlankOrError` and saved later without a check produced
  blank scores. Re-fetch or validate at the save, server-side.
- The App Insights key is injected per environment at release time (MakeSurveys.ps1), not edited in the app.
