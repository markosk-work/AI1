---
name: pp-sql
description: House conventions and a safe procedure for T-SQL behind Power Platform apps - stored procedures, tables, indexes, seeds and master DDL scripts - so new SQL is indistinguishable from the code already there - naming, casing, procedure skeleton, caller identity (@User) and authorization, THROW codes, transactions, concurrency tokens, return shapes and data modelling - plus how to apply a change to a live database without overwriting hand-edited objects. Includes codebase profiles for Telework, Gaslog Briefing Desk and Surveys. Use it whenever you write, review, deploy, compare or diagnose SQL in a project with a .claude/pp-project.yaml or in the Telework-SQL, Gaslog-Briefing-Desk-SQL or SurveysDeployment SQLScripts repos, even for a one-line proc change, "just add a column", a backfill or an index.
---

# SQL the way this codebase already writes it

## Before you touch anything

1. **Load the project config** (skill `pp-project-config`): the SQL repo's `commit_policy`, `new_files` and owner, the
   DDL file, the databases, the roles, and `project.style_profile`.
2. **Read the profile** for this codebase - `references/telework.md`, `references/gaslog.md` or `references/surveys.md`.
   It holds everything that differs between codebases: CREATE form, error codes, transactions, token, naming. With no
   built-in profile, read `project.style_notes`, or derive the conventions from the nearest existing procs.
3. **Fetch first.** The DB owner commits straight to `main`; a stale clone produces a stale diff. If you cannot fetch,
   note the `FETCH_HEAD` date and whether HEAD equals origin, and call the diff provisional.
4. **Read the live definition** of every object you will change - and of every object your new code depends on
   (`OBJECT_DEFINITION` / `sys.sql_modules`). Owners edit live objects by hand, so live is often ahead of git. Start
   from the live body, not the repo copy. If a dependency exists only in someone's uncommitted work, say so: your code
   ships with it or after it.
5. **Open the nearest sibling** - the existing proc that does the most similar job - and copy its structure, names,
   casing and formatting. The existing convention beats a cleaner design.

## Scope rules

- **Smallest change inside existing objects.** Prefer a `V2` next to V1 (same signature), an optional parameter, one
  more join or predicate - or no SQL change at all when the app can already get the rows (an existing proc, or a flow
  reading a table or view directly). A new table, proc or file needs the lead's agreement; a new stored procedure needs
  the SP approver's OK before it enters the DDL file or a database. A draft outside the repo, to show the approver, is
  fine.
- **Fix it in the flow when that avoids a proc change** - DB owners prefer it, and it keeps their object untouched.
- **Never rename a deployed object** - version it. The name may outlive its meaning (a proc called InsertOrGet... that
  no longer inserts stays as it is).
- **Repos with `commit_policy: never`:** edit the existing DDL file in the working tree only, add no files, and report
  the diff; the owner commits. Delta, rollback, test and backfill scripts live outside the owner's repo
  (`paths.work_outside_repos` in the config, or the scratchpad).
- **Owner repos get rewritten.** Owners revert what they did not write and re-implement it their way, even authorised
  commits. Expect it, and learn from the rewrite (see the profile's examples).

## Conventions shared across these codebases (where the profile differs, the profile wins)

**Files**
- One master DDL script per database, run piece by piece in SSMS: security, then tables (each with its indexes), then
  procedures, functions, views. No `IF OBJECT_ID` guards, no DROP/CREATE pairs.
- New proc at the end of its section; a V2 directly after its V1; a replacement directly after what it replaces.
- Deprecate in three steps: keep, comment out the whole object (`--DELETED` + `/* ... */`), delete later. No DROP in
  the script - dropping objects in the owner's database is the owner's job.
- No header or banner comments, no prose comments. A one-line label on a magic value is fine: `--briefing form`,
  `where [ID] = 28 --SOLUTION SALES`.

**Naming**
- Tables singular PascalCase (`Employee`, `Team`, `[User]`). Columns PascalCase; primary key `ID` (GUID).
- Reference columns are named after the entity, without an `ID` suffix: `[Employee]`, `[Status]`. Columns imported from
  HR keep their source names (`EntraID`, `DepartmentID`, `email`).
- Procs start with a verb: `Get...`, `Insert...`, `Update...`, `Remove...`/`Delete...`, `InsertOrGet...`,
  `Get<Plural>WithCriteria`, `Get...ToNotify`; `4` means "for" (`CalculateMaxScore4Survey`); a successor is `...V2`.
- Parameters: `@User` = the caller; `@Employee` / `@ID` = the target; the concurrency token always last.
- CTEs are PascalCase nouns (`EmployeesBase`); aliases short and lower-case (`e`, `p`, `pd`, `empl`).

**Layout**
- Types lower-case (`uniqueidentifier`, `nvarchar(200)`, `bit`); defaults written `= null`.
- Parameter list between `(` and `)` on their own lines; one INSERT column per line; leading commas in column lists.
- Column aliases bracketed without `AS`: `pd.ID [PersonnelID]`, `cast(1 as bit) [IsActive]`.
- `IIF` for a two-branch value, `CASE` for more branches and for role flags. `<>` not `!=`. `EXISTS(SELECT 1 ...)`.
  ANSI joins, often several on one line.
- Keyword case is mixed in the existing code and nobody polices it; lower case is always safe for `join ... on`,
  `is null`, `declare`, `begin try`, `output inserted.*`. Do not normalise the owner's casing or brackets.
- **Keep the owner's bytes.** Trailing whitespace, tabs and typos stay exactly as they are (a misspelt proc name is part
  of the API), and so do the file's line endings. Patch from HEAD with an editor that does not strip trailing spaces,
  and check `git diff` shows only your lines. If the working tree already carries someone else's uncommitted change,
  diff against a copy taken just before your edit and tell the owner which hunks are yours.

