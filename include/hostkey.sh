#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# hostkey.sh - the ssh host keys of vm-bake as a resource of the database:
# a key lives under a name of its own, not under the name of a guest, and a
# guest binds one with 'guest hostkey use'. That is why a guest can be torn
# down and built again without its identity changing -- the key outlives the
# guest record, and the host's known_hosts stays right. A key is bound to at
# most one guest; the binding is a record of the guest family.

#@help
# @defgroup hostkey  Host keys
# @order   66
#   An ssh host key is a resource kept in the database under a name of its
#   own: 'hostkey create <name>' makes one, 'hostkey add <name> <path>'
#   takes an existing one in (a backup, a key from another host), 'hostkey
#   list' names them with their fingerprint and the guest that carries
#   them, 'hostkey drop' throws one out. A guest takes one with 'guest
#   hostkey use <guest> <hostkey>' -- at most one guest per key, so no two
#   guests ever answer with the same identity. 'guest make' is content with
#   a key named after the guest and makes it when it is missing.
#@end

#@help
# @defcompletion hostkey  hostkey
#@end

#@help ___hostkey_create1
# @command hostkey create <name>
# @summary Make an ssh host key under a name: the name is a word and free; then the key made with ssh-keygen (ed25519, no passphrase) in the database. The name is the key's, not a guest's -- 'guest hostkey use' hands it to one
# @group   hostkey
# @example vm-bake hostkey create dalmatia
# @see     hostkey add
# @see     hostkey drop
# @see     guest hostkey use
#@end
___hostkey_create1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey name valid $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey check absent $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey make $(sq "$1")"
}

#@help ___hostkey_add2
# @command hostkey add <name> <path>
# @summary Take an existing ssh host key into the database under a name: the name is a word and free, the path is an ed25519 private key that is there and readable with its public half beside it; then both copied into the database. This is how a key from a backup or another host keeps its identity here
# @group   hostkey
# @example vm-bake hostkey add dalmatia /home/brj/.vm-bake/db/guest/dalmatia/ssh_host_ed25519_key
# @see     hostkey create
# @see     hostkey list
#@end
___hostkey_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey name valid $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey check absent $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey key valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey place $(sq "$1") $(sq "$2")"
}

#@help ___hostkey_drop1
# @command hostkey drop <name>
# @summary Throw an ssh host key out of the database: it is kept there and no guest carries it ('guest hostkey drop <guest>' lets go first); then the record removed. A guest built again afterwards answers with a new identity, so every known_hosts that remembered it has to forget it
# @group   hostkey
# @example vm-bake hostkey drop dalmatia
# @see     hostkey create
# @see     guest hostkey drop
#@end
___hostkey_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey check $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey check free $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey remove $(sq "$1")"
}

#@help __hostkey_name_valid1
# @command hostkey name valid <name>
# @summary The name is a plain word ([A-Za-z0-9][A-Za-z0-9_.-]*): a comment line, else an error line
# @group   hostkey
# @internal
# @see     hostkey create
#@end
__hostkey_name_valid1() {
	local ok=yes
	case "$1" in ""|[!A-Za-z0-9]*|*[!A-Za-z0-9_.-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "hostkey name $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "hostkey: invalid name $1 ([A-Za-z0-9][A-Za-z0-9_.-]*)")"
	fi
}

#@help __hostkey_check_absent1
# @command hostkey check absent <name>
# @summary No ssh host key of that name in the database (read at generation time): a comment line, else an error line -- a key is never replaced in place, because a guest may carry it
# @group   hostkey
# @internal
# @see     hostkey create
# @see     hostkey add
#@end
__hostkey_check_absent1() {
	if test ! -e "$VM_BAKE_BASE/hostkey/$1/key"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "hostkey name $1 is free")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "hostkey $1 is already kept (hostkey list, hostkey drop $1)")"
	fi
}

#@help __hostkey_check1
# @command hostkey check <name>
# @summary The ssh host key is kept in the database (hostkey/<name>/key): a comment line, else an error line
# @group   hostkey
# @internal
# @see     hostkey drop
# @see     guest hostkey use
#@end
__hostkey_check1() {
	if test -e "$VM_BAKE_BASE/hostkey/$1/key"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "hostkey $1 is kept")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "unknown hostkey $1 (hostkey create $1, or hostkey list)")"
	fi
}

