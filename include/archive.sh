#!/bin/sh
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# archive.sh - the pair that travels: the DUMP (the replay as text, for a
# git repository whose signed commit vouches for it) and the BUNDLE (the
# files the records point at and the bake needs again: guest host keys,
# package files, home seeds -- never the images, they are baked anew), bound
# by the seal line of the dump. export writes the pair from this database,
# import checks a pair end to end before a byte lands, then replays it.

#@help
# @defgroup archive  Export and import
# @order   80
#   'export <dump> <bundle>' writes the two artifacts: the dump (what
#   'dump' prints: the environment the replay needs, every template, the
#   image and guest records as witnesses, every override) to a path you
#   commit, and the bundle (a tar of export/tree in the database: the guest
#   host keys, the package files of every template's pkgfile list, the home
#   seeds of every home list, each hashed in a MANIFEST) to a store of your
#   own. The seal line at the end of the dump names the bundle by sha256
#   and size. 'import <dump> <bundle>' verifies the seal, unpacks into
#   <root>/incoming, checks the MANIFEST, refuses a file that differs from
#   one already here, places the missing ones and replays the dump. Nothing
#   is signed or encrypted here: the commit that carries the dump is.
#@end

#@help ___export2
# @command export <dump> <bundle>
# @summary Write the pair: the DUMP to <dump> (a path of your choosing, absolute; commit it), the BUNDLE to <bundle> (absolute; keep it where the host keys may lie). Both paths absolute, the archiver set; then the dump written, the collection, the tree, the MANIFEST, the bundle packed, the dump sealed with the bundle's hash -- an earlier dump at that path is overwritten, its seal with it
# @group   archive
# @env     VM_BAKE_ARCHIVER  the packing template; $a is the archive, $b the base directory
# @example vm-bake export ~/git/vm-bake-dump/illyria/production/dump.sh ~/Infrastruktur/vm-bake-export/illyria/production/20261103.tar.gz
# @see     import
# @see     dump
# @see     bundle
# @see     seal
#@end
___export2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" archive path absolute $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" archive path absolute $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" archiver set"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dump all > $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" export collection write"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" export tree write"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" manifest '$VM_BAKE_BASE/export/collection' '$VM_BAKE_BASE/export/tree/MANIFEST'"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" bundle '$VM_BAKE_BASE/export/tree' $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" seal $(sq "$1") $(sq "$2")"
}

#@help __archive_path_absolute1
# @command archive path absolute <path>
# @summary The path is absolute: a comment line, else an error line (the pair is named by paths that mean the same from every directory)
# @group   archive
# @internal
# @see     export
# @see     bundle
#@end
__archive_path_absolute1() {
	if test "${1#/}" != "$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "path $1 absolute")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "archive: the path must be absolute: $1")"
	fi
}

#@help __archiver_set0
# @command archiver set
# @summary VM_BAKE_ARCHIVER is set: a comment line, else an error line (bootstrap again refreshes the defaults)
# @group   archive
# @internal
# @env     VM_BAKE_ARCHIVER  the packing template
# @see     bundle
#@end
__archiver_set0() {
	if test -n "${VM_BAKE_ARCHIVER:-}"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'archiver set'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'bundle: VM_BAKE_ARCHIVER not set (bootstrap <name> <profile> again refreshes the defaults)'"
	fi
}

