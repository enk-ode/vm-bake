#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# dowry.sh - the dowry of vm-bake: an object kept in the database under a
# name, which a template hands to the home of every guest it stands for
# ('template home copy'). The object is copied into the database once and
# travels in the export bundle, so a guest's dowry is reproducible on
# another host; where it lands in the guest says the template, because that
# may differ from guest to guest.

#@help
# @defgroup dowry  Dowry
# @order   65
#   A dowry is an object (a file or a whole directory) kept in the database
#   under a name: 'dowry add <dowry> <source>' copies it there, 'dowry list'
#   names what is kept, 'dowry drop' throws it out. A template hands a dowry
#   to its guests with 'template home copy idem|overwrite <template> <dowry>
#   <destination>' -- 'idem' puts it only where it is missing (the guest
#   keeps what it has made of it), 'overwrite' replaces it at every start.
#   'guest start' places them before it hangs the overlays in.
#@end

#@help
# @defcompletion dowry   dowry
# @defcompletion source  files
# @defcompletion destination  none
#@end

#@help ___dowry_add2
# @command dowry add <dowry> <source>
# @summary Keep an object in the database under a name: the name is a word, the source is there and readable; then the object copied into the database with its source and the date beside it. An existing dowry of that name is replaced, so this is also how a dowry is refreshed
# @group   dowry
# @example vm-bake dowry add claude-state /home/brj/vm-bake/guest/dalmatia/.claude
# @see     dowry drop
# @see     dowry list
# @see     template home copy idem
#@end
___dowry_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry name valid $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry source valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry place $(sq "$1") $(sq "$2")"
}

#@help ___dowry_drop1
# @command dowry drop <dowry>
# @summary Throw a dowry out of the database: it is kept there; then the record removed. A template that still hands it out keeps its line -- 'guest start' then says the dowry is gone
# @group   dowry
# @example vm-bake dowry drop claude-state
# @see     dowry add
# @see     template home unlink idem
#@end
___dowry_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry check $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry remove $(sq "$1")"
}

