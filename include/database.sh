#!/bin/sh
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# vm-bake database - the database itself: bootstrap, environment, dump and
# restore, batch execution and destroy. The pair that travels (export,
# bundle, seal, import) lives in archive.sh.

#@help __bootstrap1
# @command bootstrap <name> <profile>
# @completion name database
# @summary Create the database ~/.vm-bake/<name> (under VM_BAKE_ROOT) with the named profile and point the active-DB symlink db at it. <name> is a plain name, not a path: a slash is refused, db is reserved
# @group   setup
# @param   name     database name below VM_BAKE_ROOT (e.g. production); no slashes
# @param   profile  environment profile (minimal or all)
# @returns shell commands (create structure, copy defaults, stamp version)
# @example vm-bake bootstrap production all | sh
#@end
__bootstrap1() {
        echo "\"\$VM_BAKE_CONTEXT_SCRIPT\" bootstrap \"$1\" minimal"
}

#@help ___bootstrap2
# @internal arity-2 sibling of 'bootstrap' (bootstrap <name> <profile>): Create the database <root>/<name> with the named profile and point the active-DB symlink <root>/db at it: the name and the profile valid, the scaffold the batch runner of init needs, init against the new database, the link, the log line. Runs before any database exists: the environment is the shipped baseline, the batch runs under sh -e
#@end
___bootstrap2() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" bootstrap name valid '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment profile valid '$2'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" bootstrap scaffold '$1' '$VM_BAKE_ROOT'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" bootstrap init '$VM_BAKE_ROOT/$1' '$2'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" bootstrap link '$1' '$VM_BAKE_ROOT'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" log 'Bootstrap complete: $VM_BAKE_ROOT/$1 ($2) [db -> $1]'"
}

#@help __bootstrap_name_valid1
# @command bootstrap name valid <name>
# @summary The name is a plain database name below VM_BAKE_ROOT -- not empty, no slash, not the reserved 'db' (the active-DB symlink): a comment line, else an error line
# @group   setup
# @internal
# @see     bootstrap
#@end
__bootstrap_name_valid1() {
        if test -n "$1" && test "${1#*/}" = "$1" && test "$1" != db; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'database name $1 valid'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'bootstrap: <name> is a plain database name -- no slash, not db: $1 (e.g. production)'"
        fi
}

#@help _bootstrap_scaffold2
# @command bootstrap scaffold <name> <root>
# @summary Act terminal: the database directory (0700) with .tmp and .tmp/batch-exits (modes from the layout) -- what the batch runner of the following init needs before its first line
# @group   setup
# @internal
# @see     bootstrap
# @see     database init
#@end
_bootstrap_scaffold2() {
        printf '%s\n' "$MODIFY_DIR_CREATE '$2/$1/.tmp/batch-exits'"
        printf '%s\n' "$MODIFY_FILE_PERMS 0700 '$2/$1'"
        printf '%s\n' "$MODIFY_FILE_PERMS $(printf '%s\n' "$VM_BAKE_INIT_DIR_CONFIG" | awk -F: '$1 == ".tmp" { print $2 }') '$2/$1/.tmp'"
        printf '%s\n' "$MODIFY_FILE_PERMS $(printf '%s\n' "$VM_BAKE_INIT_DIR_CONFIG" | awk -F: '$1 == ".tmp/batch-exits" { print $2 }') '$2/$1/.tmp/batch-exits'"
}

#@help __bootstrap_init2
# @command bootstrap init <base> <profile>
# @summary The one line that initializes the NEW database: 'init <profile>' with VM_BAKE_BASE bound to <base> in front of it (the root is named by the parent: a child derives no root before a database exists) -- its pin maps the context-script word and execs the line (cat = dry-run)
# @group   setup
# @internal
# @env     VM_BAKE_INTERPRETER_bootstrap_init  execs the line with VM_BAKE_BASE bound; cat = dry-run
# @see     bootstrap
# @see     init
#@end
__bootstrap_init2() {
        printf '%s\n' "env VM_BAKE_BASE='$1' \"\$VM_BAKE_CONTEXT_SCRIPT\" init '$2'"
}

#@help _bootstrap_link2
# @command bootstrap link <name> <root>
# @summary Act terminal: point the active-DB symlink <root>/db at the database <name> (forced: a bootstrap re-run or a second database moves it); a plain directory there holding only scratch (.tmp, .log: the base was named before any database existed -- 'import bootstrap') has that scratch MOVED into the new database first (rename: the open files of the processes waiting on it stay valid, their paths resolve through the link), anything else there is an error
# @group   setup
# @internal
# @see     bootstrap
#@end
_bootstrap_link2() {
        local db="$2/db" new="$2/$1" f=""
        if test -d "$db" && ! test -L "$db"; then
                (cd "$db" && find .tmp .log \( -type f -o -type l \) 2>/dev/null) | while IFS= read -r f; do
                        printf '%s\n' "$MODIFY_DIR_CREATE '$new/$(dirname "$f")' && mv -f '$db/$f' '$new/$f' || exit 1"
                done
                printf '%s\n' "rm -rf '$db/.tmp' '$db/.log' && rmdir '$db' || { printf '# Error: bootstrap link: %s is a directory, not the active-DB link (a database of that name? move it away)\\n' '$db' >&2; exit 1; }"
        fi
        printf '%s\n' "$MODIFY_LINK_FORCE '$1' '$db'"
}

#@help __environment_profile_valid1
# @command environment profile valid <profile>
# @summary The profile is shipped as template/environment/VM_BAKE_PROFILE_<PROFILE>: a comment line, else an error line
# @group   setup
# @internal
# @see     bootstrap
# @see     environment init
# @env     VM_BAKE_TEMPLATE_DIR  the shipped profiles: environment/VM_BAKE_PROFILE_<PROFILE>
#@end
__environment_profile_valid1() {
        if test -f "$VM_BAKE_TEMPLATE_DIR/environment/VM_BAKE_PROFILE_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'profile $1 shipped'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'unknown profile $1 (minimal | all)'"
        fi
}
#@help ___database_init0
# @command database init
# @summary Ensure every directory of the database layout (VM_BAKE_INIT_DIR_CONFIG: path, mode, exec flag, content policy), one 'database dir ensure' per line, then the ready line
# @group   configuration
# @internal
# @see     init
# @see     database dir ensure
#@end
___database_init0() {
        local dir="" mode="" exec="" policy=""
        printf '%s\n' "$VM_BAKE_INIT_DIR_CONFIG" | while IFS=: read -r dir mode exec policy; do
                test -n "$dir" || continue
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" database dir ensure '$dir' '$mode' '$exec' '$policy'"
        done
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" log 'Database ready: $VM_BAKE_BASE'"
}

#@help __database_dir_ensure4
# @command database dir ensure <dir> <mode> <exec-flag> <policy>
# @summary The directory is there: rewrite to 'database dir validate ...', else to 'database dir create <dir> <mode>'
# @group   configuration
# @internal
# @see     database init
#@end
__database_dir_ensure4() {
        if test -e "$VM_BAKE_BASE/$1"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" database dir validate '$1' '$2' '$3' '$4'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" database dir create '$1' '$2'"
        fi
}

