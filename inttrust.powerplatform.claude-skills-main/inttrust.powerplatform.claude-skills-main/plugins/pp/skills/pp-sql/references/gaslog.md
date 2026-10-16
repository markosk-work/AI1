# SQL profile: Gaslog Briefing Desk

Repo `Gaslog-Briefing-Desk-SQL` (role `sql` in the config), written entirely by its DB owner. Master scripts
`BriefingDesk_DDL_Scripts.sql` (app database) and `Gaslog_DW_SQL.sql` (warehouse). Read the owner's version with
`git show HEAD:BriefingDesk_DDL_Scripts.sql` - the working tree may carry uncommitted edits that are not the owner's.
Migrations, pre-checks, rollbacks and fixtures for existing databases live outside this repo
(`paths.work_outside_repos`).

## Object header
No `SET ANSI_NULLS` / `SET QUOTED_IDENTIFIER` lines. `CREATE or ALTER` with a lower-case "or" (19 of 25 procs; the
owner typed it that way when converting); `SET NOCOUNT ON` usually without a semicolon (17 of 24):

```sql
CREATE or ALTER PROCEDURE [dbo].[X]
(
	@User uniqueidentifier,
	@ID uniqueidentifier,
	@Optional nvarchar(200) = null,
	@LastModifiedOn datetimeoffset
)
AS
BEGIN
	SET NOCOUNT ON
	...
END
GO
```

Whitespace (tabs vs spaces inside the gate and the DECLARE block) varies - copy the sibling's bytes. HEAD is CRLF.
A new version gets `V2` (`...V2`, `[model].[SeafarerBriefingDebriefingV2]`), never a new semantic name. A proc keyed
by a related entity names that parameter `@<Entity>ID` (`@SessionID`), as `DeleteSessionAttendeeUsers` and
`InsertComment` do.

## Reads usually don't need a new proc
Most app reads are flows running `Get rows (V2)` directly on a table or view (`DBGetSessionReport` on `[Session.View]`,
`DBGetComments`, `DBGetUsers`), or an existing generic proc (`GetEntityRelations`). Before writing a read proc, check
whether an existing proc or a view plus `Get rows` already returns the rows.

## Tables (hand-written, no foreign keys)

```sql
CREATE TABLE dbo.[User]
	(
	ID uniqueidentifier NOT NULL CONSTRAINT PK_User_ID PRIMARY KEY CLUSTERED (ID),
	[Name] nvarchar(200) NOT NULL CONSTRAINT User_Name_Check CHECK (trim([Name])<>''),
	Systemic bit NULL,
	Active bit NOT NULL Constraint User_Active_Default Default 1,
	CreatedBy uniqueidentifier NOT NULL,
	CreatedOn datetimeoffset NOT NULL Constraint User_CreatedOn_Default Default SYSDATETIMEOFFSET(),
	ModifiedBy uniqueidentifier NULL,
	ModifiedOn datetimeoffset NULL
	)  ON [PRIMARY]
```

- `CHECK (trim([X])<>'')` on every nvarchar, plus `ISJSON(...)=1` on JSON columns and `[Order] > 0`.
- Names: `PK_<T>_ID`, `<T>_<C>_Check`, `<T>_<C>_Default`, `IX_<T>_<C1>_<C2>` for every index, unique or not (no `UX_`);
  reuse an existing index name when you recreate it (for example as a filtered UNIQUE index).
- Dotted link tables and views: `[Form.RankGroup.Department]`, `[Session.View]`.

## Constants and lookups
- GUID constants declared inline in each proc, in one DECLARE block, named `@<Entity><Field><Value>`:
  `@SessionStatusCommented`, `@CommentStatusSigned`, `@EntityRelationTypeUserWithRole`, `@CoordinatorRole`.
- Enumerations are rows in `dbo.EntityLookup (Entity, Field, Code, Name, Description, Order, Active)`, relations in
  `dbo.EntityRelation`. New states are new `EntityLookup` rows with real `NEWID()` GUIDs, not strings or patterned ids.
- Systemic users: `(u.Systemic = 0 or u.Systemic is null)`.

