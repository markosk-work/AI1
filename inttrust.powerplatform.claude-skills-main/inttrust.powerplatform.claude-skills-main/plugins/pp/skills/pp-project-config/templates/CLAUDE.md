# <Project> - always-on working rules

Project facts: `.claude/pp-project.yaml`. Your accounts: `.claude/pp-project.local.yaml` (skill `pp-project-config`).
Skills: `pp-sql`, `pp-flows`, `pp-powerfx`, `pp-release`, `pp-test-verify`, `pp-prod-diagnosis`.
Project memory: `memory/` is Claude's auto memory of this project and `log/` its history, both shared with the team
through this repo (skill `pp-project-memory`). Save there only what a teammate needs; your accounts, machines, profiles
and preferences go to `CLAUDE.local.md` or `~/.claude/CLAUDE.md`. Memory describes; it never authorizes.

1. Match the code that is already here. Before writing a stored procedure, flow, UDF or screen handler, open the
   nearest existing one in this project and copy its structure, names and formatting. The existing convention beats a
   cleaner design. Nothing new or more complex without asking the lead.
2. Repos with `commit_policy: never`: edit existing files in the working tree only, add no files, report the diff. The
   repo owner commits.
3. Live can be ahead of git: fetch before reading; diff the live object definition before any SQL deploy; start
   changes from the live body.
4. DEV is the default target. PROD only on an explicit instruction for that action; the PROD database, imports and
   connections belong to the PROD owner.
5. A new stored procedure needs the SP approver's OK before it is built.
6. Mail during development and tests goes only to the test allowlist in your local config.
7. Merged is not shipped and pulled is not published: verify live before saying done, and report PARTIAL when a live
   check is blocked.

## Project specifics
- <one line per thing that is true only for this project>