#@help __database_dir_validate4
# @command database dir validate <dir> <mode> <exec-flag> <policy>
# @summary The path is a directory, its content admissible (policy operational: any; else empty -- the exclusive hierarchy) and, with the exec flag, its mount runs scripts: rewrite to 'database dir validated <dir> <mode>', else an error line
# @group   configuration
# @internal
# @see     database dir ensure
#@end
__database_dir_validate4() {
        local ok=yes probe="$VM_BAKE_BASE/$1/.init_exec_test_$$"
        test -d "$VM_BAKE_BASE/$1" || ok=no
        test "$4" = operational || test -z "$(ls -A "$VM_BAKE_BASE/$1" 2>/dev/null)" || ok=no
        if test "$ok" = yes && test "$3" = exec; then
                printf '#!/bin/sh\nexit 0\n' > "$probe" && chmod 0700 "$probe" && "$probe" >/dev/null 2>&1 || ok=no
                rm -f "$probe"
        fi
        if test "$ok" = yes; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" database dir validated '$1' '$2'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'database init: $1 exists but is not a directory, not empty (policy $4) or mounted noexec (flag $3) -- remove or fix it and run init again'"
        fi
}

#@help _database_dir_validated2
# @command database dir validated <dir> <mode>
# @summary Act terminal: the validated line for the directory, with a warning when its mode differs from the layout's
# @group   configuration
# @internal
# @see     database dir ensure
#@end
_database_dir_validated2() {
        local actual=""
        actual=$($CMD_STAT_PERMS "$VM_BAKE_BASE/$1" 2>/dev/null | sed 's/^0*//')
        if test "$actual" != "$(printf '%s' "$2" | sed 's/^0*//')"; then
                emit_note "Warning: directory $1 has mode $actual, expected $2"
        fi
        emit_note "Validated: $1"
}

#@help _database_dir_create2
# @command database dir create <dir> <mode>
# @summary Act terminal: create the directory with its mode and say so
# @group   configuration
# @internal
# @see     database dir ensure
#@end
_database_dir_create2() {
        printf '%s\n' "$MODIFY_DIR_CREATE '$VM_BAKE_BASE/$1'"
        printf '%s\n' "$MODIFY_FILE_PERMS $2 '$VM_BAKE_BASE/$1'"
        emit_note "Created: $1 (mode $2)"
}

#@help __environment_init0
# @command environment init [<profile>]
# @summary Install a profile's template variables into .env/default -- a line of init, and the step after an update of vm-bake: a variable new in template/environment reaches a database only this way (the cache is dropped with it). Without an argument the profile is the database's own, read from .env/default/VM_BAKE_PROFILE_<PROFILE> (profile show): rewrite to 'environment init <profile>'; no profile installed, or more than one, is an error
# @group   configuration
# @param   profile  minimal or all; the database's own when left out
# @example vm-bake environment init
# @example vm-bake environment init all
# @see     profile show
# @see     bootstrap
# @see     environment profile valid
# @see     environment install
#@end
__environment_init0() {
        local p="" n=0 f=""
        for f in "$VM_BAKE_BASE"/.env/default/VM_BAKE_PROFILE_*; do
                test -f "$f" || continue
                n=$((n + 1)); p=$(printf '%s' "${f##*/VM_BAKE_PROFILE_}" | tr '[:upper:]' '[:lower:]')
        done
        case "$n" in
        1) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment init $(sq "$p")" ;;
        0) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'environment init: no profile installed in .env/default (bootstrap <name> <profile>, or environment init <profile>)'" ;;
        *) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "environment init: $n profiles installed in .env/default (profile show) -- name one: environment init <profile>")" ;;
        esac
}

#@help ___environment_init1
# @internal arity-1 sibling of 'environment init' (environment init <profile>  -- the profile named): the profile is shipped (environment profile valid), then 'environment install'
#@end
___environment_init1() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment profile valid '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment install '$1'"
}

#@help _profile_show0
# @command profile show
# @summary The database's profile: the name from .env/default/VM_BAKE_PROFILE_<PROFILE>, how many variables that list names, how many of them .env/default holds, and how many the shipped list of the same profile names now -- a shipped count above the installed one says 'environment init' is due
# @group   configuration
# @example vm-bake profile show
# @see     environment init
# @see     environment cache status
# @env     VM_BAKE_TEMPLATE_DIR  the shipped profiles: environment/VM_BAKE_PROFILE_<PROFILE>
#@end
_profile_show0() {
        local f="" name="" listed=0 held=0 shipped=0 v="" n=0
        for f in "$VM_BAKE_BASE"/.env/default/VM_BAKE_PROFILE_*; do
                test -f "$f" || continue
                n=$((n + 1)); name=$(printf '%s' "${f##*/VM_BAKE_PROFILE_}" | tr '[:upper:]' '[:lower:]')
                for v in $(head -1 "$f"); do listed=$((listed + 1)); test -f "$VM_BAKE_BASE/.env/default/$v" && held=$((held + 1)); done
                shipped=$(head -1 "$VM_BAKE_TEMPLATE_DIR/environment/${f##*/}" 2>/dev/null | wc -w | tr -d ' ')
                printf '# profile %s: %s variables listed, %s held in .env/default, %s shipped by this vm-bake\n' "$name" "$listed" "$held" "$shipped"
                test "$shipped" -le "$held" || printf '# profile %s: %s shipped variables are not installed -- environment init\n' "$name" "$((shipped - held))"
        done
        test "$n" -gt 0 || printf '# profile: none installed in .env/default (bootstrap <name> <profile>)\n'
}

