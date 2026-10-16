# SQL profile: Telework

Repo `Telework-SQL` (role `sql` in the config). The DB owner wrote almost all of it and edits live procs by hand, then
commits straight to `main`.

## Files
- Master script `DDL SQL Scripts.sql`, with section markers `/* TABLES */ ... /* TABLES END */`,
  `/* PROCEDURES START*/ ... /* PROCEDURES END */`, `/* FUNCTIONS START */ ... /* FUNCTIONS END */`.
- Table changes since 2026-09-16 go in per-table files `<Table> Table.sql` (`Department Table.sql`, `Team Table.sql`,
  `RemoteWorkDay Table.sql`, `SPPersonnel Table.sql`): the SSMS CREATE, then the exact ALTER / UPDATE / seed statements
  that were run, in order. Proc changes go in the master script in place.
- Seeds: one `INSERT ... VALUES` + `GO` per row with literal random GUIDs (`Static Data SQL Scripts.sql`).
- The master script keeps `GO` inside `/* */` blocks, so running the whole file fails ("Missing end comment mark").
  Run one object at a time.
- `tests/` holds the rolled-back acceptance harness (`tests/Test-WorkDayProcs.ps1`, see pp-test-verify).

## Object header
Every object has the SET lines and upper-case `CREATE OR ALTER`:

```sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[X]
(
    @User uniqueidentifier,
    ...
    @UpdatedAt datetimeoffset(7)
)
AS
BEGIN
    SET NOCOUNT ON;
    ...
END
GO
```

## Naming specifics
- Audit columns `CreatedAt` / `UpdatedAt` (`datetimeoffset(7)`), `CreatedBy` / `UpdatedBy`.
- Constraints `PK_<T>`, `DF_<T>_<C>`, `UQ_<T>_<C>`; unique indexes `UX_` or `IX_`.
- `Db` prefix only on the workday family (`DbInsertWorkDayV2`, `DbGetDeptWorkDays`).
- Dates `@StartDate` / `@EndDate`; token `@UpdatedAt`.
- 4-space indentation inside procs; tables are SSMS-scripted verbatim (tab-indented, `WITH (...) ON [PRIMARY]`).

## Identity and authorisation
Role flags are scalar variables built from `MAX(CASE ...)`, and role GUIDs come from scalar functions
(`GetDeptModeratorRoleID()`, ...). Never `IIF(EXISTS(...))`:

```sql
DECLARE @IsModerator bit = 0;
SELECT @IsModerator = ISNULL(MAX(CASE WHEN RoleID = @ModeratorRoleID THEN 1 ELSE 0 END), 0)
FROM dbo.EmployeeRole
WHERE EmployeeID = @User AND Active = 1;

SELECT @UserDeptID = DepartmentID, @UserEmail = email
FROM [dbo].[GetActiveEmployeeFromPersonnelByEntraID](@User);
```

- Authorise either as a predicate on the DML followed by `IF @@ROWCOUNT = 0 THROW ...`, or as
  `IF @IsHRAdmin = 1 <statement> ELSE THROW 50000, 'Unauthorized access', 1;`.
- Permissions are per operation, not one hierarchy. Search: HR admin / viewer see all, same-department moderator,
  the target's department or team manager, self. Workday writes: self, the target's named department manager (any
  department), same-department moderator; managers and moderators are exempt from their own weekly quota. A new
  predicate goes outside the optional filters, so a broader search never broadens access.
- `DbInsertWorkDayV2` validates parameters first (51007, then 51000-51003) and checks security after (51004). Copy the
  order of the sibling you extend.
- A persona test is just `EXEC` with another user's Entra id as `@User`: the proc takes identity from the parameter, not
  from the SQL login.

## Errors
- Workday procs number their own: 51000 'Unsupported work type', 51001, ..., 51004 'Invalid Action',
  51005 'Weekly remote work quota exceeded', 51006 'Action not succeeded', 51007 'Required parameter missing'.
- Remove procs: 51100 'Action not succeeded'. Role procs: 50000 'Unauthorized access', 50001 'Action unsuccessful'.
- Sentence-case messages. Other procs reuse 51000/51001 with their own messages - copy the sibling.
- 51001 'Invalid Action' from `UpdateEmployee` = the authorisation or concurrency guard fired: check the caller's
  `EmployeeRole` rows and the row's `DepartmentManagerEmail` before suspecting the proc version.

