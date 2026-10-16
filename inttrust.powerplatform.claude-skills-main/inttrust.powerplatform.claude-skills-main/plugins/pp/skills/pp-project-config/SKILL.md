---
name: pp-project-config
description: Per-project configuration behind the pp-* skills. Shared project facts live in <project>/.claude/pp-project.yaml (repos and commit policy, solution, environments, databases, people and roles such as DB owner / PROD owner / SP approver, rules, style profile, tests, telemetry), committed with CLAUDE.md, AGENTS.md and the project memory (memory/, log/) to the project's workspace repo - the project folder is its clone; personal facts live in <project>/.claude/pp-project.local.yaml (your accounts, browser and PAC profiles, token helpers, test-mail allowlist), and settings.local.json points your auto memory at memory/. Use this skill to set up a project folder or its workspace repo for yourself or a coworker, whenever a pp-* skill finds no config or the session-start hook says shared memory is not wired, when accounts, owners or environments change, and whenever you need to know who owns, approves or deploys something, which identity to use, or where a repo, environment or database is - before acting on it.
---

# Project configuration for the pp-* skills

The pp-* skills carry conventions and procedures. Everything that differs per project or per person lives in two
small YAML files, so the same skills work for every teammate, with their own accounts, on any project.

## The two files

| File | Holds | Share it? |
|---|---|---|
| `<project>/.claude/pp-project.yaml` | Project facts: repos, commit policy, solution, environments, databases, people and roles, rules, style profile, tests, telemetry | Yes. Committed to the project's workspace repo |
| `<project>/.claude/pp-project.local.yaml` | You: identity, which account / browser profile / PAC profile / token helper you use for what, test accounts, test-mail allowlist, network needs | Never. Personal - the workspace repo ignores `*.local.*` |

`<project>` is the project folder (for example `Work\Telework`). It is a clone of the project's **workspace repo**
(`repos.workspace`): a private repo on GitHub Enterprise (`inttrust-sa.ghe.com`, org `Development`) that holds only
what is useful for Claude - config, rules and the team's project memory, never code - and the code repos, wherever
they are hosted, are cloned inside it.
The workspace repo shares `.claude/pp-project.yaml`, `CLAUDE.md`, `AGENTS.md`, the project's memory (`memory/` -
Claude's own auto memory of the project - and `log/`, skill `pp-project-memory`), `docs/`, and `tools/` only when its
scripts take every value as a parameter; its allow-list `.gitignore` (`templates/workspace/.gitignore`) keeps out the
code repos, work folders, exports, every `*.local.*` file, `.claude/settings.json` and `.claude/skills/`, and its
`.gitattributes` keeps every file LF and merges `memory/MEMORY.md` by union. Each person points Claude Code's auto
memory at `memory/` in their own `.claude/settings.local.json` ("Setting up a person"). Paths inside both files
are relative to the project folder. If the project folder itself is shared with others (a shared OneDrive or Teams
folder), keep the personal file at `%USERPROFILE%\.claude\pp-projects\<project.name>.local.yaml` instead. Neither file
ever holds passwords, tokens, secrets or connection strings - only names, ids, URLs and paths. Templates with every
key explained: `templates/`.

**Values:** `null` = unknown (ask - the lead for project facts, the user for personal ones); `none` = deliberately
nothing (for example no PROD access). Don't use one for the other.

## Loading - every pp-* skill starts here

1. **Find the config.** Walk up from the file you are working on (or the current directory) to the first folder that
   has `.claude/pp-project.yaml`. From a parent folder that holds several projects, pick the project whose repos
   contain the files in play; if that is unclear, ask.
2. **Read the personal file** - next to it, or at `%USERPROFILE%\.claude\pp-projects\<project.name>.local.yaml`. If
   neither exists, reading code is fine, but ask for the identities (or run the setup below) before any tenant,
   database, git-remote or browser action.