#@help __dowry_name_valid1
# @command dowry name valid <dowry>
# @summary The name is a plain word ([A-Za-z0-9][A-Za-z0-9_.-]*): a comment line, else an error line
# @group   dowry
# @internal
# @see     dowry add
#@end
__dowry_name_valid1() {
	local ok=yes
	case "$1" in ""|[!A-Za-z0-9]*|*[!A-Za-z0-9_.-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "dowry name $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "dowry: invalid name $1 ([A-Za-z0-9][A-Za-z0-9_.-]*)")"
	fi
}

#@help __dowry_source_valid1
# @command dowry source valid <source>
# @summary The source is an absolute path that is there and readable (read at generation time): a comment line, else an error line
# @group   dowry
# @internal
# @see     dowry add
#@end
__dowry_source_valid1() {
	local ok=yes
	case "$1" in /*) ;; *) ok=no ;; esac
	test -r "$1" || ok=no
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "dowry source $1 readable")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "dowry add: the source is an absolute path that is there and readable, not $1")"
	fi
}

#@help __dowry_check1
# @command dowry check <dowry>
# @summary The dowry is kept in the database (dowry/<dowry>/object): a comment line, else an error line
# @group   dowry
# @internal
# @see     dowry drop
# @see     template home copy idem
#@end
__dowry_check1() {
	if test -e "$VM_BAKE_BASE/dowry/$1/object"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "dowry $1 is kept")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "unknown dowry $1 (dowry add $1 <source>, or dowry list)")"
	fi
}

#@help _dowry_place2
# @command dowry place <dowry> <source>
# @summary Act terminal: the record dowry/<dowry>/ with the object copied from the source (a file or a whole directory, times and modes kept), the source path and the date beside it (0600); an object of that name already there is replaced
# @group   dowry
# @internal
# @see     dowry add
#@end
_dowry_place2() {
	local rec="$VM_BAKE_BASE/dowry/$1" stamp=""
	stamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
	printf '%s\n' "$MODIFY_DIR_CREATE '$rec' && $MODIFY_FILE_PERMS 0700 '$rec'"
	printf '%s\n' "rm -rf '$rec/object' && cp -Rp $(sq "$2") '$rec/object' || exit 1"
	printf '%s\n' "printf '%s\\n' $(sq "$2") > '$rec/source'"
	printf '%s\n' "printf '%s\\n' '$stamp' > '$rec/created'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$rec/source' '$rec/created'"
	printf '%s\n' "printf '# dowry %s: %s from %s\\n' '$1' \"\$(du -sh '$rec/object' | cut -f1 | tr -d ' ')\" $(sq "$2") >&2"
}

#@help _dowry_remove1
# @command dowry remove <dowry>
# @summary Act terminal: the record dowry/<dowry>/ removed with its object
# @group   dowry
# @internal
# @see     dowry drop
#@end
_dowry_remove1() {
	printf '%s\n' "rm -rf '$VM_BAKE_BASE/dowry/$1'"
	emit_note "dowry $1: removed from the database"
}

#@help _dowry_list0
# @command dowry list
# @summary List the dowry records (one line each): name, size, kind, created, source
# @group   dowry
# @example vm-bake dowry list
# @see     dowry add
#@end
_dowry_list0() {
	local d="" s="" c="" n=0 kind=""
	printf '%s\n' "# dowry (name  size  kind  created  source)"
	for d in "$VM_BAKE_BASE"/dowry/*/; do
		test -e "$d/object" || continue
		IFS= read -r s 2>/dev/null < "$d/source" || s=-
		IFS= read -r c 2>/dev/null < "$d/created" || c=-
		kind=file; test ! -d "$d/object" || kind=directory
		printf '#   %-20s %-7s %-10s %-22s %s\n' "$(basename "$d")" "$(du -sh "$d/object" | cut -f1 | tr -d ' ')" "$kind" "$c" "$s"
		n=$((n + 1))
	done
	test "$n" -gt 0 || printf '%s\n' "#   (none)"
}

#@help ___dowry_dump_all0
# @command dowry dump all
# @summary Every dowry record as replay lines, one 'dowry dump record' per record, no records a comment -- the dump's witness of the dowry (name, source, created); the object itself travels in the export bundle, not in the dump
# @group   dowry
# @example vm-bake dowry dump all
# @see     dowry dump record
# @see     export
#@end
___dowry_dump_all0() {
	local d="" n=0
	for d in "$VM_BAKE_BASE"/dowry/*/; do
		test -e "$d/object" || continue
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry dump record $(sq "$(basename "$d")")"
		n=$((n + 1))
	done
	test "$n" -gt 0 || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'no dowry in this database'"
}

#@help ___dowry_dump_record1
# @command dowry dump record <dowry>
# @summary The replay line of one dowry record, a batch pinned to cat so it is shown rather than run: 'dowry record restore' with source and created
# @group   dowry
# @internal
# @see     dowry dump all
#@end
___dowry_dump_record1() {
	local rec="$VM_BAKE_BASE/dowry/$1" s=- c=-
	IFS= read -r s 2>/dev/null < "$rec/source" || s=-
	IFS= read -r c 2>/dev/null < "$rec/created" || c=-
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry record restore $(sq "$1") $(sq "$s") $(sq "$c")"
}

#@help ___dowry_record_restore3
# @command dowry record restore <dowry> <source> <created>
# @summary A dowry record from a dump, the witness of an object kept elsewhere or before: the name is valid; then 'dowry record compare' -- no record of that name here: placed (the object itself comes with the bundle, 'import place' puts it there); the same record: a comment; one that differs: an error
# @group   dowry
# @example vm-bake dowry record restore claude-state /home/brj/.claude 2026-11-05T12:00:00Z
# @see     dowry dump record
# @see     import
#@end
___dowry_record_restore3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry name valid $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry record compare $(sq "$1") $(sq "$2") $(sq "$3")"
}

#@help __dowry_record_compare3
# @command dowry record compare <dowry> <source> <created>
# @summary The record of this dowry here against the one from the dump: no record here rewrites to 'dowry record place' (the object itself may already lie there -- 'import place' puts it in place before the replay), the same one is a comment, a differing one an error line naming both
# @group   dowry
# @internal
# @see     dowry record restore
#@end
__dowry_record_compare3() {
	local rec="$VM_BAKE_BASE/dowry/$1" s="" c=""
	if test ! -f "$rec/source"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry record place $(sq "$1") $(sq "$2") $(sq "$3")"
		return 0
	fi
	IFS= read -r s 2>/dev/null < "$rec/source" || s=-
	IFS= read -r c 2>/dev/null < "$rec/created" || c=-
	if test "$s" = "$2" && test "$c" = "$3"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "dowry $1: the record is the one of the dump")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "dowry $1: here source $s created $c, the dump says source $2 created $3 -- dowry drop $1 first")"
	fi
}

#@help _dowry_record_place3
# @command dowry record place <dowry> <source> <created>
# @summary Act terminal: the record dowry/<dowry>/ with source and created from the dump (0600), WITHOUT the object -- that one travels in the bundle and 'import place' puts it beside them
# @group   dowry
# @internal
# @see     dowry record restore
#@end
_dowry_record_place3() {
	local rec="$VM_BAKE_BASE/dowry/$1"
	printf '%s\n' "$MODIFY_DIR_CREATE '$rec' && $MODIFY_FILE_PERMS 0700 '$rec'"
	printf '%s\n' "printf '%s\\n' $(sq "$2") > '$rec/source'"
	printf '%s\n' "printf '%s\\n' $(sq "$3") > '$rec/created'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$rec/source' '$rec/created'"
	emit_note "dowry $1: record placed (source $2, created $3), the object comes with the bundle"
}

#@help __dowry_check_file1
# @command dowry check file <dowry>
# @summary The dowry is kept in the database and its object is one regular file (a template file line puts it at a path in the system; a directory has no mode and no single path): a comment line, else an error line
# @group   dowry
# @internal
# @see     dowry check
# @see     template file add
#@end
__dowry_check_file1() {
	if test -f "$VM_BAKE_BASE/dowry/$1/object"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "dowry $1 is kept and is a file")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "dowry $1 is not one file in the database (dowry add $1 <file>, or dowry list)")"
	fi
}