#@help _export_collection_write0
# @command export collection write
# @summary Act terminal (owner): export/collection written -- one line per file the bundle carries, <kind>/<path> below the tree: guest/<guest>/ssh_host_ed25519_key and .pub of every guest record that has one, pkg/<file> for every pkgfile line of every template that is in VM_BAKE_PKG_DIR, home/<path> for every file and symlink under every home line of every template (the invoking user's home, read here at generation); sorted, duplicates once; a pkgfile or home path that is not here is noted and not bundled
# @group   archive
# @internal
# @env     VM_BAKE_PKG_DIR  where the package files of the pkgfile lists lie
# @see     export
# @see     export tree write
#@end
_export_collection_write0() {
	local home="" g="" l="" f="" lines="" missing="" n=0
	eval "home=~$(id -un)"
	for g in "$VM_BAKE_BASE"/guest/*/; do
		test -f "$g/ssh_host_ed25519_key" || continue
		lines="$lines
guest/$(basename "$g")/ssh_host_ed25519_key
guest/$(basename "$g")/ssh_host_ed25519_key.pub"
	done
	for l in "$VM_BAKE_BASE"/template/*; do
		test -L "$l" || continue
		test -f "$l/pkgfile" && while IFS= read -r f; do
			test -n "$f" || continue
			if test -f "$VM_BAKE_PKG_DIR/$f"; then lines="$lines
pkg/$f"; else missing="$missing pkg/$f"; fi
		done < "$l/pkgfile"
		test -f "$l/home" && while IFS= read -r f; do
			test -n "$f" || continue
			if test -e "$home/$f" || test -L "$home/$f"; then lines="$lines
$(find "$home/$f" \( -type f -o -type l \) | sed "s|^$home/|home/|")"; else missing="$missing home/$f"; fi
		done < "$l/home"
	done
	lines=$(printf '%s\n' "$lines" | grep . | LC_ALL=C sort -u)
	n=$(printf '%s\n' "$lines" | grep -c .)
	printf '%s\n' "$MODIFY_DIR_CREATE '$VM_BAKE_BASE/export'"
	printf '%s\n' "cat > '$VM_BAKE_BASE/export/collection' <<'VMBCOLLECTION'"
	test -z "$lines" || printf '%s\n' "$lines"
	printf '%s\n' "VMBCOLLECTION"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$VM_BAKE_BASE/export/collection'"
	emit_note "export: collection of $n files (guest host keys, package files, home seeds)"
	test -z "$missing" || emit_note "export: not here, not bundled:$missing"
}

#@help _export_tree_write0
# @command export tree write
# @summary Act terminal (owner): export/tree made anew from the collection -- the old tree removed, every listed file copied to tree/<kind>/<path> from where its kind lives (guest: this database, pkg: VM_BAKE_PKG_DIR, home: the invoking user's home), modes kept, a symlink copied as the link; the collection copied beside them as tree/collection. The tree IS what the bundle carries, readable before it is packed
# @group   archive
# @internal
# @env     VM_BAKE_PKG_DIR  where the package files of the pkgfile lists lie
# @see     export
# @see     export collection write
# @see     bundle
#@end
_export_tree_write0() {
	local home="" tree="$VM_BAKE_BASE/export/tree" l="" src="" n=0
	eval "home=~$(id -un)"
	printf '%s\n' "rm -rf '$tree' && $MODIFY_DIR_CREATE '$tree' && $MODIFY_FILE_PERMS 0700 '$tree'"
	while IFS= read -r l; do
		test -n "$l" || continue
		case "$l" in
		guest/*) src="$VM_BAKE_BASE/$l" ;;
		pkg/*) src="$VM_BAKE_PKG_DIR/${l#pkg/}" ;;
		home/*) src="$home/${l#home/}" ;;
		*) src="" ;;
		esac
		test -n "$src" || continue
		printf '%s\n' "$MODIFY_DIR_CREATE '$tree/$(dirname "$l")' && cp -RpP $(sq "$src") '$tree/$l' || exit 1"
		n=$((n + 1))
	done < "$VM_BAKE_BASE/export/collection"
	printf '%s\n' "cp -p '$VM_BAKE_BASE/export/collection' '$tree/collection'"
	emit_note "export: tree of $n files under $tree"
}

#@help ___manifest2
# @command manifest <collection> <manifest>
# @summary Hash every entry of a collection into a manifest (LC_ALL=C-sorted 'path sha256=hash' lines, a symlink as 'path symlink=target', the collection itself listed last): the collection is readable, the manifest is named MANIFEST (import looks for it by name in the unpacked bundle) and lies in the tree the paths are relative to, every entry is hashable; then 'manifest write'
# @group   archive
# @param   collection  the collection file export wrote
# @param   manifest    <tree>/MANIFEST, the tree being what the bundle packs
# @example vm-bake manifest ~/.vm-bake/db/export/collection ~/.vm-bake/db/export/tree/MANIFEST
# @see     export
# @see     manifest match
# @see     bundle
#@end
___manifest2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" collection readable $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" manifest named $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" manifest entries hashable $(sq "$1") $(sq "$(dirname "$2")")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" manifest write $(sq "$1") $(sq "$2")"
}

#@help __collection_readable1
# @command collection readable <collection>
# @summary The collection file is there and readable: a comment line, else an error line
# @group   archive
# @internal
# @see     manifest
# @see     bundle
#@end
__collection_readable1() {
	if test -r "$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "collection $1 readable")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "no such collection $1 (export collection write)")"
	fi
}

#@help __manifest_named1
# @command manifest named <manifest>
# @summary The manifest path ends in /MANIFEST: a comment line, else an error line
# @group   archive
# @internal
# @see     manifest
#@end
__manifest_named1() {
	if test "${1##*/}" = MANIFEST; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "manifest $1 named")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "manifest: the manifest must be named MANIFEST: $1 (import looks for it by name)")"
	fi
}