#@help _environment_install1
# @command environment install <profile>
# @summary Act terminal: the script that copies every template the profile lists into .env/default (0600), removes the default pins the profile no longer lists (a renamed terminal's old pin would bind the wrong function), records the profile marker, invalidates the environment cache when one is there and says so; a local pin that names no function is reported
# @group   configuration
# @internal
# @see     environment init
# @env     VM_BAKE_TEMPLATE_DIR  where the profile and its templates live
# @env     VM_BAKE_PROFILE_ALL  the profile lists (VM_BAKE_PROFILE_<PROFILE>): line 1 names the variables to install
# @env     VM_BAKE_CACHE_ENV_ARGS  the environment cache, invalidated by the install
# @env     VM_BAKE_INTERPRETER_<function>  the pins the profile installs; a default pin the profile no longer lists is removed
#@end
_environment_install1() {
        local var="" f="" prof="" stem=""
        for var in $(head -1 "$VM_BAKE_TEMPLATE_DIR/environment/VM_BAKE_PROFILE_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" 2>/dev/null); do
                printf '%s\n' "$MODIFY_FILE_COPY_FORCE '$VM_BAKE_TEMPLATE_DIR/environment/$var' '$VM_BAKE_BASE/.env/default/$var'"
                printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$VM_BAKE_BASE/.env/default/$var'"
        done
        printf '%s\n' "$MODIFY_FILE_COPY_FORCE '$VM_BAKE_TEMPLATE_DIR/environment/VM_BAKE_PROFILE_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')' '$VM_BAKE_BASE/.env/default/VM_BAKE_PROFILE_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')'"
        printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$VM_BAKE_BASE/.env/default/VM_BAKE_PROFILE_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')'"
        prof="$VM_BAKE_TEMPLATE_DIR/environment/VM_BAKE_PROFILE_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
        for f in "$VM_BAKE_BASE"/.env/default/VM_BAKE_INTERPRETER_*; do
                test -f "$f" || continue
                head -1 "$prof" 2>/dev/null | tr ' ' '\n' | grep -qx "${f##*/}" && continue
                printf '%s\n' "$MODIFY_FILE_REMOVE '$f'"
                emit_note "removed the stale default pin ${f##*/} (the profile no longer lists it)"
        done
        for f in "$VM_BAKE_BASE"/.env/local/VM_BAKE_INTERPRETER_*; do
                test -f "$f" || continue
                head -1 "$prof" 2>/dev/null | tr ' ' '\n' | grep -qx "${f##*/}" && continue
                stem=${f##*/}; stem=${stem#VM_BAKE_INTERPRETER_}
                printf '%s\n' $ANCHOR_FUNCTIONS | grep -qE "^_${stem}[0-9]*$" && continue
                emit_note "local pin ${f##*/} names no terminal of this version (a rename? it may bind a batch or combinator now) -- check: unsetenv ${f##*/}"
        done
        printf '%s\n' "$MODIFY_FILE_REMOVE '$VM_BAKE_BASE/.env/local/VM_BAKE_CACHE_ENV_ARGS' 2>/dev/null || true"
        emit_note "Installed $1 profile (environment cache invalidated)"
}

#@help __environment_cache0
# @command environment cache [on|off|status]
# @summary Manage the cached-environment optimisation
# @group   configuration
# @param   on|off|status  enable, disable, or report the cache (default: status)
# @returns shell commands / cache status
# @example vm-bake environment cache status

# @env VM_BAKE_CACHE_ENV_ARGS  the cache this command manages
#@end
__environment_cache0() {
        # Combinator - delegate to status display
        echo '"$VM_BAKE_CONTEXT_SCRIPT" environment cache status'
}

#@help ___environment_cache_on0
# @command environment cache on
# @summary Build the environment cache, the pattern of stage site mk: 'environment cache render' redirected into .env/local/VM_BAKE_CACHE_ENV_ARGS.new (a fresh scan of .env/), then 'environment cache place' moves it into place (0600) and says how many variables. The scan happens when the lines run, not when this command generates: a compiled script carries them, and they see the setenv acts before them. A database whose cache predates this version knows no pin for 'place' and only displays it: re-sync first (environment init <profile>), it drops the cache
# @group   configuration
# @env     VM_BAKE_CACHE_ENV_ARGS  the cache file the lines write
# @see     environment cache render
# @see     environment cache place
# @see     environment cache status
#@end
___environment_cache_on0() {
        local f="$VM_BAKE_BASE/.env/local/VM_BAKE_CACHE_ENV_ARGS"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment cache render > '$f.new'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment cache place"
}

#@help _environment_cache_render0
# @command environment cache render
# @summary Text terminal: the layered store .env/ as one line of NAME='value' pairs, local over default, scanned afresh (the in-memory cache a parent handed down is set aside for the scan) -- the content of the cache, what 'environment cache on' redirects into the .new file
# @group   configuration
# @internal
# @env     VM_BAKE_CACHE_ENV_ARGS  the value a parent may have handed down -- ignored here, the scan reads .env/
# @see     environment cache on
#@end
_environment_cache_render0() {
        ( unset VM_BAKE_CACHE_ENV_ARGS; build_env_args_full )
}

#@help _environment_cache_place0
# @command environment cache place
# @summary Act terminal: the script that moves .env/local/VM_BAKE_CACHE_ENV_ARGS.new into place (0600) and says how many variables the cache holds. Before 14.09. the cache was written while 'environment cache on' generated; a compiled script had nothing to run, and a display pin was not innocent
# @group   configuration
# @internal
# @env     VM_BAKE_CACHE_ENV_ARGS  the cache file this script places
# @see     environment cache on
#@end
_environment_cache_place0() {
        local f="$VM_BAKE_BASE/.env/local/VM_BAKE_CACHE_ENV_ARGS"
        printf '%s\n' "test -s '$f.new' || { printf '# Error: environment cache not rendered (%s)\\n' '$f.new' >&2; exit 1; }"
        printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$f.new' && mv -f '$f.new' '$f'"
        printf '%s\n' "echo '# Environment cache ENABLED' >&2"
        printf '%s\n' "echo \"# Cached \$(wc -w < '$f' | tr -d ' ') variables\" >&2"
}

#@help ___environment_refresh0
# @command environment refresh
# @summary The environment as a new call finds it: at generation time VM_BAKE_CACHE_ENV_ARGS and VM_BAKE_CONTEXT_BOOTSTRAPPED are unset; the lines are 'environment cache off' and 'environment cache on' -- the cache rebuilt from .env/ when they run, the calls after them look their pins up afresh. A dump places it after the setenv lines of its prologue and of its epilogue
# @group   configuration
# @env     VM_BAKE_CACHE_ENV_ARGS        unset here; the cache the lines rebuild
# @env     VM_BAKE_CONTEXT_BOOTSTRAPPED  unset here
# @see     environment cache
# @see     dump
#@end
___environment_refresh0() {
        unset VM_BAKE_CACHE_ENV_ARGS
        unset VM_BAKE_CONTEXT_BOOTSTRAPPED
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment cache off"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment cache on"
}

#@help _environment_cache_off0
# @command environment cache off
# @summary Remove the environment cache; later invocations read the layered store again
# @group   configuration
# @env     VM_BAKE_CACHE_ENV_ARGS  the cache file this command removes
# @see     environment cache on
#@end
_environment_cache_off0() {
        local cache_file="$VM_BAKE_BASE/.env/local/VM_BAKE_CACHE_ENV_ARGS"
        if [ -f "$cache_file" ]; then
                echo "$MODIFY_FILE_REMOVE '$cache_file'"
                echo "echo '# Environment cache DISABLED' >&2"
        else
                echo "echo '# Environment cache already disabled' >&2"
        fi
}

#@help _environment_cache_status0
# @command environment cache status
# @summary Is the environment cache on, how many variables does it hold, and is the environment frozen (environment freeze)?
# @group   configuration
# @env     VM_BAKE_CACHE_ENV_ARGS  the cache file this command examines
# @see     environment cache on
#@end
_environment_cache_status0() {
        local cache_file="$VM_BAKE_BASE/.env/local/VM_BAKE_CACHE_ENV_ARGS" var_count
        if [ -f "$cache_file" ]; then
                var_count=$(wc -w < "$cache_file" | tr -d ' ')
                echo "echo '# Environment cache: ENABLED ($var_count vars)' >&2"
        else
                echo "echo '# Environment cache: DISABLED' >&2"
        fi
        if [ -f "$VM_BAKE_BASE/.env/frozen" ]; then
                echo "echo '# Environment: FROZEN ($(sed -n 1p "$VM_BAKE_BASE/.env/frozen")) -- combinator and batch pins are the shipped defaults' >&2"
        fi
}

#@help ___environment_freeze1
# @command environment freeze <name>
# @completion name database
# @summary Freeze the interpreter environment of this database, with no way back: the name IS the confirmation (as destroy), a warning says what goes, then every machine override that weakens a combinator or batch pin is removed (environment freeze pins), the terminal default becomes sh (acts run), the marker .env/frozen is written, the cache rebuilt. Frozen, setenv and unsetenv refuse those pins. The shipped defaults are the only interpreters that read ONE line reliably (head -n1 | xargs ... for a combinator, the batch runner for a batch): a pin of sh or cat there works until two lines stand on stdin. A pin that must deviate is a decision taken BEFORE the freeze, in the template that ships it, never a machine override afterwards. Assumes: the database is provisioned and about to be trusted with acts; there is no thaw
# @group   configuration
# @param   name  must match the database's own name -- the confirmation
# @env     VM_BAKE_TERMINAL_INTERPRETER  set to sh by the batch: acts run in a frozen database
# @example vm-bake environment freeze production
# @see     environment freeze pins
# @see     environment cache status
# @see     setenv
# @see     destroy
#@end
___environment_freeze1() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment freeze named '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment freeze warn '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment freeze pins"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setenv VM_BAKE_TERMINAL_INTERPRETER sh"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment freeze mark"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment cache on"
}

