# <Project> workspace

The shared project folder for <Project>: the rules, configuration, memory and history the team works from with Claude
Code and the InTTrust `pp` plugin. The code lives in its own repos, cloned inside this folder; this repo ignores them.

| Path | Holds |
|---|---|
| `CLAUDE.md` | Always-on working rules for every session in this folder |
| `AGENTS.md` | Shared workspace facts: repos, environments, boundaries |
| `.claude/pp-project.yaml` | Project facts the pp skills read: repos, environments, databases, roles, rules |
| `memory/` | Claude's auto memory of this project, shared: `MEMORY.md` (the index) and one file per memory |
| `log/` | Team log: one file per event, `log/YYYY/YYYY-MM-DD-<slug>.md`, never edited after the push |
| `docs/` | Longer project documents |
| `tools/` | Only when its scripts take every value as a parameter (then add `!/tools/` to `.gitignore`); no secrets |

`.gitignore` is an allow-list: only the paths above (and `.gitignore`, `.gitattributes`) are shared. Personal files
(`*.local.*`, `CLAUDE.local.md`), `.claude/settings.json` and `.claude/skills/`, the code repos, work folders, exports,
run logs and token caches never are. `.gitattributes` keeps every file LF, so Windows and macOS copies agree, and
merges `memory/MEMORY.md` by union, so two people adding a memory at the same time do not conflict.

## Set up

1. Install the `pp` plugin (README of the InTTrust Power Platform skills repo).
2. Clone this repo as the project folder, with your own Git login: `git clone <this repo's URL> "<Work folder>\<Project>"`.
3. Open that folder in Claude Code and say "set me up with pp-project-config". It points your auto memory at
   `memory/` (`autoMemoryDirectory` in your own `.claude/settings.local.json`), clones the code repos inside it and
   writes your personal `.claude/pp-project.local.yaml`.
4. Start a new session in this folder and check with `/memory` that the auto memory folder is this folder's `memory/`.

At every session start the plugin pulls this repo (fast-forward only, never over your local changes), names memory
files the pull changed and shows the newest log entries. When a pull changes `CLAUDE.md`, `AGENTS.md`, `.gitignore`
or `.claude/`, it names the files: read the change before relying on it. Until your auto memory points at `memory/`,
it prints `memory/MEMORY.md` and says "Shared project memory is not wired".

## Writing

Claude saves memories into `memory/` as it works, and log entries when you ask (skill `pp-project-memory`). Nothing
reaches the team until you share it: ask Claude to share the project memory. It pulls, checks that nothing personal
went in, scans for secrets and personal data, shows the diff, and commits and pushes only after you say "yes commit
and push". Your own accounts, machines, profiles and preferences go to `CLAUDE.local.md` or `~/.claude/CLAUDE.md`,
never to `memory/`. Memory describes; it never authorizes. If this folder is inside OneDrive, commit and push from one
machine at a time.