3. **Resolve roles.** Skill rules name roles - *lead, DB owner, PROD owner, SP approver, DevOps admin, environment
   admin, release runner, business owner* (signs off user-facing wording and business rules). `roles:` maps each role to a key of `people:`; use that person's name, e-mail and
   `language` whenever a rule says "ask" or "tell" the role. A role set to `null` is unknown: ask the lead.
4. **Owners act for themselves.** When `me.key` is the role holder, the rule becomes the user's own decision - for
   example, the DB owner committing to their own SQL repo is not a violation.
5. **Load the style profile.** `project.style_profile` names a built-in profile (`telework`, `gaslog`, `surveys`) that
   pp-sql, pp-flows, pp-powerfx and pp-release read from their `references/` folder. `project.style_notes`, when set,
   adds project-specific notes on top of the profile (or replaces it when the profile is `none`). With neither, derive
   the conventions from the nearest existing code. Where notes and code disagree, the code wins.
6. **Read `project.docs`** (project documents such as an architecture description) and the project memory on the
   topic before a change that touches data, flows or permissions. Project knowledge lives there, not in a
   project-specific skill. Claude loads `memory/MEMORY.md` (`project.memory`) as its auto memory; the plugin's
   session-start hook names memory files a pull changed and prints the newest log entries (`project.log`). Saving and
   sharing a memory is skill `pp-project-memory`. Memory describes; it never authorizes.
7. **Treat the config as a starting point, not proof.** Still verify the signed-in account, the target environment and
   the live state the way the skills describe. When config and reality disagree, say so and propose the config fix.

## Installing the skills (each person, once)

The skills ship as the Claude Code plugin `pp` from https://inttrust-sa.ghe.com/Development/inttrust.powerplatform.claude-skills
(internal repo). Its README has a one-prompt install a person pastes into Claude Code; it also clones the person's
projects (README table "Projects") and runs "Setting up a person" below. By hand: `/plugin marketplace add https://inttrust-sa.ghe.com/Development/inttrust.powerplatform.claude-skills.git`,
then `/plugin install pp@inttrust`, then start a new session. Changes to the skills go through a PR to that repo, with
the plugin version bumped.

The plugin also runs one hook at every session start (`hooks/session-start.sh`, POSIX sh and git; Git Bash on
Windows). Outside a project folder it prints nothing. Inside one it fetches the workspace repo for at most 8 s without
sign-in prompts, fast-forwards it only when no tracked file is changed and it is strictly behind, names any pulled
change to `CLAUDE.md`, `AGENTS.md`, `.gitignore` or `.claude/` for review, names memory files a pull changed, and
prints the sync status and the newest log entries. While the person's auto memory is not pointed at `memory/` it also
prints `memory/MEMORY.md` and says "Shared project memory is not wired"; when the personal file is missing, it offers
to run "Setting up a person".