#@help __manifest_entries_hashable2
# @command manifest entries hashable <collection> <tree>
# @summary Every entry of the collection is a file or symlink under the tree with no whitespace in its path: a comment line, else an error line naming the first that is not (a missing entry ends the command instead of shortening the manifest; a name with a space cannot be listed in 'path sha256=' lines)
# @group   archive
# @internal
# @see     manifest
#@end
__manifest_entries_hashable2() {
	local l="" bad=""
	while IFS= read -r l; do
		test -n "$l" || continue
		case "$l" in *[[:space:]]*) bad="whitespace in the name: $l"; break ;; esac
		test -f "$2/$l" || test -L "$2/$l" || { bad="not under the tree: $l"; break; }
	done 2>/dev/null < "$1"
	if test -z "$bad"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "every entry of $1 is hashable under $2")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "manifest: $bad (export tree write)")"
	fi
}

#@help _manifest_write2
# @command manifest write <collection> <manifest>
# @summary Act terminal (owner): the manifest written as one heredoc -- every collection entry hashed here at generation against the tree the manifest lies in (sha256 of a file, the target of a symlink), then 'collection sha256=...' for the collection's own copy in the tree; mode 0644
# @group   archive
# @internal
# @see     manifest
#@end
_manifest_write2() {
	local tree="" l="" n=0
	tree=$(dirname "$2")
	n=$(grep -c . "$1" 2>/dev/null)
	printf '%s\n' "cat > '$2.new' <<'VMBMANIFEST'"
	while IFS= read -r l; do
		test -n "$l" || continue
		if test -L "$tree/$l"; then
			printf '%s symlink=%s\n' "$l" "$(readlink "$tree/$l")"
		else
			printf '%s sha256=%s\n' "$l" "$(sha256 -q "$tree/$l" 2>/dev/null)"
		fi
	done 2>/dev/null < "$1"
	printf 'collection sha256=%s\n' "$(sha256 -q "$tree/collection" 2>/dev/null)"
	printf '%s\n' "VMBMANIFEST"
	printf '%s\n' "mv -f '$2.new' '$2' && $MODIFY_FILE_PERMS 0644 '$2'"
	emit_note "manifest: $2 lists $n entries and the collection"
}

#@help ___bundle2
# @command bundle <tree> <bundle>
# @summary Pack the tree with VM_BAKE_ARCHIVER into <bundle>: the tree's collection readable, the archiver set, the bundle path absolute, the MANIFEST in the tree (a bundle without its tamper detection is not produced); then 'bundle pack'
# @group   archive
# @env     VM_BAKE_ARCHIVER  the packing template; $a is the archive, $b the base directory
# @example vm-bake bundle ~/.vm-bake/db/export/tree ~/Infrastruktur/vm-bake-export/illyria/production/20261103.tar.gz
# @see     export
# @see     extract
# @see     bundle pack
#@end
___bundle2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" collection readable $(sq "$1/collection")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" archiver set"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" archive path absolute $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" manifest present $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" bundle pack $(sq "$1") $(sq "$2")"
}

#@help __manifest_present1
# @command manifest present <tree>
# @summary <tree>/MANIFEST is there: a comment line, else an error line (manifest first)
# @group   archive
# @internal
# @see     bundle
#@end
__manifest_present1() {
	if test -f "$1/MANIFEST"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "manifest in $1")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "bundle: no MANIFEST in $1 (manifest <collection> $1/MANIFEST first)")"
	fi
}