#@help __environment_freeze_named1
# @command environment freeze named <name>
# @summary The name is this database's own (the basename the active-DB symlink resolves to): a comment line, else an error line -- naming the database IS the confirmation
# @group   configuration
# @internal
# @see     environment freeze
#@end
__environment_freeze_named1() {
        local real=""
        real=$(basename "$(readlink -f "$VM_BAKE_BASE")")
        if test "$1" = "$real"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'environment freeze $1 confirmed by name'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "environment freeze: name '$1' does not match this database ('$real') -- naming it IS the confirmation")"
        fi
}

#@help _environment_freeze_warn1
# @command environment freeze warn <name>
# @summary Print what the freeze removes for good and what it fixes -- the warning the batch shows before the first unsetenv
# @group   configuration
# @internal
# @env     VM_BAKE_COMBINATOR_INTERPRETER  named in the warning: a class default the freeze pins to the shipped value
# @env     VM_BAKE_BATCH_COMBINATOR_INTERPRETER  named in the warning: the other class default
# @env     VM_BAKE_INTERPRETER_  named in the warning: the per-anchor pins of __ and ___ anchors
# @see     environment freeze
#@end
_environment_freeze_warn1() {
        printf '%s\n' "# FREEZE '$1' -- no way back:"
        printf '%s\n' "#   every machine override of a combinator or batch pin that is not the shipped"
        printf '%s\n' "#   default is removed (.env/local/VM_BAKE_INTERPRETER_* of __/___ anchors, the"
        printf '%s\n' "#   class defaults VM_BAKE_COMBINATOR_INTERPRETER, VM_BAKE_BATCH_COMBINATOR_INTERPRETER),"
        printf '%s\n' "#   the terminal default becomes sh (acts run), the marker .env/frozen is written."
        printf '%s\n' "# From then on setenv and unsetenv refuse those pins; a deviation is a template decision."
}

#@help ___environment_freeze_pins0
# @command environment freeze pins
# @summary Every machine override that weakens a combinator or batch pin, per file of .env/local: an VM_BAKE_INTERPRETER_<anchor> whose anchor is a __ or ___ function (the stem table), or one of the two class defaults, holding anything but the shipped default of its class (template/environment): one 'unsetenv <VAR>' each; none: a comment line
# @group   configuration
# @internal
# @env     VM_BAKE_TEMPLATE_DIR  the template directory (the shipped defaults)
# @env     VM_BAKE_COMBINATOR_INTERPRETER  the shipped default a combinator pin must equal
# @env     VM_BAKE_BATCH_COMBINATOR_INTERPRETER  the shipped default a batch pin must equal
# @see     environment freeze
#@end
___environment_freeze_pins0() {
        local f="" v="" x="" fns="" want="" lines=0
        for f in "$VM_BAKE_BASE"/.env/local/VM_BAKE_INTERPRETER_* "$VM_BAKE_BASE"/.env/local/VM_BAKE_COMBINATOR_INTERPRETER "$VM_BAKE_BASE"/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER; do
                [ -f "$f" ] || continue
                v=${f##*/}; x=${v#VM_BAKE_INTERPRETER_}; want=""
                case "$v" in
                VM_BAKE_COMBINATOR_INTERPRETER|VM_BAKE_BATCH_COMBINATOR_INTERPRETER) want=$(sed -n 1p "$VM_BAKE_TEMPLATE_DIR/environment/$v") ;;
                *[!A-Za-z0-9_]*) ;;
                *)      eval "fns=\"\${ANCHOR_STEM_${x%[0-9]}:-} \${ANCHOR_STEM_${x}:-}\""
                        case " $fns " in
                        *" ___"*) want=$(sed -n 1p "$VM_BAKE_TEMPLATE_DIR/environment/VM_BAKE_BATCH_COMBINATOR_INTERPRETER") ;;
                        *" __"*)  want=$(sed -n 1p "$VM_BAKE_TEMPLATE_DIR/environment/VM_BAKE_COMBINATOR_INTERPRETER") ;;
                        esac ;;
                esac
                [ -n "$want" ] || continue
                [ "$(sed -n 1p "$f")" != "$want" ] || continue
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" unsetenv '$v'"
                lines=$((lines + 1))
        done
        test "$lines" -gt 0 || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'no machine override weakens a combinator or batch pin'"
}

#@help _environment_freeze_mark0
# @command environment freeze mark
# @summary Act terminal: write the marker .env/frozen (the date, 0400) -- what environment frozen allows reads
# @group   configuration
# @internal
# @see     environment freeze
#@end
_environment_freeze_mark0() {
        printf '%s\n' "printf '%s\\n' \"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\" > '$VM_BAKE_BASE/.env/frozen'"
        printf '%s\n' "$MODIFY_FILE_PERMS 0400 '$VM_BAKE_BASE/.env/frozen'"
        printf '%s\n' "printf '%s\\n' '# Environment frozen (.env/frozen)' >&2"
}

#@help __environment_frozen_allows1
# @command environment frozen allows <VAR>
# @summary A frozen database (.env/frozen) refuses to set or unset a combinator or batch pin -- VM_BAKE_INTERPRETER_<anchor> of a __ or ___ function (the stem table), or a class default: an error line naming the rule; any other variable, or no freeze, is a comment line
# @group   configuration
# @internal
# @env     VM_BAKE_COMBINATOR_INTERPRETER  a class default: refused when frozen
# @env     VM_BAKE_BATCH_COMBINATOR_INTERPRETER  the other class default: refused when frozen
# @see     environment freeze
# @see     setenv
#@end
__environment_frozen_allows1() {
        local x="" fns=""
        if [ ! -f "$VM_BAKE_BASE/.env/frozen" ]; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'environment not frozen: $1 may change'"
                return 0
        fi
        x=${1#VM_BAKE_INTERPRETER_}
        case "$1" in
        VM_BAKE_COMBINATOR_INTERPRETER|VM_BAKE_BATCH_COMBINATOR_INTERPRETER) fns="__" ;;
        *[!A-Za-z0-9_]*) fns="" ;;
        *) eval "fns=\"\${ANCHOR_STEM_${x%[0-9]}:-} \${ANCHOR_STEM_${x}:-}\"" ;;
        esac
        case " $fns " in
        *" __"*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'environment frozen: $1 is a combinator or batch pin -- the shipped default stays (a deviation is a template decision, taken before the freeze)'" ;;
        *)       printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'environment frozen: $1 is no combinator or batch pin, it may change'" ;;
        esac
}