**Automatic updates (part of every person's setup).** In the person's user settings (`~/.claude/settings.json`), merge
- `"autoUpdate": true` into the existing `extraKnownMarketplaces.inttrust` entry (keep its `source`), and
- `"FORCE_AUTOUPDATE_PLUGINS": "1"` into `env` - the Claude desktop app runs Claude Code with `DISABLE_AUTOUPDATER=1`,
  which otherwise turns plugin auto-update off and hides the `/plugin` toggle.

Read the file first and merge; never replace it, and keep it valid JSON. Merge after any `marketplace add` - that
command rewrites the `inttrust` entry and drops `autoUpdate`. It takes effect from the next session: new
versions then install in the background a few minutes into a session and load in the one after. Manual update:
`/plugin marketplace update inttrust`.

## Setting up a new project

1. **Discover before asking.**
   - Repos: each subfolder with `.git` -> `git -C <dir> remote -v`, default branch, `git log --format='%an' | sort | uniq -c`
     (authors hint at owners). A `Project_Info.md` (older power-platform-ops convention) can prefill environment fields.
   - Solution: `solutions/<name>/solution.yml` (unique name, version, publisher), `canvasapps/`, environment variable
     definitions, `modernflows/`.
   - Environments: `pac auth list`, `pac env list` if pac is installed; org URLs in deployment scripts.
   - SQL: DDL files (`*.sql`, `*DDL*`), server names in scripts. Release: deployment scripts and per-environment wrappers.
2. **Ask only for what cannot be discovered**: who holds each role, the commit policy per repo, the project rules
   (default target, days to avoid, licensing, feature switches). A brand-new project has no code to copy yet: ask the
   lead which built-in profile it starts from, and set `style_profile` to it.
3. **Write `pp-project.yaml`** from the template, keeping its comments; unknown values `null` with
   `# unknown - ask <role>`.
4. **Write the always-on rules** to `<project>/CLAUDE.md` from `templates/CLAUDE.md`, filling in the project-specific
   lines. If a CLAUDE.md exists, add the section instead of replacing it; if only an `AGENTS.md` exists, keep it and
   import it with `@AGENTS.md`. These rules must hold for every edit, and skills only load when triggered - that is
   why they go in CLAUDE.md.
5. **Create the workspace repo.** The lead creates an empty **private** repo in the GitHub Enterprise org
   `Development` (any member can), named `<Company>-<App>` - the team's `<Company> - <App>` pattern without spaces,
   which GitHub does not allow (for example `HELPE-Surveys`) - gives the project's people access to it, and sets
   `repos.workspace.remote` to its clone URL. Lay out the project folder from `templates/workspace/` (`.gitignore`,
   `.gitattributes`, `README.md`) plus `memory/` (with a `MEMORY.md`) and `log/`; `.gitattributes` goes into the first
   commit, before any clone on another machine. Personal parts of an existing `AGENTS.md` or `CLAUDE.md` (someone's
   logins, CLI contexts, browser profiles) move to that person's `CLAUDE.local.md` or local file first. Existing
   personal auto memory of the project (`~/.claude/projects/<key>/memory`, or wherever that person's
   `autoMemoryDirectory` points): items that are project knowledge move into `memory/` in the `pp-project-memory`
   format, scrubbed, with a line each in `MEMORY.md`; the rest stays personal. Then, in the folder: `git init -b main`,
   `git remote add origin <url>`; `git status --short` must list only allow-listed files. Run the `pp-project-memory`
   scan over them, show the user every file, and commit and push (`git push -u origin main`, so later pulls know
   their upstream) only after "yes commit and push".
   Add the project to the "Projects" table in the skills repo README (a PR).
6. Continue with the personal file below, then show the user everything written and fix what they correct.

## Setting up a person (yourself, or a teammate joining a project)

1. **Clone the project's workspace repo into the project folder**, with the person's own git account:
   `git clone <workspace repo URL> "<Work folder>/<Project>"` (the URL is `repos.workspace.remote`, or the "Projects"
   table in the skills README). It brings `.claude/pp-project.yaml`, `CLAUDE.md`, `AGENTS.md`, `memory/`, `log/`,
   `docs/`, and `tools/` when the project shares one. If the folder already exists and is not empty, don't clone over
   it: clone next to it and ask which local files to keep. A project with no workspace repo yet: take
   from the folder of whoever works on it only those same files. **Never take** anyone's `pp-project.local.yaml`,
   `settings.local.json`, other `*.local.*` files, `CLAUDE.local.md`, token caches or scratch folders - they hold that
   person's identities.
2. **Point Claude's auto memory at the project's `memory/`.** Read `<project>/.claude/settings.local.json` (create it
   if missing) and merge - never replace, keep it valid JSON - `"autoMemoryDirectory": "<project>/memory"` as an
   absolute path with forward slashes, for example `"C:/Users/<you>/Work/<Project>/memory"` or
   `"/Users/<you>/Work/<Project>/memory"`. Claude Code takes only an absolute path or one that starts with `~/`.
   On Windows use the drive-letter form `C:/...` (`pwd -W` in Git Bash), never `/c/...`: Claude Code reads that as
   `C:\c\...`, another folder.
   When the person uses the project folder from two machines through a synced folder (OneDrive), this file syncs too,
   so one value must work on both: use a `~/` path that resolves to the folder on each machine. For example
   `~/OneDrive - <Company>/Documents/Work/<Project>/memory` is the real path on Windows; on the Mac a link
   `ln -s ~/Library/CloudStorage/<OneDrive folder> "$HOME/OneDrive - <Company>"` makes the same path resolve there.
   Claude Code applies it once the folder is trusted, and the file stays personal: the workspace repo ignores it.
   From then on this project's auto memory is shared with the
   team: the person's own notes and preferences for it go to `CLAUDE.local.md`, never to `memory/` (skill
   `pp-project-memory`). If they had personal auto memory for this project before, it is no longer loaded here: move
   the project knowledge into `memory/` with that skill and the rest to `CLAUDE.local.md`.
