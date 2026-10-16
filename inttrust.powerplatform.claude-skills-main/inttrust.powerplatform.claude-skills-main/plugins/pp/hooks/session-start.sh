#!/bin/sh
# pp plugin - SessionStart hook: tells Claude where the project's shared memory stands - memory/, Claude's auto memory
# of the project, kept in the project's workspace repo - and shows the newest entries of its log.
#
# Outside a project folder (no .claude/pp-project.yaml in the session's folder or above) it prints nothing.
# Inside one that is a clone of the project's workspace repo (repos.workspace.remote) it fetches for at most
# FETCH_SECONDS without any sign-in prompt, and fast-forwards only when no tracked file is changed and the copy is
# strictly behind. It never merges, rebases or stashes. A pull that changed CLAUDE.md, AGENTS.md, .gitignore,
# .claude/ or tools/ is named for review; memory files it changed are named for re-reading. Then it prints the sync
# status, whether auto memory is wired to memory/ (if not, MEMORY.md itself), and the newest log entries.
# Any failure: exit 0 with at most one line. Needs only POSIX sh, git, awk, sort and find, so it runs under
# Git Bash on Windows and sh on macOS. Skill pp-project-memory describes the memory, pp-project-config the keys.

FETCH_SECONDS=8
MAX_CHARS=8000
LOG_ENTRIES=10
MEMORY_LINE=300
MEMORY_FILES=20

# No sign-in prompt of any kind: terminal, Git Credential Manager, askpass helpers (an empty GIT_ASKPASS also stops
# core.askPass and SSH_ASKPASS - needed where git is older than 2.47 and ignores credential.interactive), ssh's
# askpass. No optional index refresh by git status, so the hook does not rewrite .git/index (OneDrive) every time.
LC_ALL=C
GIT_TERMINAL_PROMPT=0
GCM_INTERACTIVE=never
GIT_ASKPASS=
SSH_ASKPASS_REQUIRE=never
GIT_OPTIONAL_LOCKS=0
export LC_ALL GIT_TERMINAL_PROMPT GCM_INTERACTIVE GIT_ASKPASS SSH_ASKPASS_REQUIRE GIT_OPTIONAL_LOCKS
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
TAB=$(printf '\t')