#@help ___init1
# @command init <profile>
# @summary The line bootstrap runs against the new database (and again on a re-run, which refreshes the defaults): initialize the database at VM_BAKE_BASE: the layout (database init), then the profile's environment (environment init), then the environment cache (environment cache on) -- every later invocation reads one file instead of the layered store
# @group   configuration
# @internal
# @param   profile  minimal or all
# @see     bootstrap
#@end
___init1() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" database init"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment init '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment cache on"
}

#@help __init0
# @internal low-level database init — complex to call directly; use 'bootstrap'

# @env VM_BAKE_CACHE_ENV_ARGS                 rebuilt as part of init
# @env VM_BAKE_TERMINAL_INTERPRETER          class default seeded by init
# @env VM_BAKE_COMBINATOR_INTERPRETER        class default seeded by init
# @env VM_BAKE_BATCH_COMBINATOR_INTERPRETER  class default seeded by init

#@end
__init0() {
        # Bootstrap: passthrough interpreter variables for init command
        # Since init creates the .env files, we need to provide defaults via CACHE_ENV_ARGS
        echo "VM_BAKE_CACHE_ENV_ARGS=\"VM_BAKE_COMBINATOR_INTERPRETER=sh VM_BAKE_TERMINAL_INTERPRETER=sh VM_BAKE_BATCH_COMBINATOR_INTERPRETER='while IFS= read -r line; do echo \\\"\\\$line\\\" | \\\$VM_BAKE_COMBINATOR_INTERPRETER; done'\" \"\$VM_BAKE_CONTEXT_SCRIPT\" init minimal"
}

#@help ___setenv2
# @command setenv <VAR> <value>
# @summary Set a machine override: the name is a variable name, a frozen database allows it (environment frozen allows: no combinator or batch pin after environment freeze), the value is written to .env/local/<VAR> (0640, owner of the database when possible), the environment cache refreshed when one is on. Effective with the next command
# @group   configuration
# @param   VAR    letters, digits and underscores
# @param   value  the first line of the variable's file
# @example vm-bake setenv VM_BAKE_FREEBSD_SRC /home/brj/git/freebsd-src
# @see     getenv
# @see     unsetenv
# @see     environment cache
#@end
___setenv2() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setenv name valid '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment frozen allows '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setenv write '$1' $(sq "$2")"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment cache refresh"
}

#@help __setenv_name_valid1
# @command setenv name valid <VAR>
# @summary The name consists of letters, digits and underscores only: a comment line, else an error line
# @group   configuration
# @internal
# @see     setenv
#@end
__setenv_name_valid1() {
        if printf '%s\n' "$1" | grep -qx '[A-Za-z0-9_][A-Za-z0-9_]*'; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'variable name $1 valid'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'setenv: invalid variable name $1 (letters, digits and underscores only)'"
        fi
}

#@help _setenv_write2
# @command setenv write <VAR> <value>
# @summary Act terminal: the script that writes the value as .env/local/<VAR> (directory 0700, file 0640) and hands the file to the database's owner when that is someone else (best effort)
# @group   configuration
# @internal
# @see     setenv
#@end
_setenv_write2() {
        local owner=""
        owner=$($EXAMINE_FILE_OWNER "$VM_BAKE_BASE/.env/default" 2>/dev/null)
        printf '%s\n' "$MODIFY_DIR_CREATE '$VM_BAKE_BASE/.env/local'"
        printf '%s\n' "$MODIFY_FILE_PERMS 0700 '$VM_BAKE_BASE/.env/local'"
        printf '%s\n' "printf '%s\\n' $(sq "$2") > '$VM_BAKE_BASE/.env/local/$1'"
        printf '%s\n' "$MODIFY_FILE_PERMS 0640 '$VM_BAKE_BASE/.env/local/$1'"
        printf '%s\n' "$MODIFY_FILE_OWNER '$owner' '$VM_BAKE_BASE/.env/local/$1' 2>/dev/null || true"
        emit_note "Set $1 (effective next command)"
}

#@help __environment_cache_refresh0
# @command environment cache refresh
# @summary The environment cache is on (.env/local/VM_BAKE_CACHE_ENV_ARGS is there): rewrite to 'environment cache on' (a fresh scan), else a comment line
# @group   configuration
# @internal
# @see     setenv
# @see     unsetenv
# @see     environment cache on
#@end
__environment_cache_refresh0() {
        if test -f "$VM_BAKE_BASE/.env/local/VM_BAKE_CACHE_ENV_ARGS"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment cache on"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'environment cache off, nothing to refresh'"
        fi
}

#@help __getenv1
# @command getenv <VAR>
# @summary Show the effective value of a variable and the layer that answers (.env/local override, .env/default, the shipped template): the variable resolves: rewrite to 'getenv read <VAR> <layer> <path>', else an error line
# @group   configuration
# @example vm-bake getenv VM_BAKE_FREEBSD_SRC
# @see     setenv
# @see     printenv
#@end
__getenv1() {
        local resolved=""
        if resolved=$(env_resolve_file "$1" 2>/dev/null); then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" getenv read '$1' '$(printf '%s\n' "$resolved" | sed -n 1p)' '$(printf '%s\n' "$resolved" | sed -n 2p)'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'getenv: variable $1 not found in any layer'"
        fi
}

#@help _getenv_read3
# @command getenv read <VAR> <layer> <path>
# @summary Act terminal: the source line (layer and path; the local layer is the override) on stderr and the value (the file's first line) on stdout
# @group   configuration
# @internal
# @see     getenv
#@end
_getenv_read3() {
        emit_note "Source: $3 ($(printf '%s' "$2" | sed 's/^local$/override/'))"
        printf '%s\n' "head -n 1 '$3'"
}

#@help ___unsetenv1
# @command unsetenv <VAR>
# @summary Remove the machine override .env/local/<VAR> when there is one (else say so) -- a frozen database allows it first (environment frozen allows) -- and refresh the environment cache when one is on
# @group   configuration
# @example vm-bake unsetenv VM_BAKE_FREEBSD_SRC
# @see     setenv
# @see     getenv
#@end
___unsetenv1() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment frozen allows '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" unsetenv remove '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment cache refresh"
}

#@help __unsetenv_remove1
# @command unsetenv remove <VAR>
# @summary The override file is there: rewrite to 'unsetenv erase <VAR>', else a note line (nothing to unset)
# @group   configuration
# @internal
# @see     unsetenv
#@end
__unsetenv_remove1() {
        if test -f "$VM_BAKE_BASE/.env/local/$1"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" unsetenv erase '$1'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note 'Variable $1 not set (nothing to unset)'"
        fi
}