**Procedure skeleton**
- `SET NOCOUNT ON` first. Scalar parameters, not a JSON parameter.
- The caller is `@User` - the Entra object id the flow takes from the `x-ms-user-id` header. Authorisation and
  validation live in the proc; the app only mirrors them.
- Errors: `THROW <code>, '<message>', 1;` - never RAISERROR. Codes and message casing are per codebase (profile).
- Writes return the changed row: `OUTPUT inserted.*` directly, or into a temp table with the same shape and a final
  `SELECT * FROM #X;`. No extra status or "outcome" result sets.
- Concurrency uses a timestamp token, not rowversion. The caller sends the token of the record it selected, keeps its
  precision through JSON and the flow, and adopts the returned row. A 0-row update means stale, denied or ineligible.
- **String building:** one NULL in `@HTML + ... + @x` makes the whole result NULL. `ISNULL(@x, '')` every optional
  value, and LEFT JOIN an optional lookup that fills variables - an inner join that finds no row assigns nothing, so
  they stay NULL (or keep the previous loop's value).

**Data modelling**
- GUID `ID` everywhere (`NEWID()` in the INSERT, or supplied by the app). No foreign keys.
- Enumerations are GUID rows in lookup tables, never strings and never `CHECK ... IN ('A','B')`. Seed GUIDs are random,
  never patterned.
- Optional flags are `bit NULL` with no default, and only `1` counts: `(t.ID is null OR (t.Notify = 1 AND t.IsActive = 1))`.
- Soft delete = an `Active` column plus a filtered unique index (`WHERE [Active] = 1`).
- Timestamps from `SYSDATETIMEOFFSET()`.
- Configuration often lives hard-coded in functions (a cutoff day and time inside a scalar function), not in a config
  table - when behaviour looks wrong, read those functions first.
- **Design parameter defaults around the connector.** The Power Automate SQL connector omits a null parameter, so the
  proc's default is the real fallback (`@Active bit = NULL`). JSON null, an omitted parameter, `false`, 0 and blank are
  five different things.

**Never**: banners or prose comments, side files, `IF OBJECT_ID` guards, DROP, string enums, patterned GUIDs,
`IIF(EXISTS(...))`, CROSS APPLY, TRY_CONVERT, cursors, RAISERROR, dynamic SQL, foreign keys, extra outcome selects.

## Applying SQL to a database - only on an explicit instruction for that target

1. **Pre-check, read-only:** `SUSER_SNAME()` and `DB_NAME()` / `@@SERVERNAME` match the intended target; permissions;
   the objects are in the expected state (`OBJECT_ID`, `COL_LENGTH`, `modify_date`); not on a day the config forbids
   (`rules.no_prod_changes_on`).
2. **Diff live against the file.** Normalise `CREATE OR ALTER` to `CREATE` (the database stores `CREATE   PROCEDURE`),
   whitespace and case; read the file as UTF-8 (Greek literals garble otherwise). An unexplained difference means
   someone changed it by hand - stop and ask.
3. **One transaction:** statements copied verbatim from the file; verify inside the transaction (definition equality,
   and results equal to a capture taken seconds before); roll back on any difference.
4. **Dry-run behaviour changes first.** For audience or visibility logic, run the new body against `#Table` copies
   (`[dbo].[X]` -> `#X`) and compare with the live output. This catches wrong recipients before anyone is mailed.
5. **Grants before the flow.** A new proc on another environment needs the grants its predecessor has - or, for a
   brand-new proc, EXECUTE for the flows' connection identity (`HAS_PERMS_BY_NAME('dbo.X', 'OBJECT', 'EXECUTE')` as that
   login; a database-wide `db_executor` role covers it) - before a flow that calls it is imported, or flow activation
   fails (`WorkflowOperationParametersExtraParameter`: the connection cannot see the parameters).