## Authorisation gate
17 of 25 procs gate on EntityRelation; the ELSE throws:

```sql
IF EXISTS(
    SELECT 1
    FROM [dbo].[EntityRelation] r join [dbo].[User] u on r.EntityID=u.ID
    WHERE r.Entity = @UserEntity
      AND r.EntityID = @User
      AND r.RelatedEntity = @RoleEntity
      AND r.RelatedEntityID = @CoordinatorRole
      AND r.[Type] = @EntityRelationTypeUserWithRole
      AND u.Active=1
)
    UPDATE dbo.[Session] ...
ELSE
    THROW 52000, 'Not allowed', 1;
```

Authorisation comes before payload checks. Older procs take the actor as `@CreatedBy` / `@ModifiedBy`.

## Errors (Title Case)
- 51000 'Invalid Parameters' - parameters or payload.
- 52000 'Not allowed' - the caller may not do this (also 'Signature Unavailable').
- 53000 'Action Unsuccessful' - a write inside the transaction touched 0 rows (also 'Signing Unsuccessful').
- The gate's ELSE uses 51000 in some procs and 52000 in others: copy the sibling. Some single-statement writes return
  an empty OUTPUT set instead of throwing (UpdateComment, UpdateSession).

## Transactions, token, return shapes
- Several writes: `BEGIN TRY BEGIN TRAN ... COMMIT; SELECT * FROM #X; END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK;
  THROW; END CATCH`. Never `SET XACT_ABORT ON`. A single-statement write has no transaction.
- Token: `and ( [ModifiedOn] is null or ABS(DATEDIFF(ms,  [ModifiedOn], @LastModifiedOn)) < 1 )` - a NULL ModifiedOn passes.
- Shape copy: `SELECT * INTO #SessionOutput FROM [dbo].[Session] WHERE 1=2;`, then `OUTPUT INSERTED.* INTO #SessionOutput`.
- Two changed entities -> two result sets (DeleteComment, SignComment). No status/outcome selects.
- No nested EXEC anywhere: inline logic instead of calling one proc from another.
- List vs detail in one proc: `(@ID IS NOT NULL AND ID = @ID) OR (@ID IS NULL AND ...)`, and hide detail-only columns
  with `(CASE WHEN @ID IS NULL THEN NULL ELSE [EventDetails] END) [EventDetails]`.
- Search: `DECLARE @Name_Clean ... = NULLIF(TRIM(@Name), '');`, `OPTION (RECOMPILE)`.
- Dates: half-open ranges `>= @DateFrom AND < DATEADD(DAY, 1, @DateTo)`.
- Report HTML is built in views (`dbo.EscapeHtml`), not in flows; JSON columns are shredded in views with `OPENJSON`.
- No `N''` on ASCII literals.

## Known issues (report, don't copy, don't fix in passing)
- The master DDL holds plaintext SQL-login passwords in `CREATE LOGIN` and grants `db_owner` / `dbmanager` /
  `loginmanager` to a SQL login. Never copy them; recommend rotation and purging from history.
- `GetSessionsWithCriteria` live has `INTO #Sessions ... SELECT * FROM #Sessions;`, HEAD does not - start from live.
- `SaveAgreementDetails` has an IF without ELSE, so an unauthorised call silently does nothing. Keep the live body as
  it is (agreed); do not "harden" existing procs while building a feature.
- Typos are API: `CanceleSignatureAgreement`, a Greek `τ` inside `@EntityRelationTypeSessionWithDepτ`. Keep them.

## Assistant mistakes caught in review (do not repeat)
Banner comments, `SET XACT_ABORT ON`, `IF OBJECT_ID` guards, `CHECK ([Role] IN ('FORM_FILLER', ...))`, patterned GUIDs
(`A1E30D11-0001-...`), `UX_` names, trailing column comments, sentence-style codes 51001-51007, a nested
`INSERT ... EXEC`, `iif(exists(...))`, a `@FormData ... = NULL` upper-case default, a 200-line new proc where extending
an existing view / proc would do, and new semantic proc names (`BeginStagedAgreement`) where the codebase would add a
`...V2` of the existing proc.