#@help _bundle_pack2
# @command bundle pack <tree> <bundle>
# @summary Act terminal (owner): the bundle's directory, $a and $b for the VM_BAKE_ARCHIVER template, the template in a group fed the file list (the collection's entries, MANIFEST, collection) on stdin; the bundle 0600 -- it carries host keys
# @group   archive
# @internal
# @env     VM_BAKE_ARCHIVER  the packing template; $a is the archive, $b the base directory
# @see     bundle
#@end
_bundle_pack2() {
	local n=0
	n=$(grep -c . "$1/collection" 2>/dev/null)
	printf '%s\n' "$MODIFY_DIR_CREATE '$(dirname "$2")'"
	printf "a='%s'\n" "$2"
	printf "b='%s'\n" "$1"
	printf '%s\n' "{ $VM_BAKE_ARCHIVER ; } <<'VMBUNDLE'"
	grep . "$1/collection" 2>/dev/null
	printf '%s\n' "MANIFEST"
	printf '%s\n' "collection"
	printf '%s\n' "VMBUNDLE"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$2'"
	emit_note "bundled $((n + 2)) entries (MANIFEST and the collection included) -> $2"
}

#@help ___seal2
# @command seal <dump> <bundle>
# @summary Append the bundle's sha256 and size to the dump as its seal line ('# Bundle: sha256=... bytes=...'): both files readable, the dump not yet sealed (a dump names ONE bundle; export again for a new pair); then 'seal write'
# @group   archive
# @example vm-bake seal ~/git/vm-bake-dump/illyria/production/dump.sh ~/Infrastruktur/vm-bake-export/illyria/production/20261103.tar.gz
# @see     seal verify
# @see     export
#@end
___seal2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dump readable $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" bundle readable $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" seal absent $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" seal write $(sq "$1") $(sq "$2")"
}

#@help __dump_readable1
# @command dump readable <dump>
# @summary The dump file is there and readable: a comment line, else an error line
# @group   archive
# @internal
# @see     seal
# @see     import
#@end
__dump_readable1() {
	if test -r "$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "dump $1 readable")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "no such dump $1")"
	fi
}

#@help __bundle_readable1
# @command bundle readable <bundle>
# @summary The bundle is there and readable: a comment line, else an error line
# @group   archive
# @internal
# @see     seal
# @see     extract
#@end
__bundle_readable1() {
	if test -r "$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "bundle $1 readable")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "no such bundle $1")"
	fi
}

#@help __seal_absent1
# @command seal absent <dump>
# @summary The dump carries no seal line yet: a comment line, else an error line (a dump names ONE bundle; export again for a new pair)
# @group   archive
# @internal
# @see     seal
#@end
__seal_absent1() {
	if grep -qs '^# Bundle: sha256=' "$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "seal: $1 is sealed already (a dump names one bundle; export again for a new pair)")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "dump $1 not sealed yet")"
	fi
}

#@help _seal_write2
# @command seal write <dump> <bundle>
# @summary Act terminal (owner): the one line that appends the seal ('# Bundle: sha256=<sha256 of the bundle> bytes=<size>', both read here at generation) to the dump
# @group   archive
# @internal
# @see     seal
#@end
_seal_write2() {
	local line=""
	line="# Bundle: sha256=$(sha256 -q "$2" 2>/dev/null) bytes=$(wc -c 2>/dev/null < "$2" | tr -d ' ')"
	printf '%s\n' "printf '%s\\n' '$line' >> '$1'"
	emit_note "seal: $1 names $(basename "$2") (${line#\# Bundle: })"
}

#@help ___seal_verify2
# @command seal verify <dump> <bundle>
# @summary The dump's seal line names THIS bundle (sha256 and size): both files readable, the dump sealed, the seal matching -- a mismatch fails the command before anything is unpacked
# @group   archive
# @example vm-bake seal verify dump.sh 20261103.tar.gz
# @see     seal
# @see     import
#@end
___seal_verify2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dump readable $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" bundle readable $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" seal present $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" seal matches $(sq "$1") $(sq "$2")"
}

#@help __seal_present1
# @command seal present <dump>
# @summary The dump carries a seal line: a comment line, else an error line (it was not exported with a bundle -- a dump and a bundle are bound by content, not by name)
# @group   archive
# @internal
# @see     seal verify
#@end
__seal_present1() {
	if grep -qs '^# Bundle: sha256=' "$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "dump $1 sealed")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "seal verify: $1 carries no seal line, it was not exported with a bundle (a dump and a bundle are bound by content, not by name)")"
	fi
}