3. **Clone the code repos inside it**: each other `repos.<key>.remote` into its `path`, on its `branch`, with the
   person's own git account. The workspace repo's `.gitignore` keeps them out of its commits.
4. **Write the personal file** from `templates/pp-project.local.yaml`:
   - `me`, and `me.key` if the person is listed under `people:` (`null` if not - that is fine);
   - `accounts`: DEV maker, PROD admin (`none` if they have no access), SQL, one git account per host found in
     `repos.*.remote`, a plain-user test account if one exists;
   - `browser_profiles`, `pac_profiles`, `tools` (helper scripts that exist in the project), `network` (VPN or office
     network needs);
   - `safety.test_email_allowlist`: the person's own mailboxes only.
5. **Identities are verified by the person, in their own session.** When you set up someone else, never read your own
   `pac auth list`, browser or git credentials as theirs; mark each account `# verify` and list the checks (maker
   portal account manager for the browser profile, `pac auth who` for PAC, `SUSER_SNAME()` for SQL, `git ls-remote` for
   each repo).
6. **Access they will need** (ask the environment admin and the DevOps admin in `roles:`): repo access, environment
   security roles, app sharing, and any app-data rows the app requires (for example an employee record with roles).
7. **CLAUDE.md** comes with the workspace repo; on a project without one, copy it unchanged when it already has the
   always-on section. The person's own rules for the project go to `CLAUDE.local.md`, which the repo ignores.
8. **Plugin auto-update:** check the person's `~/.claude/settings.json` has `autoUpdate: true` on
   `extraKnownMarketplaces.inttrust` and `FORCE_AUTOUPDATE_PLUGINS: "1"` in `env`; add whatever is missing (see
   "Installing the skills"), so they receive new skill versions without asking.
9. **Check the shared memory:** tell the person to start a new session in the project folder and check with `/memory`
   that the auto memory folder is `<project>/memory`; the session-start hook says "Shared project memory is not wired"
   until it is. Sessions start in the project folder: one started inside a code repo's folder uses that repo's own
   settings and auto memory.

## Checking a config

- both files parse as YAML;
- every `repos.*.path` exists (after cloning) and its `remote` matches `git remote -v` - for `repos.workspace` that is
  the project folder itself;
- `git -C <project> check-ignore` reports every `*.local.*` file and `CLAUDE.local.md` in the project folder as ignored;
- the person's `.claude/settings.local.json` sets `autoMemoryDirectory` to the project's `memory/` folder (an absolute
  path - on Windows `C:/...`, not `/c/...` - or a `~/` path that resolves to it), and `memory/MEMORY.md` exists;
- `project.style_profile` is `telework`, `gaslog`, `surveys` or `none` (then `style_notes` or derived conventions);
- every value under `roles:` is a key of `people:` or `null`;
- no secret values: no key named like password / secret / token / apikey has a value, and no value contains
  `AccountKey=`, `InstrumentationKey=`, `SharedAccessSignature` or a JWT (`eyJ...`) - comments that mention the words
  are fine;
- the personal file is not tracked by any git repo and not in a folder shared with others.