## Transactions, token, return shapes
- Only where several statements share an invariant (the two insert procs):
  `SET XACT_ABORT ON; BEGIN TRAN; ... IF ... BEGIN ROLLBACK; THROW ... END ... COMMIT;`, with
  `WITH (UPDLOCK, HOLDLOCK)` on the weekly count, plus the unique `(WorkDate, Employee)` index.
- Token: `AND @UpdatedAt IS NOT NULL AND ABS(DATEDIFF_BIG(MICROSECOND, UpdatedAt, @UpdatedAt)) < 1000`.
- Shape copy: `SELECT * INTO #RemoteWorkDay FROM (SELECT TOP 0 * FROM [dbo].[RemoteWorkDay]) AS EmptyTable;` then
  `OUTPUT inserted.* INTO #RemoteWorkDay` and `SELECT * FROM #RemoteWorkDay;`.
- Several datasets come back as one row of `FOR JSON PATH` columns (`DbGetDeptWorkDays`).
- `INSERT INTO #t EXEC ...` is used once (DbGetDeptWorkDays); wrapping that proc in another INSERT-EXEC fails with 8164.
- Recipient lists: `JSON_ARRAYAGG([email] ORDER BY [email] RETURNING JSON)` inside `ISNULL(..., CAST(N'[]' AS json))`.
- Search procs: `SET @LastName = NULLIF(TRIM(@LastName), N'');`, `(@X IS NULL OR col = @X)`, `OPTION (RECOMPILE)`,
  Greek columns compared `COLLATE Greek_CI_AI`.

## Data
- Enumerations: `Role` and `WorkType` tables (GUID + Code + Name), read through `Get...ID()` functions.
- Local time: `[dbo].[GetLocalDateTime](SYSDATETIMEOFFSET())` (`AT TIME ZONE 'GTB Standard Time'`). Active personnel:
  `TerminationDate IS NULL OR TerminationDate >= @today`.
- The booking cutoff (Thursday 18:00 local) is hard-coded in `dbo.GetFirstAllowedRegistrationDate`;
  `SP_GetFirstAllowedRegistrationDate` is only a wrapper. It has been hand-edited before (to Friday 11:00) - check the
  function first when the booking window looks wrong. The reminder e-mail text says 17:00; ask before changing either.
- `ConfigParameter` exists but no proc reads it.
- DEV grants: the flows' SQL user is in `db_datareader`, `db_datawriter` and a `db_executor` role (database-level
  EXECUTE), so new procs are callable in DEV at once. The repo holds no grants; PROD is the owner's.

## How the owner rewrote an assistant change (527beb6 -> reverted d0ebf89 -> 2fe1b8c, 3f50c01)

| Assistant (reverted) | Owner's version |
|---|---|
| Edited the master `CREATE TABLE Department`, appended `CREATE TABLE Team` to the master | Master untouched; new `Department Table.sql` / `Team Table.sql` with the ALTER / UPDATE actually run |
| `Team.TeamName`, a `CreatedAt` default, `UpdatedAt` NULL, rows by hand | `Team.Name`, both timestamps NOT NULL, seeded `select distinct ... from SPPersonnel` |
| Prose comments, one join per line, EXISTS subquery for team leaders, changed GROUP BY | One added join line: `AND (d.Notify = 1 AND d.IsActive = 1)`, `AND (t.ID is null OR (t.Notify = 1 AND t.IsActive = 1))`; team leaders kept by the existing `OR`; no comments |
| (missing) | Next day: `;WITH EmployeesBase ... ModeratorsBase` + `NOT EXISTS` to stop duplicate recipients; managers out of To, moderators in CC; `ORDER BY [email]` |

Other reverts: a "sync procs from the live DB" commit (406eaa5 -> 728c81a) and an `@Active = NULL` default commit
(-> b1b4090); an extra `deploy-employee-procs.sql` file was deleted (f0fd71f). Lesson: the smallest predicate change
inside the existing proc, in the existing file, committed by the owner.

## Owner's commit style
Short lower-case phrases: "changes on workdays procedures", "commented out unused sp".