#@help __seal_matches2
# @command seal matches <dump> <bundle>
# @summary The dump's seal line equals this bundle's sha256 and size: a log line, else an error line (MISMATCHED PAIR)
# @group   archive
# @internal
# @see     seal verify
#@end
__seal_matches2() {
	local want="" have=""
	want=$(grep '^# Bundle: sha256=' "$1" 2>/dev/null | head -n1)
	have="# Bundle: sha256=$(sha256 -q "$2" 2>/dev/null) bytes=$(wc -c 2>/dev/null < "$2" | tr -d ' ')"
	if test "$want" = "$have"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" log $(sq "seal verify: $(basename "$2") is the bundle $1 names (${have#\# Bundle: })")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "seal verify: MISMATCHED PAIR, $1 does not name this bundle (dump says ${want#\# Bundle: }; bundle is ${have#\# Bundle: })")"
	fi
}

#@help ___import2
# @command import <dump> <bundle>
# @summary Replay an exported pair into this database (bootstrap one first: the dump's '# Profile:' header names the profile), checked end to end before a byte lands: the seal (this bundle is the one the dump names), incoming cleared, the bundle unpacked into <root>/incoming/<bundle name>, its MANIFEST against the unpacked tree, every file of the collection absent here or identical ('import check clear'), the missing ones placed, the dump replayed. Into an EMPTY database by intent: a template already here is never re-minted, a record that differs is refused, a file that differs from the bundle's is refused before anything lands
# @group   archive
# @param   dump    the dump of the pair
# @param   bundle  the bundle the dump's seal names
# @env     VM_BAKE_ROOT  the root the databases live in; incoming/ beside them is import's scratch
# @example vm-bake import ~/git/vm-bake-dump/illyria/production/dump.sh ~/Infrastruktur/vm-bake-export/illyria/production/20261103.tar.gz
# @see     export
# @see     seal verify
# @see     extract
# @see     manifest match
# @see     import check clear
# @see     import place
# @see     restore
# @see     bootstrap
#@end
___import2() {
	local inc=""
	inc="$VM_BAKE_ROOT/incoming/$(basename "$2" | sed 's/\.[a-z.]*$//')"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" seal verify $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" incoming clear $(sq "$inc")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" extract $(sq "$2") $(sq "$inc")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" manifest match $(sq "$inc/MANIFEST") $(sq "$inc")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" import check clear $(sq "$inc")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" import place $(sq "$inc")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" restore $(sq "$1")"
}

#@help __incoming_clear1
# @command incoming clear <directory>
# @summary Empty one scratch directory under <root>/incoming/, import's own unpacking area, cleared before each extract so a re-import never trips over the last one: the path lies below incoming/ and carries no '..' -> 'incoming remove', else an error line (only import's scratch is cleared here, never a database)
# @group   archive
# @internal
# @env     VM_BAKE_ROOT  the root the databases live in; incoming/ beside them is import's scratch
# @see     import
# @see     extract
#@end
__incoming_clear1() {
	if test "${1#"$VM_BAKE_ROOT"/incoming/}" != "$1" && test "${1%%..*}" = "$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" incoming remove $(sq "$1")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "incoming clear: not below $VM_BAKE_ROOT/incoming (or carrying ..): $1 -- only the scratch of import is cleared here, never a database")"
	fi
}

#@help _incoming_remove1
# @command incoming remove <directory>
# @summary Act terminal (owner): rm -rf of the scratch directory
# @group   archive
# @internal
# @see     incoming clear
#@end
_incoming_remove1() {
	printf '%s\n' "rm -rf $(sq "$1")"
	emit_note "incoming clear: $1"
}

#@help ___extract2
# @command extract <bundle> <destination>
# @summary Unpack a bundle into a scratch directory with VM_BAKE_EXTRACTOR: the bundle readable, the extractor set, the destination absolute and empty (or not yet there); then 'extract unpack'
# @group   archive
# @env     VM_BAKE_EXTRACTOR  the unpacking template; $a is the archive, $d the destination
# @example vm-bake extract ~/Infrastruktur/vm-bake-export/illyria/production/20261103.tar.gz ~/.vm-bake/incoming/20261103
# @see     bundle
# @see     import
#@end
___extract2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" bundle readable $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" extractor set"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" archive path absolute $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" extract destination empty $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" extract unpack $(sq "$1") $(sq "$2")"
}

