# InTTrust Power Platform skills for Claude Code

One Claude Code plugin, `pp`, with eight skills that carry how InTTrust builds and ships Power Platform apps, and one
session-start hook. The skills hold conventions and procedures only; everything that differs per project or per person
comes from two config files in each project folder (see `pp:pp-project-config`), and what the team has learned about a
project is Claude's own project memory, kept in that project's workspace repo (see `pp:pp-project-memory`).

| Skill | Use it when you... |
|---|---|
| `pp:pp-project-config` | set up a project folder (or yourself on a project), or need to know who owns / approves / deploys something |
| `pp:pp-project-memory` | want to save or share a memory or log entry for the team, or a release, incident or decision has just ended |
| `pp:pp-sql` | write, review or apply SQL (procs, tables, DDL); codebase profiles for Telework, Gaslog, Surveys |
| `pp:pp-flows` | build or change a Power Automate flow |
| `pp:pp-powerfx` | edit a canvas app (`.pa.yaml`, App.Formulas, screens) |
| `pp:pp-release` | pull, publish, export, import, promote to QA/PROD, plan a rollback |
| `pp:pp-test-verify` | test a change, seed fixtures, backfill data, or are about to say "done" |
| `pp:pp-prod-diagnosis` | investigate a production problem (read-only) |

## Install (once per person)