6. Test in rolled-back transactions - see skill `pp-test-verify`.

**Changing the body of a live procedure** (a fix in an existing proc):
- Save the live body as the rollback script (`CREATE OR ALTER`). Gate the apply on identity (`@@SERVERNAME`,
  `DB_NAME()`, `SUSER_SNAME()`) and on the live body being exactly the expected "before" body (normalised as in step
  2); otherwise run nothing. The rollback uses the same gate, with the fixed body as "before".
- Apply through SqlClient or `sqlcmd -I`. A proc keeps the QUOTED_IDENTIFIER and ANSI_NULLS it was created with, and
  ODBC sqlcmd defaults QUOTED_IDENTIFIER OFF (go-sqlcmd ignores `-I` and is always ON). Afterwards check the live body
  is the new one and `sys.sql_modules` `uses_ansi_nulls` / `uses_quoted_identifier` are 1.
- Regression: before and after, run the proc on a sample of real rows of every type and status (`INSERT ... EXEC` into
  a table variable, `HASHBYTES('SHA2_256', ...)` per output). Every output that was not the bug must be byte-identical.
- Reproduce the bug: create its condition with UPDATEs inside one transaction that is always rolled back, run the proc
  there (old body: the bug shows; new body: fixed), then re-read every touched value against its original.

## Scripts (config-driven, in `scripts/`)

- `Get-SqlToken.ps1 -Tenant <environments.<env>.tenant_id> -CachePath <tools.sql_token_cache>` returns an Entra token
  for Azure SQL from a DPAPI-cached refresh token. First use (or after `AADSTS50173` - the grant was revoked, usually by
  a password change): add `-Register`, run it in the background and give the user the device code. `-Scope
  '<resource>//.default'` gets a token for another resource with the same sign-in (read-only diagnostics). Never print
  the token; put it in `SqlConnection.AccessToken`.
- `Invoke-Sql.ps1 -Server <databases.<env>.server> -Database <...database> -Tenant ... -CachePath ... -SqlFile <file>`
  runs one batch (no GO splitting) and prints every result set, message and SQL error. `-SaveFirstStringTo <file>`
  writes the first result set's first column, all rows joined.
- **Long `FOR JSON` output arrives in 2,033-character pieces** - several rows through SqlClient, several lines through
  sqlcmd. Join them as they are. With go-sqlcmd (`-h -1 -y 0 -b`, drop the `Warning:` lines) strip only CR/LF from each
  line: `Trim`/`TrimEnd` deletes real spaces that fall on a piece boundary and changes values without any error.
- Azure SQL firewalls often reject home networks (`databases.<env>.network`, the local `network` note).
- `Connect-AzAccount -UseDeviceAuthentication` hangs in the non-interactive PowerShell 5.1 host - don't use Az.Accounts
  for this.

## Existing problems: report, don't copy, don't silently fix

Old code has bugs and hazards (plaintext secrets in a DDL file, an IF without ELSE that silently does nothing, live
bodies ahead of HEAD). Leave the owner's existing bodies exactly as they are while building a feature, never copy a
hazard into new code, and list what you found in your report. Each profile names the known ones.

## Hand-over checklist

- [ ] Sibling copied: CREATE form, casing, `= null`, brackets, THROW codes and messages match the profile.
- [ ] Only my lines in `git diff`; the owner's bytes untouched; no new files in an owner repo; nothing committed where
      `commit_policy` is `never`.
- [ ] Live definition was read first; any drift from git is reported.
- [ ] New proc: approval recorded; grants noted for every environment it must reach.
- [ ] The DB owner is told about every proc or schema change, in their `language`.