#@help __extractor_set0
# @command extractor set
# @summary VM_BAKE_EXTRACTOR is set: a comment line, else an error line (bootstrap again refreshes the defaults)
# @group   archive
# @internal
# @env     VM_BAKE_EXTRACTOR  the unpacking template
# @see     extract
#@end
__extractor_set0() {
	if test -n "${VM_BAKE_EXTRACTOR:-}"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'extractor set'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'extract: VM_BAKE_EXTRACTOR not set (bootstrap <name> <profile> again refreshes the defaults)'"
	fi
}

#@help __extract_destination_empty1
# @command extract destination empty <destination>
# @summary The destination is empty or not there yet: a comment line, else an error line
# @group   archive
# @internal
# @see     extract
#@end
__extract_destination_empty1() {
	if test -z "$(ls -A "$1" 2>/dev/null)"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "destination $1 empty")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "extract: destination not empty: $1 (choose an empty or new directory)")"
	fi
}

#@help _extract_unpack2
# @command extract unpack <bundle> <destination>
# @summary Act terminal (owner): the destination directory (0700), $a and $d for the VM_BAKE_EXTRACTOR template, the template
# @group   archive
# @internal
# @env     VM_BAKE_EXTRACTOR  the unpacking template; $a is the archive, $d the destination
# @see     extract
#@end
_extract_unpack2() {
	printf '%s\n' "$MODIFY_DIR_CREATE $(sq "$2") && $MODIFY_FILE_PERMS 0700 $(sq "$2")"
	printf "a='%s'\n" "$1"
	printf "d='%s'\n" "$2"
	printf '%s\n' "$VM_BAKE_EXTRACTOR"
	emit_note "extracted $1 -> $2"
}

#@help ___manifest_match2
# @command manifest match <manifest> <tree>
# @summary Does the tree match the manifest? The manifest is readable and lists entries, the tree exists; then 'manifest tree matches' -- every listed file hashes identically, every listed symlink points where recorded (MISSING, CHANGED, RETARGETED fail). Files present but unlisted are not findings: the tree is an extraction directory
# @group   archive
# @param   manifest  the MANIFEST to check
# @param   tree      the directory its paths are relative to
# @example vm-bake manifest match ~/.vm-bake/incoming/20261103/MANIFEST ~/.vm-bake/incoming/20261103
# @see     import
# @see     manifest
#@end
___manifest_match2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" manifest readable $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" manifest tree exists $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" manifest tree matches $(sq "$1") $(sq "$2")"
}

#@help __manifest_readable1
# @command manifest readable <manifest>
# @summary The manifest is readable and lists at least one entry: a comment line, else an error line
# @group   archive
# @internal
# @see     manifest match
#@end
__manifest_readable1() {
	local n=""
	n=$(grep -cE "^[^ ]+ (sha256|symlink)=" "$1" 2>/dev/null)
	if test "${n:-0}" -gt 0; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "manifest $1 lists entries")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "manifest match: no such manifest, or it lists no entries: $1")"
	fi
}

#@help __manifest_tree_exists1
# @command manifest tree exists <tree>
# @summary The tree directory exists: a comment line, else an error line
# @group   archive
# @internal
# @see     manifest match
#@end
__manifest_tree_exists1() {
	if test -d "$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "tree $1 exists")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "manifest match: no such directory $1")"
	fi
}