#@help __hostkey_check_free1
# @command hostkey check free <name>
# @summary No guest carries this ssh host key (every guest record read at generation time): a comment line, else an error line naming the guest
# @group   hostkey
# @internal
# @see     hostkey drop
#@end
__hostkey_check_free1() {
	local d="" k="" who=""
	for d in "$VM_BAKE_BASE"/guest/*/; do
		test -f "$d/hostkey" || continue
		IFS= read -r k < "$d/hostkey"
		test "$k" = "$1" || continue
		who="${who:+$who }$(basename "$d")"
	done
	if test -z "$who"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "hostkey $1 is carried by no guest")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "hostkey $1 is carried by $who (guest hostkey drop $who first)")"
	fi
}

#@help __hostkey_key_valid1
# @command hostkey key valid <path>
# @summary The path is an absolute one of a readable ed25519 private key with its public half '<path>.pub' beside it, which ssh-keygen reads (all of it at generation time): a comment line naming the fingerprint, else an error line. sshd in a guest is handed this one as /etc/ssh/ssh_host_ed25519_key, so another type is of no use here
# @group   hostkey
# @internal
# @see     hostkey add
#@end
__hostkey_key_valid1() {
	local why="" fp=""
	case "$1" in /*) ;; *) why="not an absolute path" ;; esac
	test -n "$why" || test -r "$1" || why="not there or not readable"
	test -n "$why" || test -r "$1.pub" || why="the public half $1.pub is not there (ssh-keygen -y -f $1 > $1.pub makes it)"
	test -n "$why" || fp=$(ssh-keygen -l -f "$1.pub" 2>/dev/null) || why="ssh-keygen does not read $1.pub as a key"
	test -n "$why" || case "$fp" in *"(ED25519)") ;; *) why="not an ed25519 key but ${fp##* }" ;; esac
	if test -z "$why"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "hostkey source $1: $(printf '%s' "$fp" | cut -d' ' -f2)")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "hostkey add: the key $1 is $why")"
	fi
}

#@help _hostkey_make1
# @command hostkey make <name>
# @summary Act terminal: the record hostkey/<name>/ with a new ed25519 key pair made by ssh-keygen without a passphrase (key 0600, key.pub 0644) and the date beside it; a key already there is left alone and an error -- 'hostkey check absent' has seen that it is not
# @group   hostkey
# @internal
# @see     hostkey create
#@end
_hostkey_make1() {
	local rec="$VM_BAKE_BASE/hostkey/$1" stamp=""
	stamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
	printf '%s\n' "$MODIFY_DIR_CREATE '$rec' && $MODIFY_FILE_PERMS 0700 '$rec'"
	printf '%s\n' "test ! -f '$rec/key' || { printf '# Error: hostkey %s is already there\\n' '$1' >&2; exit 1; }"
	printf '%s\n' "ssh-keygen -q -t ed25519 -N '' -C $(sq "vm-bake hostkey $1") -f '$rec/key' || exit 1"
	printf '%s\n' "printf '%s\\n' '$stamp' > '$rec/created'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$rec/key' '$rec/created' && $MODIFY_FILE_PERMS 0644 '$rec/key.pub'"
	printf '%s\n' "printf '# hostkey %s: %s\\n' '$1' \"\$(ssh-keygen -l -f '$rec/key.pub' | cut -d' ' -f2)\" >&2"
}

#@help _hostkey_place2
# @command hostkey place <name> <path>
# @summary Act terminal: the record hostkey/<name>/ with the key pair copied from the path (key 0600, key.pub 0644) and the date beside it; a key already there is left alone and an error
# @group   hostkey
# @internal
# @see     hostkey add
#@end
_hostkey_place2() {
	local rec="$VM_BAKE_BASE/hostkey/$1" stamp=""
	stamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
	printf '%s\n' "$MODIFY_DIR_CREATE '$rec' && $MODIFY_FILE_PERMS 0700 '$rec'"
	printf '%s\n' "test ! -f '$rec/key' || { printf '# Error: hostkey %s is already there\\n' '$1' >&2; exit 1; }"
	printf '%s\n' "install -m 600 $(sq "$2") '$rec/key' && install -m 644 $(sq "$2.pub") '$rec/key.pub' || exit 1"
	printf '%s\n' "printf '%s\\n' '$stamp' > '$rec/created'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$rec/created'"
	printf '%s\n' "printf '# hostkey %s: %s from %s\\n' '$1' \"\$(ssh-keygen -l -f '$rec/key.pub' | cut -d' ' -f2)\" $(sq "$2") >&2"
}

#@help _hostkey_remove1
# @command hostkey remove <name>
# @summary Act terminal: the record hostkey/<name>/ removed with both halves of the key
# @group   hostkey
# @internal
# @see     hostkey drop
#@end
_hostkey_remove1() {
	printf '%s\n' "rm -rf '$VM_BAKE_BASE/hostkey/$1'"
	emit_note "hostkey $1: removed from the database"
}

#@help _hostkey_list0
# @command hostkey list
# @summary List the ssh host keys of the database (one line each): name, fingerprint, created, and the guest that carries it (every guest record read here) or '-' for a free one
# @group   hostkey
# @example vm-bake hostkey list
# @see     hostkey create
# @see     guest hostkey use
#@end
_hostkey_list0() {
	local d="" g="" k="" c="" who="" name="" n=0
	printf '%s\n' "# hostkey (name  fingerprint  created  guest)"
	for d in "$VM_BAKE_BASE"/hostkey/*/; do
		test -e "$d/key.pub" || continue
		name=$(basename "$d")
		IFS= read -r c 2>/dev/null < "$d/created" || c=-
		who=-
		for g in "$VM_BAKE_BASE"/guest/*/; do
			test -f "$g/hostkey" || continue
			IFS= read -r k < "$g/hostkey"
			test "$k" = "$name" || continue
			who=$(basename "$g")
		done
		printf '#   %-16s %-50s %-22s %s\n' "$name" "$(ssh-keygen -l -f "$d/key.pub" 2>/dev/null | cut -d' ' -f2)" "$c" "$who"
		n=$((n + 1))
	done
	test "$n" -gt 0 || printf '%s\n' "#   (none)"
}

#@help ___hostkey_dump_all0
# @command hostkey dump all
# @summary Every ssh host key record as replay lines, one 'hostkey dump record' per record, no records a comment -- the dump's witness of the keys (name, created); the keys themselves travel in the export bundle, not in the dump
# @group   hostkey
# @example vm-bake hostkey dump all
# @see     hostkey dump record
# @see     export
#@end
___hostkey_dump_all0() {
	local d="" n=0
	for d in "$VM_BAKE_BASE"/hostkey/*/; do
		test -e "$d/key" || continue
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey dump record $(sq "$(basename "$d")")"
		n=$((n + 1))
	done
	test "$n" -gt 0 || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'no host keys in this database'"
}