#@help _unsetenv_erase1
# @command unsetenv erase <VAR>
# @summary Act terminal: remove .env/local/<VAR> and say so
# @group   configuration
# @internal
# @see     unsetenv
#@end
_unsetenv_erase1() {
        printf '%s\n' "$MODIFY_FILE_REMOVE '$VM_BAKE_BASE/.env/local/$1'"
        emit_note "Unset $1"
}

#@help ___dump_env_prologue0
# @command dump env prologue
# @summary Emit the prologue of a dump: the SOURCE's .env/local overrides that the restore itself depends on (the PROLOGUE profile's list -- deliberately WITHOUT function-specific interpreter pins, which could deactivate replayed commands), then 'environment refresh' so the pins hold for the lines after it
# @group   database
# @env     VM_BAKE_TEMPLATE_DIR  the shipped templates, where the PROLOGUE profile lives
# @env     VM_BAKE_PROFILE_PROLOGUE  the profile listing the variables that travel in the prologue
# @env     VM_BAKE_CACHE_ENV_ARGS  never copied: 'environment refresh' rebuilds it after the pins
# @see     dump env epilogue
# @see     environment refresh
# @see     dump
#@end
___dump_env_prologue0() {
        local varname="" value=""
        for varname in $(head -n 1 "$VM_BAKE_TEMPLATE_DIR/environment/VM_BAKE_PROFILE_PROLOGUE" 2>/dev/null); do
                test "$varname" != VM_BAKE_CACHE_ENV_ARGS || continue
                value=$(head -n 1 "$VM_BAKE_BASE/.env/local/$varname" 2>/dev/null)
                test -n "$value" && printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setenv $varname $(sq "$value")"
        done
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment refresh"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'environment prologue replayed'"
}
#@help ___dump_env_epilogue0
# @command dump env epilogue
# @summary Emit the epilogue of a dump: EVERY .env/local override of the source, including function-specific interpreter pins -- restored at the very end, when the replay is done
# @group   database
# @env     VM_BAKE_CACHE_ENV_ARGS  regenerated by 'environment refresh', never copied
# @see     dump env prologue
# @see     environment refresh
# @see     dump
#@end
___dump_env_epilogue0() {
        local local_file="" varname="" value=""
        for local_file in "$VM_BAKE_BASE/.env/local/"*; do
                varname=${local_file##*/}
                test -f "$local_file" && test "$varname" != VM_BAKE_CACHE_ENV_ARGS || continue
                value=$(head -n 1 "$local_file" 2>/dev/null)
                test -n "$value" && printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setenv $varname $(sq "$value")"
        done
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" environment refresh"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'environment epilogue replayed'"
}
#@help ___destroy1
# @command destroy <name>
# @completion name database
# @summary Remove this database and everything it owns, IRRECOVERABLY, as three steps: the worktrees and their registration in the source repo, the records, the scaffolding (bundle handover area, active-DB symlink, empty root). The name IS the confirmation, checked before a line runs
# @group   database
# @param   name  must match the database's own name -- the confirmation
# @example vm-bake destroy current
# @see     dump
#@end
___destroy1() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" destroy named '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" destroy warning '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" destroy records '$1'"
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" destroy scaffold '$1'"
}

#@help __destroy_named1
# @command destroy named <name>
# @summary The name is this database's own (the basename the active-DB symlink resolves to): a comment line, else an error line -- naming the database IS the confirmation
# @group   database
# @internal
# @see     destroy
#@end
__destroy_named1() {
        local real=""
        real=$(basename "$(readlink -f "$VM_BAKE_BASE")")
        if test "$1" = "$real"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'destroy $1 confirmed by name'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "destroy: name '$1' does not match this database ('$real') -- naming it IS the confirmation")"
        fi
}

#@help _destroy_warning1
# @command destroy warning <name>
# @summary Print what destroy removes for good and what it leaves alone -- the warning the batch shows before the first rm
# @group   database
# @internal
# @see     destroy
#@end
_destroy_warning1() {
        printf '%s\n' "# DESTROY '$1' -- everything below is gone for good, with no undo:"
        printf '%s\n' "#   the records, every stage with its boot tree, markers and backups,"
        printf '%s\n' "#   the worktrees under $VM_BAKE_ROOT/worktree and their registration in the source repo,"
        printf '%s\n' "#   the bundle handover area $VM_BAKE_ROOT/bundle (a handover point, never a store --"
        printf '%s\n' "#   copy anything you still need OUT of it first),"
        printf '%s\n' "#   and the active-DB symlink if it points here."
        printf '%s\n' "# Not touched, because they are not this database's: deployed loaders on media,"
        printf '%s\n' "# NVRAM boot entries, and key material in the world (pem/pkcs11/openpgp paths)."
}

#@help __destroy_records1
# @command destroy records <name>
# @completion name database
# @summary Step 2 of destroy: the name is this database's: rewrite to 'destroy records remove' (the database directory itself, resolved through the active-DB symlink first -- rm -rf on a symlink removes the LINK and orphans the database), else an error line
# @group   database
# @param   name  the database's own name -- the confirmation
# @see     destroy
# @see     destroy records remove
#@end
__destroy_records1() {
        local real=""
        real=$(basename "$(readlink -f "$VM_BAKE_BASE")")
        if test "$1" = "$real"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" destroy records remove"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "destroy records: name '$1' does not match this database ('$real')")"
        fi
}

#@help _destroy_records_remove0
# @command destroy records remove
# @summary Act terminal: rm -rf of the resolved database directory and a note of what was destroyed
# @group   database
# @internal
# @see     destroy records
#@end
_destroy_records_remove0() {
        printf '%s\n' "rm -rf '$(readlink -f "$VM_BAKE_BASE")'"
        printf '%s\n' "printf '# destroyed: %s\\n' '$(basename "$(readlink -f "$VM_BAKE_BASE")")' >&2"
}

#@help __destroy_scaffold1
# @command destroy scaffold <name>
# @completion name database
# @summary Step 3 of destroy: the name is this database's: rewrite to 'destroy scaffold remove' (the bundle handover area, the active-DB symlink if it points here, the empty scaffolding), else an error line
# @group   database
# @param   name  the database's own name -- the confirmation
# @see     destroy
# @see     destroy scaffold remove
#@end
__destroy_scaffold1() {
        local real=""
        real=$(basename "$(readlink -f "$VM_BAKE_BASE")")
        if test "$1" = "$real"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" destroy scaffold remove"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "destroy scaffold: name '$1' does not match this database ('$real')")"
        fi
}

#@help _destroy_scaffold_remove0
# @command destroy scaffold remove
# @summary Act terminal: rm -rf of the bundle handover area, rm of the active-DB symlink when it points to this database, rmdir of worktree/, incoming/ and the root -- rmdir refuses non-empty directories, so a second database in the same root survives untouched; what remains is listed on stderr
# @group   database
# @internal
# @see     destroy scaffold
#@end
_destroy_scaffold_remove0() {
        printf '%s\n' "rm -rf '$VM_BAKE_ROOT/bundle'"
        if test "$(readlink "$VM_BAKE_ROOT/db" 2>/dev/null)" = "$(basename "$(readlink -f "$VM_BAKE_BASE")")"; then
                printf '%s\n' "rm -f '$VM_BAKE_ROOT/db'"
        fi
        printf '%s\n' "rmdir '$VM_BAKE_ROOT/worktree' '$VM_BAKE_ROOT/incoming' 2>/dev/null || true"
        printf '%s\n' "rmdir '$VM_BAKE_ROOT' 2>/dev/null || true"
        printf '%s\n' "printf '# remaining under %s:\\n' '$VM_BAKE_ROOT' >&2"
        printf '%s\n' "ls -A '$VM_BAKE_ROOT' 2>/dev/null | sed 's/^/#   /' >&2 || true"
}