**Shortest.** Paste this into Claude Code (the CLI or the desktop app's Code tab). It reads the steps below from this
repo, so it never goes out of date:

```text
Set me up with the InTTrust Power Platform skills and my projects. With my own Git login, clone
https://inttrust-sa.ghe.com/Development/inttrust.powerplatform.claude-skills.git into a temporary folder (if git
is missing or the clone fails, tell me why - no access: ask the team; sign-in: run git ls-remote on that URL once
in my own terminal - and stop). Then read its README.md, section "Install (once per person)", and carry out the
"One prompt" steps 0-8 in this session, asking me only what they say to ask. Delete the temporary folder at the end.
```

**One prompt.** The same steps, to paste directly. It installs the plugin with your own Git login, turns on automatic
updates, clones the projects you work on (table "Projects" below) and sets you up on each:

```text
Install the InTTrust Power Platform skills for me and set up my projects - Claude Code plugin pp from marketplace
inttrust, repo https://inttrust-sa.ghe.com/Development/inttrust.powerplatform.claude-skills.git
0. Check the prerequisites; if one is missing, stop and tell me how to install it. Windows: git --version works
   and Git Bash exists (C:\Program Files\Git\bin\bash.exe, or the path in CLAUDE_CODE_GIT_BASH_PATH) -
   otherwise install Git for Windows, which also brings Git Credential Manager. macOS: xcode-select -p prints a
   path (otherwise xcode-select --install) and git credential-manager --version works (otherwise
   brew install --cask git-credential-manager).
1. Run git ls-remote on that repo with my own Git login. If it fails with TF401019, 403 or "not found", stop and
   tell me to ask the team for access. If it fails with "terminal prompts disabled", "unable to get",
   "Authentication failed" or 401, stop and tell me to run git ls-remote <repo> once in my own terminal (Git
   Credential Manager signs me in) and to say done.
2. Find the Claude Code CLI: claude on PATH, otherwise the executable of the process whose id is in the
   CLAUDE_PID environment variable (the CLI running this session). With it run "plugin marketplace add <repo>",
   then "plugin install pp@inttrust" - "already added" or "already installed" is fine. If you cannot run it,
   tell me to type /plugin marketplace add <repo> and /plugin install pp@inttrust here, and continue when I
   say done.
3. Only after step 2, because marketplace add rewrites the inttrust entry: read my ~/.claude/settings.json
   (create it if missing) and merge - never replace, keep it valid JSON - "autoUpdate": true into
   extraKnownMarketplaces.inttrust (keep its source), "pp@inttrust": true into enabledPlugins and
   "FORCE_AUTOUPDATE_PLUGINS": "1" into env.
4. Check that plugin list shows pp@inttrust enabled and that the three settings are in the file.
5. Find the marketplace clone on disk: the installLocation of the inttrust entry in
   ~/.claude/plugins/known_marketplaces.json (usually ~/.claude/plugins/marketplaces/inttrust). Show me the
   "Projects" table from its README.md and ask which project(s) I work on and where my Work folder is.
6. For each project I name whose status is "ready": run git ls-remote on its workspace repo with my own Git
   login (if that fails, sort the error as in step 1: no access - tell me to ask the project's lead for access and
   skip it; sign-in - tell me to sign in as in step 1 and retry when I say done), then clone it into
   <Work folder>/<Project>. If that folder already is a clone of that repo (git remote -v names it - for example
   my own folder synced from my other machine through OneDrive), use it as it is and run git pull --ff-only.
   If it exists, is not empty and is not that clone, don't clone over it: clone next to it and ask me what to
   keep. For any other status, use the folder if it already exists (synced from my other machine), otherwise
   tell me to set it up by hand (README "Set up a project") and skip it.
7. Read plugins/pp/skills/pp-project-config/SKILL.md in the marketplace clone and, for each cloned project,
   follow its "Setting up a person" in that folder, in this session (step 1 there is the clone you just did).
   Its step 2 points my auto memory at the project's memory/ folder: merge "autoMemoryDirectory" into
   <project>/.claude/settings.local.json - the absolute path with forward slashes, or a ~/ path that resolves
   on each machine if I use the folder from two machines through OneDrive. On Windows use the drive-letter
   form C:/... (pwd -W in Git Bash), never /c/... If my personal files are already there because the folder
   is synced from my other machine (settings.local.json, pp-project.local.yaml, CLAUDE.local.md), keep them:
   make their ~/ paths resolve here instead - on macOS a symlink from the missing ~/<folder> to my OneDrive
   folder under ~/Library/CloudStorage - check that <project>/memory/MEMORY.md opens through the
   autoMemoryDirectory path, and check this machine's identities (git, pac, browser profiles) against
   pp-project.local.yaml and tell me what differs; don't rewrite it.
8. Tell me to start a new session in each project folder and to check with /memory that the auto memory
   folder is that project's memory/.
```

**By hand.** In Claude Code - the CLI or the desktop app's Code tab:

```
/plugin marketplace add https://inttrust-sa.ghe.com/Development/inttrust.powerplatform.claude-skills.git
/plugin install pp@inttrust
```

Git uses your own GitHub Enterprise login (Git Credential Manager).

Then turn on automatic updates - ask Claude: **"turn on auto-update for the inttrust plugin marketplace"**. It merges
these two settings into your `~/.claude/settings.json` (the desktop app switches plugin auto-update off by default and
hides the `/plugin` toggle, so the settings file is the way):

```json
{
  "extraKnownMarketplaces": { "inttrust": { "autoUpdate": true } },
  "env": { "FORCE_AUTOUPDATE_PLUGINS": "1" }
}
```

(`inttrust` already has a `source` entry there after the `add` command - only `autoUpdate` is added to it. Running
`marketplace add` again rewrites that entry and drops `autoUpdate`, so merge it again afterwards.) Start a new
session. From then on new versions install in the background a few minutes into a session and load in the next one;
to update right away, run `/plugin marketplace update inttrust`.

## Projects

Each project has a workspace repo: a private repo here on GitHub Enterprise (org `Development`, named
`<Company>-<App>`) that holds only what is useful for Claude, never code. Your project folder is a clone of it: it
brings `.claude/pp-project.yaml`, `CLAUDE.md`, `AGENTS.md`, the project's memory (`memory/`, `log/`), `docs/`, and
`tools/` only when its scripts take every value as a parameter; the code repos are cloned inside it. Each person points
Claude's auto memory at `memory/`, so everyone on the project shares one memory.

| Project | Workspace repo | Status |
|---|---|---|
| Surveys | https://inttrust-sa.ghe.com/Development/HELPE-Surveys.git | ready |
| Telework | - | not yet |
| Gaslog | - | not yet |

Status: `ready` = clone it; `being created` or `not yet` = set up by hand from a teammate's folder (below).

## Set up a project

The one prompt above does this for every `ready` project. By hand:

1. Clone the project's workspace repo with your own Git login: `git clone <URL> "<Work folder>/<Project>"`. No
   workspace repo yet: from the project folder of whoever already works on it, take only `.claude/pp-project.yaml`,
   `CLAUDE.md`, `AGENTS.md` and the documents listed under `project.docs`. Never copy anyone's `*.local.*`,
   `CLAUDE.local.md` or `settings.local.json`.
2. Open the folder in Claude Code and say "set me up with pp-project-config". It points your auto memory at the
   project's `memory/` (your own `.claude/settings.local.json`), clones the code repos inside it, writes your
   `pp-project.local.yaml` (your accounts, browser and PAC profiles, test-mail allowlist) and lists the access you
   still need. Start a new session and check with `/memory` that the auto memory folder is the project's `memory/`.

A new project: the lead says "set up this project with pp-project-config". It writes `pp-project.yaml` and `CLAUDE.md`;
the lead creates the empty private `<Company>-<App>` repo in the `Development` org (e.g. `HELPE-Surveys`), gives the
project's people access, pushes the folder to it and adds a row above.

## What runs on your machine

Besides the skills, the plugin runs one script at every session start: `plugins/pp/hooks/session-start.sh` (POSIX sh
and git - Git Bash on Windows, which Git for Windows installs; sh on macOS). Outside a project folder it prints
nothing. In a project folder it fetches the workspace repo for at most 8 s with every sign-in prompt turned off,
fast-forwards your copy when it is strictly behind - your uncommitted edits stay, and it pulls nothing when an
incoming commit changes a file you edited (it never merges, rebases or stashes) - and adds the sync status, the memory files a pull changed and the newest log entries to the session. When a
pull changes `CLAUDE.md`, `AGENTS.md`, `.gitignore` or `.claude/`, the status names the files so you read them before
relying on them. While your auto memory is not pointed at the project's `memory/`, it says so and prints
`memory/MEMORY.md`. A failure only costs that session this summary.

## Change a skill

Branch, edit under `plugins/pp/`, bump `version` in `plugins/pp/.claude-plugin/plugin.json`, open a PR to `main`.
Teammates receive a new version only when that number changes.

- Never put people, accounts, passwords, tokens, connection strings or tenant ids in a skill - they belong in the
  project configs. Skills refer to roles (DB owner, PROD owner, SP approver, lead).
- Customer and environment facts (ids, URLs, team names, incident dates, work-folder paths) go to the project's
  `pp-project.yaml` or its memory, not into a skill.
- Codebase-specific conventions go in a skill's `references/<profile>.md`; a new codebase gets a new profile.
- Scripts live next to their skill (`scripts/`) and take their values as parameters. Hook scripts stay POSIX sh with
  LF line endings (`.gitattributes`) and are tested under Git Bash and macOS sh.