#@help ___hostkey_dump_record1
# @command hostkey dump record <name>
# @summary The replay line of one ssh host key record, a batch pinned to cat so it is shown rather than run: 'hostkey record restore' with the date
# @group   hostkey
# @internal
# @see     hostkey dump all
#@end
___hostkey_dump_record1() {
	local c=-
	IFS= read -r c 2>/dev/null < "$VM_BAKE_BASE/hostkey/$1/created" || c=-
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey record restore $(sq "$1") $(sq "$c")"
}

#@help ___hostkey_record_restore2
# @command hostkey record restore <name> <created>
# @summary An ssh host key record from a dump, the witness of a key kept elsewhere or before: the name is valid; then 'hostkey record compare' -- no record of that name here: placed (the key itself comes with the bundle, 'import place' puts it there); the same record: a comment; one that differs: an error
# @group   hostkey
# @example vm-bake hostkey record restore dalmatia 2026-11-06T12:00:00Z
# @see     hostkey dump record
# @see     import
#@end
___hostkey_record_restore2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey name valid $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey record compare $(sq "$1") $(sq "$2")"
}

#@help __hostkey_record_compare2
# @command hostkey record compare <name> <created>
# @summary The record of this ssh host key here against the one from the dump: no record here rewrites to 'hostkey record place' (the key itself may already lie there -- 'import place' puts it in place before the replay), the same one is a comment, a differing one an error line naming both
# @group   hostkey
# @internal
# @see     hostkey record restore
#@end
__hostkey_record_compare2() {
	local rec="$VM_BAKE_BASE/hostkey/$1" c=""
	if test ! -f "$rec/created"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey record place $(sq "$1") $(sq "$2")"
		return 0
	fi
	IFS= read -r c 2>/dev/null < "$rec/created" || c=-
	if test "$c" = "$2"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "hostkey $1: the record is the one of the dump")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "hostkey $1: here created $c, the dump says created $2 -- hostkey drop $1 first")"
	fi
}

#@help _hostkey_record_place2
# @command hostkey record place <name> <created>
# @summary Act terminal: the record hostkey/<name>/ with the date from the dump (0600), WITHOUT the key -- that one travels in the bundle and 'import place' puts it beside it
# @group   hostkey
# @internal
# @see     hostkey record restore
#@end
_hostkey_record_place2() {
	local rec="$VM_BAKE_BASE/hostkey/$1"
	printf '%s\n' "$MODIFY_DIR_CREATE '$rec' && $MODIFY_FILE_PERMS 0700 '$rec'"
	printf '%s\n' "printf '%s\\n' $(sq "$2") > '$rec/created'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$rec/created'"
	emit_note "hostkey $1: record placed (created $2), the key comes with the bundle"
}