#@help _version0
# @command version
# @summary Print the version of this vm-bake: the dump format it writes and restores (VM_BAKE_FORMAT) and the commit of the checkout it runs from (git; 'unknown' without one) -- what a dump carries in its header and what a report names
# @group   database
# @env     VM_BAKE_FORMAT  the dump format major version
# @example vm-bake version
# @see     dump
# @see     restore
#@end
_version0() {
        local commit=""
        commit=$(git -C "$VM_BAKE_LIBDIR" rev-parse --short HEAD 2>/dev/null)
        test -n "$commit" || commit=$(head -n1 "$VM_BAKE_LIBDIR/VERSION" 2>/dev/null)	# the package: no checkout, the commit written at stage time
        printf 'vm-bake %s %s\n' "$VM_BAKE_FORMAT" "${commit:-unknown}"
}

#@help ___batch0
# @internal arity-0 sibling of 'batch' (reads commands from stdin)
#@end
___batch0() {
        local tempfile="$VM_BAKE_BASE/.tmp/batch.$$"

        cat <<EOF
"\$VM_BAKE_CONTEXT_SCRIPT" cat "$tempfile"
"\$VM_BAKE_CONTEXT_SCRIPT" batch "$tempfile" true
EOF
}

#@help __batch1
# @command batch <file>
# @summary Execute a file of vm-bake commands line by line (VM_BAKE_BATCH_KEEP_GOING: 0 = stop at the first failing line, 1 = keep going): the file is readable: rewrite to the runner 'batch <file> false' (no cleanup), else an error line
# @group   database
# @param   file  file of commands to execute
# @example vm-bake batch commands.txt
# @env     VM_BAKE_BATCH_KEEP_GOING  0 = stop at the first failing line, 1 = keep going
# @see     restore
#@end
__batch1() {
        if test -r "$1"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" batch '$1' false"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'batch: file not found or not readable: $1'"
        fi
}

#@help _batch2
# @internal batch execution chain step

# @env VM_BAKE_BATCH_KEEP_GOING  0 = stop at the first failing line, 1 = keep going
#@end
_batch2() {
        local filepath="$1"
        local cleanup="${2:-false}"
        local keep_going="${VM_BAKE_BATCH_KEEP_GOING:-0}"
        # keep-going belongs to THIS batch (its pin set it); a nested batch decides
        # for itself -- inherited, the checks of an inner batch would not stop its act
        unset VM_BAKE_BATCH_KEEP_GOING
        local base="$VM_BAKE_BASE"
        local success_count=0
        local fail_count=0

        # Save current batch2 interpreter to prevent nested batch double-cutting
        # Nested batches (e.g., a batch that itself emits a batch) should use "cat" interpreter
        # to avoid applying cut -b3- multiple times, which causes truncated output
        local saved_batch_interpreter="${VM_BAKE_INTERPRETER_batch2:-cat}"
        export VM_BAKE_INTERPRETER_batch2="cat"

        # Get batch ID for exit code storage
        local batch_id
        batch_id_take; batch_id=$BATCH_ID
        if [ -z "$batch_id" ]; then
                trace_log "!" "_batch2" "Failed to allocate batch ID"
                export VM_BAKE_INTERPRETER_batch2="$saved_batch_interpreter"
                set +e
                return 1
        fi

        # Extract producer bit from EXIT_BITS
        # Last character should be the producer bit we just set
        local exit_bits="${VM_BAKE_CONTEXT_EXIT_BITS:-0}"
        local p_bit="${exit_bits##* }"
        # Handle case where EXIT_BITS might just be "0" or "1" (not space-separated)
        case "$p_bit" in
        0|1) ;;  # Valid bit
        *) p_bit=0 ;;  # Default to 0 if unclear
        esac

        # Calculate batch exit code: 128 + (p << 6) + batch_id
        local batch_exit=$((128 + (p_bit << 6) + batch_id))

        # Create batch file with enhanced format
        local batch_file="$VM_BAKE_BASE/.tmp/batch-exits/$batch_id"
        # Truncate existing file or create new one (round-robin allocation)
        if ! : > "$batch_file" 2>>"$LOG_FILE"; then
                echo "# Error: Failed to create batch file: $batch_file" >&2
                export VM_BAKE_INTERPRETER_batch2="$saved_batch_interpreter"
                set +e
                return 1
        fi

        trace_log "|" "_batch2" "Batch execution (batch_id=$batch_id, producer_bit=$p_bit)"

        # Note: .tmp and .env/local directories created by init

        # Read commands from file and execute them
        # Note: || [ -n "$line" ] prevents set -e from triggering on EOF
        # and allows processing the last line even without trailing newline
        while IFS= read -r line || [ -n "$line" ]; do
                # Pass through empty lines (preserves dump formatting)
                if [ -z "$line" ]; then
                        echo ""
                        continue
                fi

                # Reproduce comments to stdout (for dump), then skip processing
                case "$line" in
                \#*)
                echo "$line"
                continue
                ;;
        esac

        # Validate line starts with vm-bake script context variable reference
        # Batch/dump files use the LITERAL string "$VM_BAKE_CONTEXT_SCRIPT" for portability
        # This ensures the dump is independent of the specific vm-bake.sh path that created it
        #
        # Expected format: "$VM_BAKE_CONTEXT_SCRIPT" <command> <args...>
        # Example:        "$VM_BAKE_CONTEXT_SCRIPT" setenv VM_BAKE_DISPLAY_ANSI 1
        case "$line" in
        \"\$VM_BAKE_CONTEXT_SCRIPT\"\ *)
        # Valid: quoted variable reference (portable format used in dump files)
        # Strip the literal "$VM_BAKE_CONTEXT_SCRIPT" and extract arguments
        remaining_args="${line#\"\$VM_BAKE_CONTEXT_SCRIPT\"}"
        remaining_args="${remaining_args# }"
        ;;
        *)
        # Invalid line - not a valid batch command
        echo "# ✗ Invalid batch file syntax: $line" >&2
        echo "#   Expected: \"\$VM_BAKE_CONTEXT_SCRIPT\" <command> <args...>" >&2
        echo "#   Example:  \"\$VM_BAKE_CONTEXT_SCRIPT\" setenv VM_BAKE_DISPLAY_ANSI 1" >&2
        fail_count=$((fail_count + 1))

        # Stop on error unless keep-going mode
        if [ "$keep_going" != "1" ]; then
                echo "" >&2
                echo "# Batch execution stopped due to error (fail-fast mode)" >&2
                echo "# Summary: $success_count succeeded, $fail_count failed" >&2
                export VM_BAKE_INTERPRETER_batch2="$saved_batch_interpreter"
                set +e
                return 1
        fi
        continue
        ;;
        esac

        # Skip if remaining_args is empty (malformed command)
        if [ -z "$remaining_args" ]; then
                echo "# ✗ Empty command after stripping script prefix" >&2
                fail_count=$((fail_count + 1))
                continue
        fi

        # Execute vm-bake commands via process_arguments()
        # This ensures each command gets its proper interpreter (terminal, combinator, or batch_combinator)
        # and tracing continues if VM_BAKE_TRACE_FILE is set
        trace_log "|" "_batch2" "Executing: $line"

        # Get function call for recording (resolve arguments to function name)
        resolve_call "$ANCHOR_FUNCTIONS" $remaining_args
        local function_call=$CALL

        # Execute command
        eval "process_arguments $remaining_args"
        local exit_code=$?

        # Record result in batch file
        # Format: EXIT_CODE|function args|BATCH_REF -- the pointer only for a line
        # whose function returns one (the runner, or a batch combinator)
        local line_is_batch=0
        case "${function_call%% *}" in
        _batch2|___*) line_is_batch=1 ;;
        esac
        if [ "$line_is_batch" = 1 ] && [ "$exit_code" -ge 128 ]; then
                # Nested batch: extract batch_id from exit code
                local nested_batch_id=$(( (exit_code - 128) & 0x3F ))
                echo "${exit_code}|${function_call}|${nested_batch_id}" >> "$batch_file"
        else
                # Regular exit
                echo "${exit_code}|${function_call}|" >> "$batch_file"
        fi

        # Track success/failure using recursive batch checker
        if ! check_batch_success "$exit_code" "$line_is_batch"; then
                trace_log "!" "_batch2" "Failed (exit code: $exit_code)"
                fail_count=$((fail_count + 1))
                echo "# failed: $line" >&2

                # Stop on error unless keep-going mode
                if [ "$keep_going" != "1" ]; then
                        echo "" >&2
                        echo "# Batch execution stopped due to error (fail-fast mode)" >&2
                        echo "# Summary: $success_count succeeded, $fail_count failed" >&2
                        export VM_BAKE_INTERPRETER_batch2="$saved_batch_interpreter"
                        set +e  # Ensure set +e before returning batch code
                        return "$batch_exit"
                fi
        else
                trace_log "|" "_batch2" "Success"
                success_count=$((success_count + 1))
        fi
        done < "$filepath"

        trace_log "|" "_batch2" "While loop completed"

        # Summary
        trace_log "|" "_batch2" "Summary: $success_count succeeded, $fail_count failed"

        # Show EXIT_BITS structure
        if [ -n "${VM_BAKE_CONTEXT_EXIT_BITS:-}" ]; then
                trace_log "|" "_batch2" "EXIT_BITS structure: ${VM_BAKE_CONTEXT_EXIT_BITS}"
        fi

        trace_log "|" "_batch2" "========================================"

        # Clean up temp file only on success (keep on failure for debugging)
        if [ $fail_count -eq 0 ] && [ "$cleanup" = "true" ]; then
                $MODIFY_FILE_REMOVE "$filepath"
        fi

        # Note: batch-exits file NOT cleaned up - retained for diagnostics
        # Round-robin allocation naturally overwrites old batch files

        trace_log "|" "_batch2" "Returning batch_exit=$batch_exit"

        # Restore original batch2 interpreter before returning
        export VM_BAKE_INTERPRETER_batch2="$saved_batch_interpreter"

        # CRITICAL: Ensure set +e before returning batch code >= 128
        # This prevents shell exit when returning non-zero exit codes
        set +e

        # Return batch exit code (128 + (p << 6) + batch_id)
        # This allows the caller to decode results using: vm-bake debug-exit $?
        return "$batch_exit"
}