#@help __manifest_tree_matches2
# @command manifest tree matches <manifest> <tree>
# @summary No finding against the manifest (the tree read here, entry by entry): a log line with the entry count, else an error line carrying the findings (MISSING SYMLINK, RETARGETED, MISSING, CHANGED)
# @group   archive
# @internal
# @see     manifest match
#@end
__manifest_tree_matches2() {
	local rel="" val="" findings=""
	findings=$(while read -r rel val; do
		case "$val" in
		symlink=*)
			test -L "$2/$rel" || printf 'MISSING SYMLINK %s\n' "$rel"
			test ! -L "$2/$rel" || test "$(readlink "$2/$rel")" = "${val#symlink=}" || printf 'RETARGETED %s\n' "$rel"
			;;
		sha256=*)
			test -f "$2/$rel" || printf 'MISSING %s\n' "$rel"
			test ! -f "$2/$rel" || test "$(sha256 -q "$2/$rel" 2>/dev/null)" = "${val#sha256=}" || printf 'CHANGED %s\n' "$rel"
			;;
		esac
	done 2>/dev/null < "$1")
	if test -z "$findings"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" log $(sq "manifest match: $(grep -cE "^[^ ]+ (sha256|symlink)=" "$1" 2>/dev/null) entries, tree matches")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "manifest match: $1 does not describe $2 (the TREE differs from what the sender listed): $(printf '%s' "$findings" | tr '\n' ';')")"
	fi
}

#@help __import_check_clear1
# @command import check clear <incoming>
# @summary Every file of the unpacked bundle's collection is either absent at its place here (guest/<guest>/... in this database, pkg/<file> in VM_BAKE_PKG_DIR, home/<path> in the invoking user's home) or identical to what is there (same sha256, a symlink with the same target), read here at generation: a comment line counting what is new and what is already here, else an error line naming every file that DIFFERS or whose kind is unknown -- nothing of yours is overwritten; move it away or keep it and drop the line from the collection
# @group   archive
# @internal
# @env     VM_BAKE_PKG_DIR  where the package files of the pkgfile lists go
# @see     import
# @see     import place
#@end
__import_check_clear1() {
	local home="" l="" dst="" new=0 same=0 findings=""
	eval "home=~$(id -un)"
	while IFS= read -r l; do
		test -n "$l" || continue
		case "$l" in
		guest/*) dst="$VM_BAKE_BASE/$l" ;;
		pkg/*) dst="$VM_BAKE_PKG_DIR/${l#pkg/}" ;;
		home/*) dst="$home/${l#home/}" ;;
		*) findings="$findings UNKNOWN $l;"; continue ;;
		esac
		if test -L "$dst"; then
			if test "$(readlink "$dst")" = "$(readlink "$1/$l")"; then same=$((same + 1)); else findings="$findings DIFFERS $l;"; fi
		elif test -e "$dst"; then
			if test "$(sha256 -q "$dst" 2>/dev/null)" = "$(sha256 -q "$1/$l" 2>/dev/null)"; then same=$((same + 1)); else findings="$findings DIFFERS $l;"; fi
		else
			new=$((new + 1))
		fi
	done 2>/dev/null < "$1/collection"
	if test -z "$findings"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "import: $new files to place, $same already here and identical")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "import: a file here differs from the bundle's, nothing placed:$findings (move yours away, or keep it and remove the line from $1/collection)")"
	fi
}

#@help _import_place1
# @command import place <incoming>
# @summary Act terminal (owner): every file of the collection that is absent at its place copied there from the unpacked bundle (one line per file, modes kept, a symlink as the link; guest keys land in this database, package files in VM_BAKE_PKG_DIR, home seeds in the invoking user's home), the ones already here left alone -- 'import check clear' has seen that they are identical
# @group   archive
# @internal
# @env     VM_BAKE_PKG_DIR  where the package files of the pkgfile lists go
# @see     import
# @see     import check clear
#@end
_import_place1() {
	local home="" l="" dst="" n=0 kept=0
	eval "home=~$(id -un)"
	while IFS= read -r l; do
		test -n "$l" || continue
		case "$l" in
		guest/*) dst="$VM_BAKE_BASE/$l" ;;
		pkg/*) dst="$VM_BAKE_PKG_DIR/${l#pkg/}" ;;
		home/*) dst="$home/${l#home/}" ;;
		*) continue ;;
		esac
		if test -e "$dst" || test -L "$dst"; then
			kept=$((kept + 1))
			continue
		fi
		printf '%s\n' "$MODIFY_DIR_CREATE $(sq "$(dirname "$dst")") && cp -RpP $(sq "$1/$l") $(sq "$dst") || exit 1"
		n=$((n + 1))
	done 2>/dev/null < "$1/collection"
	emit_note "import: $n files placed, $kept already here"
}
