# SQL profile: Surveys

The Surveys SQL is not the Telework or Gaslog author's hand: most of it was written by another developer (2025 feature
work). Match the Surveys file itself - do not import the Telework or Gaslog templates. Delivery rules from the project
still apply (new procs only in the DDL file, no new files, commit only on explicit request).

## Files
- `SurveysDeployment/SQLScripts/Surveys DDL scripts.txt` - the master DDL (plain text, run piece by piece). New procs
  are appended here and nowhere else. It is already behind Production (no `Answer.Responder` column, different Answer
  index keys) - read live before trusting it.
- Other `.txt` scripts in `SQLScripts/` are one-off updates. Never execute any of them without an explicit request that
  names the server and database.

## Style of the file
- Schema-less `CREATE PROCEDURE CalculateMaxScore4Survey` (no `[dbo].`), no SET lines.
- Tab indentation, lower-case keywords (`is null`, `declare`), `declare @x ...; set @x = ...` on separate statements.
- Role checks: `If EXISTS(select ID from UserRoleRelation ...)`.
- Errors: 60000 'Invalid Parameters'.
- No transactions in the existing procs.
- Seeds: `insert ... select ... union select ...`.
- Table DDL uses the `Table_Column_Check` constraint naming (same template lineage as Gaslog).
- Two later procs (`FinalizeSurvey`, `ReviewSurvey`) were written in the Telework template instead (SET lines,
  `CREATE OR ALTER`, XACT_ABORT, INSERT-EXEC, codes 60001-60003). They are a known mismatch - do not copy their shape
  into new Surveys procs.

## Data and performance facts
- `dbo.Answer` is large (over a million rows in PROD). Its two original non-clustered indexes are filtered
  (`ChoiceValue IS NULL` / `IS NOT NULL`), so unfiltered lookups scanned the clustered index until `IX_Answer_Survey`
  (Survey, QuestionQuestionnaireRelation) INCLUDE (ChoiceValue) was added ONLINE in all three databases.
- Validation belongs in the stored procedure, not the UI (project rule).
- A daily BI refresh hits the database 05-19 UTC (long queries, `dbo.DistanceKM` called ~800k times an hour) - normal
  load, not an incident.

## dbo.GenerateReportHTML
- Builds the survey report's HTML for one language (the V2 report flow asks for the survey's own and English) as one
  string (`SET @HTML = @HTML + ...`, ~1,000 lines). Its own style - `[dbo].`, 4-space indent, upper case, banner
  comments - so a fix matches this proc, not the file's style. Keep the body identical in all three databases; diff
  them before a fix.
- Any NULL piece makes the whole report NULL. The known cases are guarded: `ISNULL(@DisplayScore, '')` (a Mystery
  survey in External review with a Disqualification answer has no score) and LEFT JOIN `EntityLookup` in the three
  tank lookups (a tank without a fuel type). A new optional piece needs the same guard (SKILL.md "String building");
  prove a fix with the byte-identical regression on real reports (SKILL.md "Changing the body of a live procedure").
- The proc was long missing from the DDL file; the fixed body is appended there on a release branch (whether it has
  reached `master`: the project's memory). Read the live body, not the file.

## Databases (names in the config)
- InTTrust DEV/test DB (`databases.dev`): holds real station e-mail addresses.
- Customer databases (`databases.qa`, `databases.prod`): reached through go-sqlcmd contexts with a db_owner SQL login.
  SELECT only unless a write is explicitly requested; `use-context` switches globally, so check `@@SERVERNAME` in
  every run and switch back afterwards. Production needs the user's VPN (firewall).
- Data fixes go preview -> apply with verification (skill pp-test-verify).