#@help _printenv0
# @command printenv [<VAR>]
# @summary Show all effective environment variables, or just one
# @group   configuration
# @param   VAR  restrict output to a single variable
# @returns the effective environment
# @example vm-bake printenv
# @see     getenv
#@end
_printenv0() {
        cat <<EOF
echo "# =============================================================================="
echo "# Environment variables in isolated context:"
echo "# (sorted alphabetically)"
echo ""
printenv | sort
echo "# =============================================================================="
EOF
}


#@help __dump0
# @command dump [<template>]
# @summary The complete dump of this database as replay lines (rewrite to 'dump all'), or one template (rewrite to 'template dump <template>')
# @group   database
# @example vm-bake dump > vm-bake.dump
# @see     restore
# @see     template dump
#@end
__dump0() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dump all"
}

#@help ___dump_all0
# @command dump all
# @summary The database as replay lines: the header (generator, format, date, profile, base), the prologue (the overrides the replay depends on), the dowry records and the ssh host key records as witnesses (their objects and keys travel in the bundle), the templates parents first, the image and guest records as witnesses, the epilogue (every override, the pins included)
# @group   database
# @see     dump header
# @see     dump env prologue
# @see     dowry dump all
# @see     hostkey dump all
# @see     template dump all
# @see     image dump all
# @see     guest dump all
# @see     dump env epilogue
# @see     export
#@end
___dump_all0() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dump header"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dump env prologue"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry dump all"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey dump all"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template dump all"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image dump all"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dump all"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dump env epilogue"
}

#@help _dump_header0
# @command dump header
# @summary Display terminal, pinned to cat: the header of a dump as comment lines -- the generator ('vm-bake <format> <commit>', what 'version' prints), the format as '# Version:', the date, the profile of this database (the suffix of the VM_BAKE_PROFILE_ marker in .env/default, '# Profile:', what import names when there is no database yet) and the base
# @group   database
# @internal
# @env     VM_BAKE_FORMAT  the dump format major version
# @see     dump all
# @see     version
#@end
_dump_header0() {
	local commit=""
	commit=$(git -C "$VM_BAKE_LIBDIR" rev-parse --short HEAD 2>/dev/null)
	test -n "$commit" || commit=$(head -n1 "$VM_BAKE_LIBDIR/VERSION" 2>/dev/null)
	printf '# vm-bake database dump\n# Generator: vm-bake %s %s\n# Version: %s\n' "$VM_BAKE_FORMAT" "${commit:-unknown}" "$VM_BAKE_FORMAT"
	printf '# Generated: %s\n# Profile: %s\n# Base: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(ls "$VM_BAKE_BASE/.env/default" 2>/dev/null | sed -n 's/^VM_BAKE_PROFILE_//p' | head -n1 | tr '[:upper:]' '[:lower:]')" "$VM_BAKE_BASE"
}

#@help __dump1
# @internal arity-1 sibling of 'dump' (dump <template>): rewrite to 'template dump <template>'
#@end
__dump1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template dump $(sq "$1")"
}

#@help __restore1
# @command restore <file>
# @summary Replay a dump into this database: rewrite to 'batch <file>' -- the replay stops at the first failing line; an existing template is never re-minted, an identical record is a note
# @group   database
# @example vm-bake restore vm-bake.dump
# @see     dump
# @see     batch
#@end
__restore1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" batch $(sq "$1")"
}