# awk helper shared by the readers below: a YAML scalar without blanks, a trailing " # comment" or its quotes.
AWK_UNQ='
function unq(s,   c) {
	sub(/^[ \t]+/, "", s); c = substr(s, 1, 1)
	if (c != "\"" && c != q) sub(/[ \t]+#.*$/, "", s)
	sub(/[ \t]+$/, "", s)
	if (length(s) >= 2 && (c == "\"" || c == q) && substr(s, length(s), 1) == c) s = substr(s, 2, length(s) - 2)
	return s
}
# The first n bytes of s plus "...", without the last, possibly cut, UTF-8 character (LC_ALL=C counts bytes).
function clip(s, n) {
	s = substr(s, 1, n); sub(/[\300-\367][\200-\277]*$/, "", s)
	return s "..."
}'

# The wanted keys of a YAML file as "path<TAB>value" lines. Simple "key: value" and "key: { a: b }" lines only;
# block scalars and lists are skipped; null, none and <placeholders> count as unset. Usage: yaml_values <file> <key>...
yaml_values() {
	file=$1; shift
	awk -v q="'" -v want=" $* " "$AWK_UNQ"'
	function out(p, v) {
		v = unq(v)
		if (v != "" && v != "null" && v != "none" && substr(v, 1, 1) != "<" && index(want, " " p " ")) print p "\t" v
	}
	BEGIN { block = -1; n = 0 }
	{
		sub(/\r$/, "")
		if ($0 ~ /^[ \t]*(#|$)/) next
		match($0, /^ */); ind = RLENGTH
		if (block >= 0 && ind > block) next
		block = -1
		line = substr($0, ind + 1)
		if (line !~ /^[A-Za-z0-9_.-]+:([ \t]|$)/) next
		k = line; sub(/:.*/, "", k)
		v = line; sub(/^[^:]*:[ \t]*/, "", v)
		c = substr(v, 1, 1)
		if (c != "\"" && c != q) sub(/[ \t]+#.*$/, "", v)
		while (n > 0 && ind <= lvl[n]) n--
		n++; lvl[n] = ind; key[n] = k
		path = key[1]; for (i = 2; i <= n; i++) path = path "." key[i]
		if (c == ">" || c == "|") { block = ind; next }
		if (v ~ /^\{.*\}$/) {
			m = split(substr(v, 2, length(v) - 2), parts, ",")
			for (i = 1; i <= m; i++) {
				if (parts[i] !~ /:/) continue
				kk = parts[i]; sub(/:.*/, "", kk); sub(/^[ \t]+/, "", kk)
				vv = parts[i]; sub(/^[^:]*:/, "", vv)
				out(path "." kk, vv)
			}
			next
		}
		out(path, v)
	}' "$file"
}

# First folder at or above $1 that has .claude/pp-project.yaml.
find_root() {
	d=${1%/}
	while [ -n "$d" ]; do
		if [ -f "$d/.claude/pp-project.yaml" ]; then
			printf '%s\n' "$d"
			return 0
		fi
		p=${d%/*}
		[ "$p" = "$d" ] && return 1
		d=$p
	done
	return 1
}

# Name of the git remote whose URL is the workspace repo. URLs are compared reduced to host/path, so the https,
# ssh, user@ and visualstudio.com spellings of one repo match.
workspace_remote() {
	git -C "$root" remote -v 2>/dev/null | awk -v want="$remote_url" '
	function norm(u,   org) {
		u = tolower(u)
		sub(/^[a-z+]*:\/\//, "", u); sub(/^[^\/@]*@/, "", u); gsub(/%20/, " ", u)
		sub(/^ssh\.dev\.azure\.com:v3\//, "dev.azure.com/", u)
		if (match(u, /^[^\/:]*:/)) u = substr(u, 1, RLENGTH - 1) "/" substr(u, RLENGTH + 1)
		if (match(u, /^[^.\/]*\.visualstudio\.com\//)) {
			org = substr(u, 1, index(u, ".") - 1); u = "dev.azure.com/" org "/" substr(u, RLENGTH + 1)
		}
		sub(/\/defaultcollection\//, "/", u); sub(/\/_git\//, "/", u); sub(/\/+$/, "", u); sub(/\.git$/, "", u)
		return u
	}
	BEGIN { want = norm(want) }
	{ name = $1; sub(/^[^ \t]*[ \t]+/, ""); sub(/[ \t]+\((fetch|push)\)$/, "") }
	norm($0) == want { print name; exit }'
}

# Runs a command for at most $1 seconds, its stderr into file $2. A watchdog stops it at the limit; the watchdog
# takes its own sleep down with it when the command ends first, so nothing is left running.
run_limited() {
	limit=$1 errfile=$2; shift 2
	"$@" </dev/null >/dev/null 2>"$errfile" &
	pid=$!
	(
		trap 'kill "$s" 2>/dev/null; exit 0' TERM
		sleep "$limit" &
		s=$!
		wait "$s"
		kill "$pid" 2>/dev/null
	) </dev/null >/dev/null 2>&1 &
	watchdog=$!
	wait "$pid"
	rc=$?
	kill "$watchdog" 2>/dev/null
	return "$rc"
}

commits() { if [ "$1" -eq 1 ]; then echo "1 commit"; else echo "$1 commits"; fi; }

# Fetches, then fast-forwards when that is safe. Prints one status line.
sync_status() {
	if ! command -v git >/dev/null 2>&1; then
		echo "git not found - not synced"
		return
	fi
	# At the top of a work tree this prints just "true"; in a subfolder of another repo it adds "../".
	if [ "$(git -C "$root" rev-parse --is-inside-work-tree --show-cdup 2>/dev/null)" != true ]; then
		if [ -n "$remote_url" ]; then
			echo "this folder is not a clone of the workspace repo yet - memory/ and log/ are local files only"
		else
			echo "no workspace repo in the config (repos.workspace) - memory/ and log/ are local files only"
		fi
		return
	fi
	if [ -z "$remote_url" ]; then
		echo "no workspace repo in the config (repos.workspace) - not synced"
		return
	fi
	rname=$(workspace_remote)
	if [ -z "$rname" ]; then
		echo "its git remote is not repos.workspace.remote - not synced"
		return
	fi

	# Batch-mode ssh, unless the user chose their own ssh command (GIT_SSH, GIT_SSH_COMMAND or core.sshCommand).
	if [ -z "$GIT_SSH$GIT_SSH_COMMAND" ] && [ -z "$(git -C "$root" config --get core.sshCommand 2>/dev/null)" ]; then
		GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=5'
		export GIT_SSH_COMMAND
	fi

	offline=
	if [ "$fetch" = yes ]; then
		errfile=$(mktemp 2>/dev/null) || errfile=/dev/null
		if ! run_limited "$FETCH_SECONDS" "$errfile" git -C "$root" -c credential.interactive=false -c gc.auto=0 \
			-c maintenance.auto=false -c fetch.recurseSubmodules=false fetch --quiet --no-tags "$rname" "$branch"; then
			offline="offline - could not fetch (no network, VPN or server, or over $FETCH_SECONDS s)"
			if [ "$errfile" = /dev/null ]; then
				:
			elif grep -Eiq "couldn't find remote ref" "$errfile"; then
				offline="the server has no branch $branch yet - push first"
			elif grep -Eiq 'TF401019|not found|does not exist' "$errfile"; then
				offline="fetch refused - the workspace repo does not exist or you have no access to it"
			elif grep -Eiq 'authenticat|could not read (username|password)|unable to get password|prompts disabled' \
				"$errfile" || grep -Eiq 'interactivity|denied|401|403' "$errfile"; then
				offline="sign-in needed - run git fetch in the project folder yourself once"
			fi
			offline="$offline; showing the local copy"
		fi
		[ "$errfile" = /dev/null ] || rm -f "$errfile"
	fi
	# Only tracked files count as local changes: a new untracked file (a new memory, .DS_Store, desktop.ini) does not
	# stop the pull, and merge --ff-only still refuses to overwrite one.
	head= tracking= ab= dirty= review= memchanged=
	while IFS= read -r line; do
		case $line in
		'# branch.head '*) head=${line#\# branch.head } ;;
		'# branch.upstream '*) tracking=${line#\# branch.upstream } ;;
		'# branch.ab '*) ab=${line#\# branch.ab } ;;
		'#'* | '') ;;
		*) dirty=yes ;;
		esac
	done <<EOF
$(git -C "$root" status --porcelain=v2 --branch --untracked-files=no 2>/dev/null)
EOF
	if [ "$tracking" != "$rname/$branch" ] || [ -z "$ab" ]; then
		ab=$(git -C "$root" rev-list --left-right --count "HEAD...refs/remotes/$rname/$branch" 2>/dev/null)
	fi
	set -- $ab
	ahead=${1#+} behind=${2#-}
	case $ahead$behind in '' | *[!0-9]*) ahead=0 behind=0 ;; esac
	mine=
	[ "$ahead" -gt 0 ] && mine=$(commits "$ahead")
	[ -n "$dirty" ] && mine="${mine:+$mine and }uncommitted files"

	if [ "$head" != "$branch" ]; then
		msg="on branch $head, not $branch - not pulled"
	elif [ -n "$offline" ]; then
		msg=$offline
		[ -n "$mine" ] && msg="$msg; local changes not pushed ($mine)"
	elif ! git -C "$root" rev-parse --verify -q "refs/remotes/$rname/$branch" >/dev/null 2>&1; then
		msg="branch $branch is not on the server yet - nothing to pull; push it first"
		[ -n "$mine" ] && msg="$msg ($mine)"
	elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
		msg="diverged: $(commits "$ahead") here, $(commits "$behind") on the server - see skill pp-project-memory before writing"
	elif [ "$ahead" -gt 0 ] || { [ -n "$dirty" ] && [ "$behind" -eq 0 ]; }; then
		msg="local changes not pushed ($mine)"
		[ "$behind" -gt 0 ] && msg="$msg; $(commits "$behind") on the server not pulled"
	elif [ "$behind" -gt 0 ] && [ "$fetch" = yes ]; then
		# Auto memory edits tracked files all the time, so uncommitted edits do not stop the pull: merge --ff-only keeps
		# them and refuses (changing nothing) when an incoming commit touches one of the edited files.
		old=$(git -C "$root" rev-parse --verify -q HEAD 2>/dev/null)
		if git -C "$root" merge --ff-only --quiet "refs/remotes/$rname/$branch" >/dev/null 2>&1; then
			msg="pulled $(commits "$behind")"
			[ -n "$dirty" ] && msg="$msg; local changes not pushed (uncommitted files)"
			# Rules, config and scripts arrive without review: name them, so the user reads them before relying on them.
			new=$(git -C "$root" rev-parse --verify -q HEAD 2>/dev/null)
			changed=$(git -C "$root" diff --name-only "$old" "$new" -- CLAUDE.md AGENTS.md .gitignore \
				.gitattributes .claude tools 2>/dev/null | tr '\n' ' ')
			range="$(printf '%.7s' "$old") $(printf '%.7s' "$new")"
			[ -z "$changed" ] ||
				review="The pull changed ${changed% } - show the user git diff $range -- <file> before relying on them."
			# Auto memory may have loaded MEMORY.md before this pull: name what changed, so it is read again.
			changed=$(git -C "$root" diff --name-only "$old" "$new" -- "$memory" 2>/dev/null |
				awk -v max="$MEMORY_FILES" 'NR <= max { printf "%s%s", (NR > 1 ? " " : ""), $0 }
					END { if (NR > max) printf " and %d more", NR - max }')
			[ -z "$changed" ] ||
				memchanged="$memory/ changed on the server - re-read MEMORY.md and those files: $changed"
		elif [ -n "$dirty" ]; then
			msg="$(commits "$behind") on the server not pulled: they change files you edited here - commit or set your edits aside, then pull (skill pp-project-memory)"
		else
			msg="$(commits "$behind") on the server, fast-forward failed - not pulled"
		fi
	elif [ "$behind" -gt 0 ]; then
		msg="$(commits "$behind") on the server not pulled"
	else
		msg="up to date"
	fi
	[ "$fetch" = yes ] || msg="$msg (not fetched after compaction)"
	echo "$msg - branch $branch"
	[ -z "$review" ] || echo "$review"
	[ -z "$memchanged" ] || echo "$memchanged"
}

# The value of a JSON string key anywhere in a settings file, JSON escapes undone (\uXXXX kept as written). The last
# one wins, as in JSON.parse. Prints nothing when the key is not set. Usage: json_string <file> <key>
json_string() {
	awk -v key="\"$2\"" '
	{ sub(/\r$/, ""); s = s $0 "\n" }
	END {
		found = ""
		while ((i = index(s, key)) > 0) {
			s = substr(s, i + length(key))
			if (!match(s, /^[ \t\n]*:[ \t\n]*"/)) continue
			s = substr(s, RLENGTH + 1); v = ""
			while (s != "" && substr(s, 1, 1) != "\"") {
				c = substr(s, 1, 1)
				if (c == "\\") {
					s = substr(s, 2); c = substr(s, 1, 1)
					if (c == "u") c = "\\u"; else if (c ~ /[bfnrt]/) c = " "
				}
				v = v c; s = substr(s, 2)
			}
			found = v
		}
		if (found != "") print found
	}' "$1"
}

# A path with backslashes turned into slashes and a leading ~/ expanded with $HOME, as Claude Code expands it.
expand_path() {
	p=$(printf '%s' "$1" | tr '\\' /)
	case $p in '~/'*) p=$(printf '%s' "$HOME" | tr '\\' /)/${p#??} ;; esac
	printf '%s\n' "$p"
}

# A path in one spelling for comparison: C:/x and /c/x alike, no doubled or trailing slash, lower case.
norm_path() {
	expand_path "$1" | awk '{
		s = tolower($0); gsub(/\/+/, "/", s); gsub(/\/\.\//, "/", s); sub(/\/\.?$/, "", s)
		if (s ~ /^[a-z]:(\/|$)/) s = "/" substr(s, 1, 1) substr(s, 3)
		print s
	}'
}

# The physical path of an existing folder, for comparison: links resolved and, on Windows (cygpath comes with Git for
# Windows), the long name instead of a short one such as USERNA~1.
canon_dir() {
	p=$(cd "$1" 2>/dev/null && pwd -P) || return 1
	if command -v cygpath >/dev/null 2>&1; then p=$(cygpath -l -m "$p" 2>/dev/null) || return 1; fi
	norm_path "$p"
}

# Whether this session's auto memory is the project's memory/ folder. Claude Code reads settings.local.json at the
# root of the session's git repo (outside git, in the session's folder), so a session started inside a code repo
# cloned in the project uses that repo's file. Sets nested to that repo's folder name when it is not the project's.
memory_wired() {
	top= rtop= nested=
	if command -v git >/dev/null 2>&1; then
		top=$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)
		rtop=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)
	fi
	[ -z "$top" ] || [ "$(norm_path "$top")" = "$(norm_path "$rtop")" ] || nested=${top##*/}
	set_to=
	f=${top:-$start}/.claude/settings.local.json
	[ -f "$f" ] && set_to=$(json_string "$f" autoMemoryDirectory)
	# Claude Code takes only an absolute path or one that starts with ~/.
	case $set_to in '~/'* | /* | [A-Za-z]:[\\/]*) ;; *) return 1 ;; esac
	# On Windows Claude Code reads a Git Bash path such as /c/Users/... as C:\c\Users\..., a different folder.
	case $set_to in /*) [ "$OS" = Windows_NT ] && return 1 ;; esac
	want=$root/$memory
	[ "$(norm_path "$set_to")" = "$(norm_path "$want")" ] && return 0
	a=$(canon_dir "$(expand_path "$set_to")") && b=$(canon_dir "$want") && [ "$a" = "$b" ]
}

# "Project memory (memory/MEMORY.md ...):" and the index's non-blank lines, within $1 characters - for a session
# whose auto memory does not load it. Lines longer than MEMORY_LINE characters are cut.
memory_index() {
	f=$root/$memory/MEMORY.md
	if [ ! -f "$f" ]; then
		echo "Project memory: none yet ($memory/MEMORY.md does not exist)"
		return
	fi
	awk -v q="'" -v max="$1" -v rel="$memory/MEMORY.md" -v width="$MEMORY_LINE" "$AWK_UNQ"'
	{ sub(/\r$/, "") }
	/^[ \t]*$/ { next }
	{ n++; line[n] = (length($0) > width ? clip($0, width - 3) : $0) }
	END {
		if (n == 0) { print "Project memory: none yet (" rel " is empty)"; exit }
		head = "Project memory (" rel " - read it as your auto memory until it is wired):"
		print head; total = length(head) + 1
		for (i = 1; i <= n; i++) {
			if (total + length(line[i]) + 1 > max - 80) {
				print "- ... " (n - i + 1) " more lines not shown - read " rel " yourself"
				exit
			}
			total += length(line[i]) + 1; print line[i]
		}
	}' "$f"
}

# "Log (log/, N entries, newest first):" and the newest LOG_ENTRIES as "- YYYY-MM-DD - title".
log_index() {
	if [ ! -d "$root/$logs" ]; then
		echo "Log: none yet ($logs/ does not exist)"
		return
	fi
	find "$root/$logs" -type f -name '*.md' 2>/dev/null | awk -F/ '$NF != "README.md" { print $NF "\t" $0 }' |
		sort -r | awk -F "$TAB" -v q="'" -v max="$LOG_ENTRIES" -v rel="$logs" "$AWK_UNQ"'
	function entry(f,   b, d, s, t, line, infm, n) {
		while ((getline line < f) > 0) {
			n++; sub(/\r$/, "", line)
			if (n == 1 && line ~ /^---[ \t]*$/) { infm = 1; continue }
			if (infm && line ~ /^---[ \t]*$/) { infm = 0; continue }
			if (infm && line ~ /^title:/) { sub(/^title:/, "", line); t = unq(line); continue }
			if (infm && line ~ /^date:/) { sub(/^date:/, "", line); d = unq(line); continue }
			if (!infm && t == "" && line ~ /^# /) { t = substr(line, 3); break }
			if (!infm && t != "") break
		}
		close(f)
		b = f; sub(/.*\//, "", b); sub(/\.md$/, "", b); s = b
		if (b ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) { d = substr(b, 1, 10); s = substr(b, 12) }
		if (t == "") t = s
		if (length(t) > 160) t = clip(t, 157)
		return "- " (d == "" ? "(no date)" : d) " - " t
	}
	{ count++; if (count <= max) text[count] = entry($2) }
	END {
		if (count == 0) { print "Log: none yet (" rel "/ is empty)"; exit }
		print "Log (" rel "/, " count " entries, newest first):"
		for (i = 1; i <= count && i <= max; i++) print text[i]
	}'
}

main() {
	input=
	[ -t 0 ] || input=$(cat 2>/dev/null)
	fetch=yes
	case $input in *'"source":"compact"'* | *'"source": "compact"'*) fetch=no ;; esac

	start=$PWD
	if ! root=$(find_root "$start"); then
		start=$(printf '%s' "$CLAUDE_PROJECT_DIR" | tr '\\' /)
		[ -n "$start" ] && root=$(find_root "$start") || return 0
	fi

	name= remote_url= branch= memory= logs=
	values=$(yaml_values "$root/.claude/pp-project.yaml" project.name project.memory project.log \
		repos.workspace.remote repos.workspace.branch project.workspace project.workspace.remote \
		project.workspace.branch) || return 2
	while IFS="$TAB" read -r k v; do
		case $k in
		project.name) name=$v ;;
		project.memory) memory=${v%/} ;;
		project.log) logs=${v%/} ;;
		repos.workspace.remote) remote_url=$v ;;
		repos.workspace.branch) branch=$v ;;
		project.workspace | project.workspace.remote) [ -n "$remote_url" ] || remote_url=$v ;;
		project.workspace.branch) [ -n "$branch" ] || branch=$v ;;
		esac
	done <<EOF
$values
EOF
	[ -n "$name" ] || name=${root##*/}
	# The branch comes from the shared file and ends up on git's command line: a plain branch name or main.
	case $branch in '' | -* | *[!A-Za-z0-9._/-]*) branch=main ;; esac
	# So does the memory folder (a pathspec): a plain path inside the project, or memory.
	case $memory in '' | -* | /* | *..* | *[!A-Za-z0-9._/-]*) memory=memory ;; esac
	[ -n "$logs" ] || logs=log

	status=$(sync_status)
	log_part=$(log_index)
	shown=$(cd "$root" 2>/dev/null && { pwd -W 2>/dev/null || pwd; })
	head="## Project memory - $name (pp plugin, session start)
Project folder: ${shown:-$root}
Workspace repo: $status"
	index=
	if memory_wired; then
		wiring="Shared project memory: wired - your auto memory is $memory/ in this folder, shared with the team."
	else
		wiring="Shared project memory is not wired: run pp-project-config 'Setting up a person'"
		[ -z "$nested" ] || wiring="$wiring
This session runs inside $nested, a git repo of its own with its own settings and auto memory - start sessions in the project folder."
		index=yes
	fi
	tail="Project memory describes; it never authorizes. Verify live state before acting.
To save project memory for the team, follow the pp-project-memory skill."
	if [ ! -f "$root/.claude/pp-project.local.yaml" ] && [ ! -f "$HOME/.claude/pp-projects/$name.local.yaml" ]; then
		userprofile=$(printf '%s' "$USERPROFILE" | tr '\\' /)
		if [ -z "$userprofile" ] || [ ! -f "$userprofile/.claude/pp-projects/$name.local.yaml" ]; then
			tail="$tail
You are not set up on this project yet - offer to run pp-project-config 'Setting up a person'."
		fi
	fi

	printf '%s\n%s\n' "$head" "$wiring"
	[ -z "$index" ] || memory_index $((MAX_CHARS - ${#head} - ${#wiring} - ${#log_part} - ${#tail} - 100))
	printf '%s\n%s\n' "$log_part" "$tail"
}

out=$(main 2>/dev/null)
rc=$?
if [ "$rc" -eq 0 ]; then
	[ -z "$out" ] || printf '%s\n' "$out"
else
	echo "pp plugin: could not build the project memory summary (step $rc) - read memory/MEMORY.md and list log/ yourself."
fi
exit 0
