#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# template.sh - the templates of vm-bake: the build recipe of an image as a
# record of decisions (base, bake, firmware, resource, and the lists
# package, rc, user, service, forbid, data, session), inheriting from a
# parent down to the root 'empty'. add stores, drop removes, mask hides an
# inherited line; show resolves the chain. Checked at bake time, not here.

#@help
# @defgroup template  Templates
# @order   50
#   A template is the build recipe of an image: the base (a release, a
#   stage, a cloud image, an iso), how it is baked, firmware, resources,
#   and the lists of packages, rc.conf lines, users, host services the
#   guest may use, what it must not reach, its data disks and session
#   protocols. Templates inherit: scalars from the nearest ancestor, lists
#   as the union of the chain minus the masks. The root 'empty' always
#   exists and holds nothing.
#@end

#@help
# @defcompletion template      template
# @defcompletion parent        none
# @defcompletion arch          none
# @defcompletion version       none
# @defcompletion url           none
# @defcompletion sha256        none
# @defcompletion cpu           none
# @defcompletion sockets       none
# @defcompletion cores         none
# @defcompletion threads       none
# @defcompletion memory        none
# @defcompletion disk          none
# @defcompletion package       none
# @defcompletion origin       none
# @defcompletion key          none
# @defcompletion pattern      none
# @defcompletion variable      none
# @defcompletion variant       none
# @defcompletion argument      none
# @defcompletion size          none
# @defcompletion class         none
# @defcompletion protocol      none
# @defcompletion family        none
# @defcompletion chain         none
# @defcompletion leaf          none
# @defcompletion line          none
#@end

TEMPLATE_LAYOUT=""
TEMPLATE_FAMILIES="package pkgfile port rc env user home service forbid data session tag"
TEMPLATE_LEAVES="base bake firmware resource topology"

#@help _template_list0
# @command template list
# @summary List the templates with their derived state (one line each): name, id, parent, own base -- the root 'empty' first
# @group   template
# @example vm-bake template list
# @see     template add
# @see     template show
#@end
_template_list0() {
	local l="" name="" id="" parent="" base="" n=0
	printf '%s\n' "# templates (name  id  parent  base)"
	printf '#   %-16s %-24s %-16s %s\n' empty root - -
	for l in "$VM_BAKE_BASE"/template/*; do
		test -L "$l" || continue
		n=$((n + 1))
		name=${l##*/}; id=$(basename "$(readlink "$l")"); parent=-; base=-
		test -f "$l/parent" && IFS= read -r parent < "$l/parent"
		test -f "$l/base" && IFS= read -r base < "$l/base"
		printf '#   %-16s %-24s %-16s %s\n' "$name" "$id" "$parent" "$base"
	done
	test "$n" -gt 0 || printf '#   (no templates of your own -- template add <template> [<parent>])\n'
}

#@help __template_add1
# @command template add <template> [<parent>]
# @summary Create a template below a parent (the root 'empty' when none is named): rewrite to 'template add <template> empty'
# @group   template
# @example vm-bake template add freebsd
# @example vm-bake template add freebsd-15.1 freebsd
# @see     template list
# @see     template drop
#@end
__template_add1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template add $(sq "$1") empty"
}

#@help ___template_add2
# @internal arity-2 sibling of 'template add' (template add <template> <parent>): the name is a record name, the parent exists; then 'template add new' -- IDEMPOTENT, an existing template is left untouched (a replayed dump must never mint a fresh id)
#@end
___template_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template name valid $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template add new $(sq "$1") $(sq "$2")"
}

#@help __template_name_valid1
# @command template name valid <template>
# @summary The name is a record name ([A-Za-z0-9_.-], not . or .., not the reserved words empty and all): a comment line, else an error line
# @group   template
# @internal
# @see     template add
#@end
__template_name_valid1() {
	local ok=yes
	case "$1" in ""|.|..|empty|all|*[!A-Za-z0-9_.-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'template name $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template add: invalid template name $1 ([A-Za-z0-9_.-], not empty or all)")"
	fi
}

#@help __template_check_template1
# @command template check template <template>
# @summary The template exists (its name symlink under template/, or the root 'empty'): a comment line, else an error line -- the first line of every batch that acts on a template
# @group   template
# @internal
# @see     template add
# @see     template list
#@end
__template_check_template1() {
	if test "$1" = empty || test -L "$VM_BAKE_BASE/template/$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'template $1 exists'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "unknown template $1 (template add $1, or template list)")"
	fi
}

#@help __template_add_new2
# @command template add new <template> <parent>
# @summary No template of that name yet: rewrite to 'template mint <template> <parent>', else a note line (idempotent add)
# @group   template
# @internal
# @see     template add
#@end
__template_add_new2() {
	if test ! -L "$VM_BAKE_BASE/template/$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template mint '$1' '$2'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note 'template $1 already exists (idempotent add)'"
	fi
}

#@help _template_mint2
# @command template mint <template> <parent>
# @summary Act terminal: a fresh record id, the record under .templates/<id>/ with metadata (name, created) and parent, the name symlink template/<template>
# @group   template
# @internal
# @see     template add
#@end
_template_mint2() {
	local id="" stamp=""
	id="template-$(od -An -tx1 -N6 /dev/urandom | tr -d ' \n')"
	stamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
	install_layout "$VM_BAKE_BASE/.templates/$id" "$TEMPLATE_LAYOUT"
	printf '%s\n' "echo 'name=$1' > '$VM_BAKE_BASE/.templates/$id/metadata'"
	printf '%s\n' "echo 'created=$stamp' >> '$VM_BAKE_BASE/.templates/$id/metadata'"
	printf '%s\n' "echo '$2' > '$VM_BAKE_BASE/.templates/$id/parent'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$VM_BAKE_BASE/.templates/$id/metadata' '$VM_BAKE_BASE/.templates/$id/parent'"
	printf '%s\n' "$MODIFY_LINK_FORCE '../.templates/$id' '$VM_BAKE_BASE/template/$1'"
	printf '%s\n' "printf '# Created template %s -> %s (parent %s)\\n' '$1' '$id' '$2' >&2"
}

#@help ___template_drop1
# @command template drop <template>
# @summary Remove a template: it exists, it is not the root and no template names it as parent; then 'template unlink'
# @group   template
# @example vm-bake template drop freebsd-16.0
# @see     template add
#@end
___template_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template drop allowed $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template unlink $(sq "$1")"
}

#@help __template_drop_allowed1
# @command template drop allowed <template>
# @summary The template is not the root 'empty' and no other template has it as parent: a comment line, else an error line naming the children
# @group   template
# @internal
# @see     template drop
#@end
__template_drop_allowed1() {
	local l="" p="" children=""
	for l in "$VM_BAKE_BASE"/template/*; do
		test -L "$l" && test -f "$l/parent" || continue
		IFS= read -r p < "$l/parent"
		test "$p" = "$1" && children="$children ${l##*/}"
	done
	if test "$1" = empty; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'template drop: the root empty cannot be dropped'"
	elif test -n "$children"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template drop: $1 is the parent of$children (drop them first)")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'template $1 has no children'"
	fi
}

#@help _template_unlink1
# @command template unlink <template>
# @summary Act terminal: remove the record .templates/<id> and the name symlink
# @group   template
# @internal
# @see     template drop
#@end
_template_unlink1() {
	local id=""
	id=$(basename "$(readlink "$VM_BAKE_BASE/template/$1")")
	printf '%s\n' "rm -rf '$VM_BAKE_BASE/.templates/$id'"
	printf '%s\n' "$MODIFY_FILE_REMOVE '$VM_BAKE_BASE/template/$1'"
	printf '%s\n' "printf '# Dropped template %s (%s)\\n' '$1' '$id' >&2"
}

#@help ___template_show1
# @command template show <template>
# @summary The template resolved over its chain: the head (parent, chain, the scalars with their origin), then every list with the origin of each line
# @group   template
# @example vm-bake template show freebsd-dev
# @see     template list
#@end
___template_show1() {
	local f=""
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain head $(sq "$1")"
	for f in $TEMPLATE_FAMILIES; do
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") $f"
	done
}

#@help __template_chain_head1
# @command template chain head <template>
# @summary The chain of the template (root to leaf) read at generation time: rewrite to 'template show head <template> <chain>', an error line when the parents do not end at empty
# @group   template
# @internal
# @see     template show
#@end
__template_chain_head1() {
	local cur="$1" chain="" p="" n=0
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	if test "$cur" = empty; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template show head $(sq "$1") $(sq "empty${chain:+ $chain}")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template $1: the chain of parents does not end at empty ($chain ...)")"
	fi
}

#@help __template_chain_table2
# @command template chain table <template> <family>
# @summary The chain of the template read at generation time: rewrite to 'template line table <template> <family> <chain>', an error line when the parents do not end at empty
# @group   template
# @internal
# @see     template show
#@end
__template_chain_table2() {
	local cur="$1" chain="" p="" n=0
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	if test "$cur" = empty; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line table $(sq "$1") $(sq "$2") $(sq "empty${chain:+ $chain}")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template $1: the chain of parents does not end at empty ($chain ...)")"
	fi
}

#@help _template_show_head2
# @command template show head <template> <chain>
# @summary Display terminal: name and id, parent, the chain, and each scalar (base, bake, firmware, resource, topology) with the template it comes from
# @group   template
# @internal
# @see     template show
#@end
_template_show_head2() {
	local id="root" parent="-" a="" leaf="" val="" origin=""
	if test "$1" != empty; then
		id=$(basename "$(readlink "$VM_BAKE_BASE/template/$1")")
		IFS= read -r parent < "$VM_BAKE_BASE/template/$1/parent"
	fi
	printf '# template %s (%s)\n' "$1" "$id"
	printf '#   %-9s: %s\n' parent "$parent"
	printf '#   %-9s: %s\n' chain "$(printf '%s' "$2" | sed 's/ / > /g')"
	for leaf in $TEMPLATE_LEAVES; do
		val=-; origin=-
		for a in $2; do
			test -f "$VM_BAKE_BASE/template/$a/$leaf" || continue
			IFS= read -r val < "$VM_BAKE_BASE/template/$a/$leaf"; origin=$a
		done
		printf '#   %-9s: %-36s (%s)\n' "$leaf" "$val" "$origin"
	done
}

#@help _template_line_table3
# @command template line table <template> <family> <chain>
# @summary Display terminal: the resolved lines of one list over the chain, each with its origin (template/awk/template-table.awk)
# @group   template
# @internal
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
# @see     template show
#@end
_template_line_table3() {
	printf '# %s of %s (origin  entry)\n' "$2" "$1"
	awk -v base="$VM_BAKE_BASE" -v family="$2" -v chain="$3" -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk"
}

#@help ___template_base_release3
# @command template base release <template> <arch> <version>
# @summary The base is a FreeBSD release from the pkgbase repository (bake: chroot): the template exists, arch and version are valid; then the record 'release <arch> <version>' (immutable: template base drop first)
# @group   template
# @example vm-bake template base release freebsd-15.1 amd64 15.1-RELEASE
# @see     template base stage
# @see     template base drop
#@end
___template_base_release3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template arch valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template version valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") base $(sq "release $2 $3")"
}

#@help ___template_base_stage3
# @command template base stage <template> <arch> <stage>
# @summary The base is self-baked: the worktree of an elvboot stage, 'make packages' yields the repository (bake: chroot): the template exists, the arch is valid, the stage is a record name; then the record 'stage <arch> <stage>'
# @group   template
# @example vm-bake template base stage freebsd-stage amd64 daily-v1
# @see     template base release
#@end
___template_base_stage3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template arch valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") base $(sq "stage $2 $3")"
}

#@help ___template_base_image5
# @command template base image <template> <arch> <version> <url> <sha256>
# @summary The base is a ready-made image (a FreeBSD VM image, a Linux cloud image): the template exists, arch, version (a word; FreeBSD's <major>.<minor>-RELEASE gives the ABI), url and digest are valid; then the record 'image <arch> <version> <url> <sha256>'
# @group   template
# @example vm-bake template base image freebsd-builder amd64 15.1-RELEASE https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/FreeBSD-15.1-RELEASE-amd64-ufs.raw.xz a8e2...9409
# @see     template base iso
#@end
___template_base_image5() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template arch valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template url valid $(sq "$4")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template sha256 valid $(sq "$5")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") base $(sq "image $2 $3 $4 $5")"
}

#@help ___template_base_iso4
# @command template base iso <template> <arch> <path> <sha256>
# @summary The base is an installation medium (Windows; bake: cloud-init via cloudbase-init): the template exists, arch, path and digest are valid; then the record 'iso <arch> <path> <sha256>'
# @group   template
# @example vm-bake template base iso windows amd64 /data/iso/Win11_24H2_German_x64.iso 0123...cdef
# @see     template base image
#@end
___template_base_iso4() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template arch valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template path valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template sha256 valid $(sq "$4")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") base $(sq "iso $2 $3 $4")"
}

#@help ___template_base_drop1
# @command template base drop <template>
# @summary Remove the template's own base record: the template exists, a base is set; then 'template leaf erase'
# @group   template
# @example vm-bake template base drop freebsd-16.0
# @see     template base release
#@end
___template_base_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf set $(sq "$1") base"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf erase $(sq "$1") base"
}

#@help ___template_bake_chroot1
# @command template bake chroot <template>
# @summary The image is baked offline: the base installed into the mounted image (mdconfig), packages and configuration via chroot, no first boot: the template exists; then the record
# @group   template
# @example vm-bake template bake chroot freebsd
# @see     template bake cloud-init
# @see     template bake drop
#@end
___template_bake_chroot1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") bake chroot"
}

#@help ___template_bake_cloud_init1
# @command template bake cloud-init <template>
# @summary The image is baked by a first boot in a throwaway guest: cloud-init (cloudbase-init on Windows) applies packages and configuration from the rendered user-data, then the disk is sealed: the template exists; then the record
# @group   template
# @example vm-bake template bake cloud-init debian
# @see     template bake chroot
#@end
___template_bake_cloud_init1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") bake cloud-init"
}

#@help ___template_bake_autoinstall1
# @command template bake autoinstall <template>
# @summary The image is installed by OpenBSD's autoinstall(8) in a throwaway guest: the base is the install ISO (template base iso), the response file and a site set rendered from the template answer the installer, the first boot adds the packages and powers off, then the disk is sealed: the template exists; then the record
# @group   template
# @example vm-bake template bake autoinstall openbsd
# @see     template bake chroot
# @see     template bake cloud-init
# @see     image make openbsd
#@end
___template_bake_autoinstall1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") bake autoinstall"
}

#@help __template_bake2
# @internal dispatch fallback of 'template bake <word> <template>' for a word that is neither chroot, cloud-init nor autoinstall: an error line
#@end
__template_bake2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template bake: unknown way $1 (chroot | cloud-init | autoinstall)")"
}

#@help ___template_bake_drop1
# @command template bake drop <template>
# @summary Remove the template's own bake record: the template exists, a bake is set; then 'template leaf erase'
# @group   template
# @see     template bake chroot
#@end
___template_bake_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf set $(sq "$1") bake"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf erase $(sq "$1") bake"
}

#@help ___template_firmware_uefi1
# @command template firmware uefi <template>
# @summary The guest boots UEFI (edk2-bhyve): the template exists; then the record
# @group   template
# @example vm-bake template firmware uefi freebsd
# @see     template firmware bios
# @see     template firmware drop
#@end
___template_firmware_uefi1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") firmware uefi"
}

#@help ___template_firmware_bios1
# @command template firmware bios <template>
# @summary The guest boots BIOS (grub2-bhyve): the template exists; then the record
# @group   template
# @see     template firmware uefi
#@end
___template_firmware_bios1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") firmware bios"
}

#@help __template_firmware2
# @internal dispatch fallback of 'template firmware <word> <template>' for a word that is neither uefi nor bios: an error line
#@end
__template_firmware2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template firmware: unknown firmware $1 (uefi | bios)")"
}

#@help ___template_firmware_drop1
# @command template firmware drop <template>
# @summary Remove the template's own firmware record: the template exists, a firmware is set; then 'template leaf erase'
# @group   template
# @see     template firmware uefi
#@end
___template_firmware_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf set $(sq "$1") firmware"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf erase $(sq "$1") firmware"
}

#@help ___template_resource4
# @command template resource <template> <cpu> <memory> <disk>
# @summary The guest's resources: cpus, memory and the size of disk0 (the image): the template exists, the count and the sizes are valid; then the record '<cpu> <memory> <disk>'
# @group   template
# @example vm-bake template resource freebsd-dev 8 32G 64G
# @see     template resource drop
#@end
___template_resource4() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template count valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template size valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template size valid $(sq "$4")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") resource $(sq "$2 $3 $4")"
}

#@help ___template_topology4
# @command template topology <template> <sockets> <cores> <threads>
# @summary How the guest's cpus are laid out for the guest's own scheduler: sockets, cores per socket, threads per core; the template exists and the three are counts whose product is the cpu count of 'template resource' (checked when the guest's configuration is written, where both are read); then the record '<sockets> <cores> <threads>'. Without a record a guest gets 1 socket of <cpu> cores with 1 thread each -- one real core per cpu, which is what bhyve should present unless a guest is meant to see SMT
# @group   template
# @example vm-bake template topology freebsd-dev 1 8 1
# @see     template topology drop
# @see     template resource
# @see     guest conf write
#@end
___template_topology4() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template count valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template count valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template count valid $(sq "$4")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf record $(sq "$1") topology $(sq "$2 $3 $4")"
}

#@help ___template_topology_drop1
# @command template topology drop <template>
# @summary Remove the template's own topology record: the template exists, a topology is set; then 'template leaf erase' -- its guests fall back to 1 socket of <cpu> cores with 1 thread each
# @group   template
# @see     template topology
#@end
___template_topology_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf set $(sq "$1") topology"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf erase $(sq "$1") topology"
}

#@help ___template_resource_drop1
# @command template resource drop <template>
# @summary Remove the template's own resource record: the template exists, a resource is set; then 'template leaf erase'
# @group   template
# @see     template resource
#@end
___template_resource_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf set $(sq "$1") resource"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf erase $(sq "$1") resource"
}

#@help __template_leaf_record3
# @command template leaf record <template> <leaf> <line>
# @summary The scalar record: no record yet: rewrite to 'template leaf write'; the same line already: a note (idempotent); a different line: an error line (records are immutable: drop, then add)
# @group   template
# @internal
# @see     template base release
#@end
__template_leaf_record3() {
	local cur=""
	if test ! -f "$VM_BAKE_BASE/template/$1/$2"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template leaf write $(sq "$1") $(sq "$2") $(sq "$3")"
	else
		IFS= read -r cur < "$VM_BAKE_BASE/template/$1/$2"
		if test "$cur" = "$3"; then
			printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "template $1: $2 unchanged ($3)")"
		else
			printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template $1: $2 is '$cur' (immutable: template $2 drop $1, then add)")"
		fi
	fi
}

#@help _template_leaf_write3
# @command template leaf write <template> <leaf> <line>
# @summary Act terminal: write the scalar record (0600) and say so
# @group   template
# @internal
# @see     template leaf record
#@end
_template_leaf_write3() {
	printf '%s\n' "printf '%s\\n' $(sq "$3") > '$VM_BAKE_BASE/template/$1/$2'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$VM_BAKE_BASE/template/$1/$2'"
	printf '%s\n' "printf '# template %s: %s = %s\\n' '$1' '$2' $(sq "$3") >&2"
}

#@help __template_leaf_set2
# @command template leaf set <template> <leaf>
# @summary The template has its own record of that scalar: a comment line, else an error line
# @group   template
# @internal
# @see     template base drop
#@end
__template_leaf_set2() {
	if test -f "$VM_BAKE_BASE/template/$1/$2"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'template $1 has $2'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template $1: no own $2 set (an inherited value is dropped at its origin)")"
	fi
}

#@help _template_leaf_erase2
# @command template leaf erase <template> <leaf>
# @summary Act terminal: remove the scalar record and say so
# @group   template
# @internal
# @see     template leaf set
#@end
_template_leaf_erase2() {
	printf '%s\n' "$MODIFY_FILE_REMOVE '$VM_BAKE_BASE/template/$1/$2'"
	printf '%s\n' "printf '# template %s: %s dropped\\n' '$1' '$2' >&2"
}

#@help __template_package_add2
# @command template package add <template> <package>|-
# @summary Add a package to the template's own list (idempotent); '-' reads names from stdin, one per line, each validated before anything is appended: rewrite to 'template package add stdin <template>', else to 'template package add entry <template> <package>'
# @group   template
# @example vm-bake template package add freebsd-dev vscode
# @example printf 'vscode\nclaude-code\n' | vm-bake template package add freebsd-dev -
# @see     template package drop
# @see     template package mask
# @see     template package show
#@end
__template_package_add2() {
	if test "$2" = -; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template package add stdin $(sq "$1")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template package add entry $(sq "$1") $(sq "$2")"
	fi
}

#@help ___template_package_add_stdin1
# @command template package add stdin <template>
# @summary The names from stdin (fd 3, bound by the top-level call), every one checked before the first is appended
# @group   template
# @internal
# @see     template package add
#@end
___template_package_add_stdin1() {
	local line="" lines=""
	while IFS= read -r line <&3; do
		test -n "$line" || continue
		lines="$lines$line
"
	done
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s' "$lines" | while IFS= read -r line; do
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template package valid $(sq "$line")"
	done
	printf '%s' "$lines" | while IFS= read -r line; do
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") package $(sq "$line")"
	done
	test -n "$lines" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'template package add: nothing on stdin'"
}

#@help ___template_package_add_entry2
# @command template package add entry <template> <package>
# @summary One package: the template exists, the name is a package name; then 'template line append'
# @group   template
# @internal
# @see     template package add
#@end
___template_package_add_entry2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template package valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") package $(sq "$2")"
}

#@help __template_package_valid1
# @command template package valid <package>
# @summary The name is a package name ([A-Za-z0-9_.+-], a category prefix allowed: editors/vscode): a comment line, else an error line
# @group   template
# @internal
# @see     template package add
#@end
__template_package_valid1() {
	local ok=yes
	case "$1" in ""|*[!A-Za-z0-9_.+/-]*|/*|*/|*//*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'package $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template package: invalid package name $1 ([A-Za-z0-9_.+-], category/name)")"
	fi
}

#@help ___template_package_drop2
# @command template package drop <template> <package>
# @summary Remove a package from the template's own list: the template exists, the package is listed there; then 'template line remove'
# @group   template
# @example vm-bake template package drop freebsd-dev emacs
# @see     template package add
#@end
___template_package_drop2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") package $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") package $(sq "$2")"
}

#@help ___template_package_mask2
# @command template package mask <template> <package>
# @summary Hide an inherited package in this template and below (own entries are dropped, not masked): the template exists, the name is a package name; then 'template line mask'
# @group   template
# @example vm-bake template package mask freebsd-dev emacs
# @see     template package drop
#@end
___template_package_mask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template package valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") package $(sq "$2")"
}

#@help ___template_package_show1
# @command template package show <template>
# @summary The packages resolved over the chain, each with its origin: the template exists; then 'template chain table'
# @group   template
# @example vm-bake template package show freebsd-dev
# @see     template show
#@end
___template_package_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") package"
}

#@help ___template_port_add2
# @command template port add <template> <origin>
# @summary Add a port to build from source in the builder guest (category/name): the template exists, the origin is a port origin; then 'template line append' -- the bake builds it there and installs the package into the image after the packages
# @group   template
# @example vm-bake template port add freebsd-x editors/vscode
# @see     template port drop
# @see     template port show
# @see     template package add
#@end
___template_port_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template port valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") port $(sq "$2")"
}

#@help __template_port_valid1
# @command template port valid <origin>
# @summary The origin is category/name of the ports tree ([a-z0-9-]+/[A-Za-z0-9_.+-]+): a comment line, else an error line
# @group   template
# @internal
# @see     template port add
#@end
__template_port_valid1() {
	local ok=no
	case "$1" in [a-z0-9]*/[A-Za-z0-9]*) ok=yes ;; esac
	case "$1" in *[!A-Za-z0-9_.+/-]*|*/*/*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'port $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template port: invalid origin $1 (category/name, e.g. editors/vscode)")"
	fi
}

#@help ___template_port_drop2
# @command template port drop <template> <origin>
# @summary Remove a port from the template's own list: the template exists, the origin is listed there; then 'template line remove'
# @group   template
# @example vm-bake template port drop freebsd-x editors/vscode
# @see     template port add
#@end
___template_port_drop2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") port $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") port $(sq "$2")"
}

#@help ___template_port_mask2
# @command template port mask <template> <origin>
# @summary Hide an inherited port in this template and below: the template exists, the origin is valid; then 'template line mask'
# @group   template
# @example vm-bake template port mask freebsd-x editors/vscode
# @see     template port drop
#@end
___template_port_mask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template port valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") port $(sq "$2")"
}

#@help ___template_port_show1
# @command template port show <template>
# @summary The ports resolved over the chain, each with its origin template: the template exists; then 'template chain table'
# @group   template
# @example vm-bake template port show freebsd-x
# @see     template show
#@end
___template_port_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") port"
}

#@help ___template_pkgfile_add2
# @command template pkgfile add <template> <file>
# @summary Add a package file to install from VM_BAKE_PKG_DIR (a .pkg of the same ABI, kept there by you, e.g. from another host's package cache): the template exists, the name is a file name ending in .pkg; then 'template line append' -- the bake stages it into the image and installs it with 'pkg add', dependencies from the repositories
# @group   template
# @example vm-bake template pkgfile add freebsd-x vscode-1.130.0.pkg
# @see     template pkgfile drop
# @see     template pkgfile show
# @see     template package add
#@end
___template_pkgfile_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template pkgfile valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") pkgfile $(sq "$2")"
}

#@help __template_pkgfile_valid1
# @command template pkgfile valid <file>
# @summary The name is a package file name: no slash, [A-Za-z0-9_.+~$-], ending in .pkg: a comment line, else an error line
# @group   template
# @internal
# @see     template pkgfile add
#@end
__template_pkgfile_valid1() {
	local ok=no
	case "$1" in *.pkg) ok=yes ;; esac
	case "$1" in .pkg|*/*|*[!A-Za-z0-9_.+~\$-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "pkgfile $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template pkgfile: invalid file name $1 (a .pkg file name without a path)")"
	fi
}

#@help ___template_pkgfile_drop2
# @command template pkgfile drop <template> <file>
# @summary Remove a package file from the template's own list: the template exists, the file is listed there; then 'template line remove'
# @group   template
# @example vm-bake template pkgfile drop freebsd-x vscode-1.130.0.pkg
# @see     template pkgfile add
#@end
___template_pkgfile_drop2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") pkgfile $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") pkgfile $(sq "$2")"
}

#@help ___template_pkgfile_mask2
# @command template pkgfile mask <template> <file>
# @summary Hide an inherited package file in this template and below: the template exists, the name is valid; then 'template line mask'
# @group   template
# @example vm-bake template pkgfile mask freebsd-x vscode-1.130.0.pkg
# @see     template pkgfile drop
#@end
___template_pkgfile_mask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template pkgfile valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") pkgfile $(sq "$2")"
}

#@help ___template_pkgfile_show1
# @command template pkgfile show <template>
# @summary The package files resolved over the chain, each with its origin template: the template exists; then 'template chain table'
# @group   template
# @example vm-bake template pkgfile show freebsd-x
# @see     template show
#@end
___template_pkgfile_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") pkgfile"
}

#@help ___template_tag_add3
# @command template tag add <template> <key> <text>
# @summary Add a tag to the template's own list, a key and a text, inherited like every list (purpose, task, owner, can ... -- the keys are yours): the template exists, the key is a word; then 'template line append'. 'template find' and 'guest find' search them
# @group   template
# @example vm-bake template tag add freebsd-dev purpose 'development on FreeBSD with Claude Code'
# @example vm-bake template tag add freebsd-x can intellij
# @see     template tag drop
# @see     template tag show
# @see     template find
#@end
___template_tag_add3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") tag $(sq "$2 $3")"
}

#@help ___template_tag_drop3
# @command template tag drop <template> <key> <text>
# @summary Remove a tag from the template's own list: the template exists, the line is listed there; then 'template line remove'
# @group   template
# @example vm-bake template tag drop freebsd-x can intellij
# @see     template tag add
#@end
___template_tag_drop3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") tag $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") tag $(sq "$2 $3")"
}

#@help ___template_tag_mask3
# @command template tag mask <template> <key> <text>
# @summary Hide an inherited tag in this template and below: the template exists, the key is a word; then 'template line mask'
# @group   template
# @example vm-bake template tag mask freebsd-x can emacs
# @see     template tag drop
#@end
___template_tag_mask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") tag $(sq "$2 $3")"
}

#@help ___template_tag_show1
# @command template tag show <template>
# @summary The tags resolved over the chain, each with its origin template: the template exists; then 'template chain table'
# @group   template
# @example vm-bake template tag show freebsd-x
# @see     template show
#@end
___template_tag_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") tag"
}

#@help _template_find1
# @internal arity-1 sibling of 'template find' (template find <key> -- the key alone): every template whose tags hold the key, whatever the text -- 'template find <key> .'
#@end
_template_find1() {
	_template_find2 "$1" .
}

#@help _template_find2
# @command template find <key> <pattern>
# @summary Display terminal: every template whose resolved tags (read over its chain) hold the key with a text matching the pattern -- an extended regular expression, case-insensitive, searched in the text alone and not in the names around it ('.' for any text, '^15\.1$' for exactly that value): one line per hit, template, origin of the tag, the tag
# @group   template
# @example vm-bake template find can intellij
# @example vm-bake template find purpose .
# @see     template tag add
# @see     guest find
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_template_find2() {
	local d="" t="" cur="" chain="" p="" n=0 hit="" found=0
	printf '# templates with tag %s ~ %s (template  origin  tag)\n' "$1" "$2"
	for d in "$VM_BAKE_BASE"/template/*/; do
		t=$(basename "$d"); cur=$t; chain=""; n=0
		while test "$cur" != empty && test "$n" -lt 32; do
			chain="$cur${chain:+ $chain}"
			IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
			cur=$p; n=$((n + 1))
		done
		hit=$(awk -v base="$VM_BAKE_BASE" -v family=tag -v chain="empty${chain:+ $chain}" -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | VM_BAKE_PATTERN=$2 awk -v k="$1" 'BEGIN { p = tolower(ENVIRON["VM_BAKE_PATTERN"]) } $3 == k { t = $0; sub(/^#   [^ ]+ +[^ ]+ +/, "", t); if (tolower(t) ~ p) print }' || true)
		test -z "$hit" || { printf '%s\n' "$hit" | sed "s/^#   /#   $(printf '%-16s' "$t") /"; found=$((found + 1)); }
	done
	test "$found" -gt 0 || printf '%s\n' "#   (none)"
}

#@help ___template_env_add3
# @command template env add <template> <variable> <value>
# @summary Add an environment variable for the sessions of every guest of this template (XCURSOR_THEME, LANG, ...): the template exists, the variable is a name, the value a plain word; then 'template line append' -- the bake writes them into /etc/profile.d/vm-bake.sh of the image, and 'session create x' hands them to the program it runs
# @group   template
# @example vm-bake template env add freebsd-x XCURSOR_THEME redglass
# @see     template env drop
# @see     template env show
# @see     session create x
#@end
___template_env_add3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template rc valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") env $(sq "$2=$3")"
}

#@help ___template_env_drop3
# @command template env drop <template> <variable> <value>
# @summary Remove an environment variable from the template's own list: the template exists, the line is listed there; then 'template line remove'
# @group   template
# @example vm-bake template env drop freebsd-x XCURSOR_THEME redglass
# @see     template env add
#@end
___template_env_drop3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") env $(sq "$2=$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") env $(sq "$2=$3")"
}

#@help ___template_env_mask3
# @command template env mask <template> <variable> <value>
# @summary Hide an inherited environment variable in this template and below: the template exists, the variable is a name; then 'template line mask'
# @group   template
# @example vm-bake template env mask freebsd-x XCURSOR_THEME redglass
# @see     template env drop
#@end
___template_env_mask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template rc valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") env $(sq "$2=$3")"
}

#@help ___template_env_show1
# @command template env show <template>
# @summary The environment variables resolved over the chain, each with its origin template: the template exists; then 'template chain table'
# @group   template
# @example vm-bake template env show freebsd-x
# @see     template show
#@end
___template_env_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") env"
}

#@help __template_home_add2
# @command template home add <template> <path> [<mode>]
# @summary Add a path of the invoking user's home (its path from the user name, the batch environment carries no HOME; relative, e.g. .themes/NsCDE or .config/gtk-3.0) to the view every guest of this template gets of that home, read-only (ro) unless the mode says rw: rewrite to 'template home add <template> <path> ro'
# @group   template
# @param   mode  ro (the default) or rw: how the guest sees the path
# @example vm-bake template home add freebsd-x .themes/NsCDE
# @example vm-bake template home add freebsd-x .config/gtk-3.0 rw
# @see     template home drop
# @see     template home show
# @see     guest make
#@end
__template_home_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home add $(sq "$1") $(sq "$2") ro"
}

#@help ___template_home_add3
# @internal arity-3 sibling of 'template home add' (template home add <template> <path> <mode>): the template exists, the path is relative and plain, the mode is ro or rw; then 'template line append' of '<path> <mode>'
#@end
___template_home_add3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home mode valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") home $(sq "$2 $3")"
}

#@help __template_home_mode_valid1
# @command template home mode valid <mode>
# @summary The mode is ro or rw: a comment line, else an error line
# @group   template
# @internal
# @see     template home add
#@end
__template_home_mode_valid1() {
	case "$1" in
	ro|rw) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "home mode $1 valid")" ;;
	*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template home: the mode is ro or rw, not $1")" ;;
	esac
}

#@help __template_home_valid1
# @command template home valid <path>
# @summary The path is relative to a home, plain ([A-Za-z0-9_.+/-]), without .. and not ending in a slash: a comment line, else an error line
# @group   template
# @internal
# @see     template home add
#@end
__template_home_valid1() {
	local ok=yes
	case "$1" in ""|/*|*/|..|../*|*/..|*/../*|*[!A-Za-z0-9_.+/-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "home path $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template home: invalid path $1 (relative to the home, plain, no ..)")"
	fi
}

#@help __template_home_drop2
# @command template home drop <template> <path> [<mode>]
# @summary Remove a home path from the template's own list, the line being '<path> <mode>' with ro as the default: rewrite to 'template home drop <template> <path> ro'
# @group   template
# @param   mode  ro (the default) or rw, as the line was added
# @example vm-bake template home drop freebsd-x .themes/NsCDE
# @see     template home add
#@end
__template_home_drop2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home drop $(sq "$1") $(sq "$2") ro"
}

#@help ___template_home_drop3
# @internal arity-3 sibling of 'template home drop' (template home drop <template> <path> <mode>): the template exists, the line '<path> <mode>' is listed there; then 'template line remove'
#@end
___template_home_drop3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") home $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") home $(sq "$2 $3")"
}

#@help __template_home_mask2
# @command template home mask <template> <path> [<mode>]
# @summary Hide an inherited home line '<path> <mode>' in this template and below, ro as the default: rewrite to 'template home mask <template> <path> ro'
# @group   template
# @param   mode  ro (the default) or rw, as the inherited line reads
# @example vm-bake template home mask freebsd-x .themes/NsCDE
# @see     template home drop
#@end
__template_home_mask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home mask $(sq "$1") $(sq "$2") ro"
}

#@help ___template_home_mask3
# @internal arity-3 sibling of 'template home mask' (template home mask <template> <path> <mode>): the template exists, the path and the mode are valid; then 'template line mask' of '<path> <mode>'
#@end
___template_home_mask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home mode valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") home $(sq "$2 $3")"
}

#@help ___template_home_show1
# @command template home show <template>
# @summary The home paths resolved over the chain, each with its origin template: the template exists; then 'template chain table'
# @group   template
# @example vm-bake template home show freebsd-x
# @see     template show
#@end
___template_home_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") home"
}

#@help ___template_home_copy_idem3
# @command template home copy idem <template> <dowry> <destination>
# @summary Hand a dowry to the home of every guest of this template, where it is missing: the template exists, the dowry is kept in the database, the destination is a plain path relative to the home; then 'template line append' of 'copy idem <dowry> <destination>'. 'guest start' places it before it hangs the overlays in; what the guest makes of it afterwards stays its own
# @group   template
# @example vm-bake template home copy idem freebsd-dev claude-state .claude
# @see     template home copy overwrite
# @see     template home unlink idem
# @see     dowry add
#@end
___template_home_copy_idem3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry check $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") home $(sq "copy idem $2 $3")"
}

#@help ___template_home_copy_overwrite3
# @command template home copy overwrite <template> <dowry> <destination>
# @summary Hand a dowry to the home of every guest of this template at every start, replacing what is there: the template exists, the dowry is kept, the destination is plain; then 'template line append' of 'copy overwrite <dowry> <destination>'. What the guest wrote at that path is gone with the next 'guest start' -- for anything the guest keeps working on, 'idem' is the word
# @group   template
# @example vm-bake template home copy overwrite freebsd-x nscde-theme .themes/NsCDE
# @see     template home copy idem
# @see     template home unlink overwrite
#@end
___template_home_copy_overwrite3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" dowry check $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") home $(sq "copy overwrite $2 $3")"
}

#@help ___template_home_unlink_idem3
# @command template home unlink idem <template> <dowry> <destination>
# @summary Take the rule back from the template's own list: the template exists, the line 'copy idem <dowry> <destination>' is listed there; then 'template line remove'. What already lies in a guest's view stays -- it belongs to the guest
# @group   template
# @example vm-bake template home unlink idem freebsd-dev claude-state .claude
# @see     template home copy idem
# @see     template home mask idem
#@end
___template_home_unlink_idem3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") home $(sq "copy idem $2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") home $(sq "copy idem $2 $3")"
}

#@help ___template_home_unlink_overwrite3
# @command template home unlink overwrite <template> <dowry> <destination>
# @summary Take the rule back from the template's own list: the template exists, the line 'copy overwrite <dowry> <destination>' is listed there; then 'template line remove'
# @group   template
# @see     template home copy overwrite
# @see     template home mask overwrite
#@end
___template_home_unlink_overwrite3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") home $(sq "copy overwrite $2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") home $(sq "copy overwrite $2 $3")"
}

#@help ___template_home_mask_idem3
# @command template home mask idem <template> <dowry> <destination>
# @summary Hide an inherited rule 'copy idem <dowry> <destination>' in this template and below: the template exists, the destination is plain; then 'template line mask'. The guests of this template get that dowry no longer -- the dowry itself stays in the database
# @group   template
# @example vm-bake template home mask idem freebsd-x claude-state .claude
# @see     template home copy idem
# @see     template home unmask idem
#@end
___template_home_mask_idem3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") home $(sq "copy idem $2 $3")"
}

#@help ___template_home_mask_overwrite3
# @command template home mask overwrite <template> <dowry> <destination>
# @summary Hide an inherited rule 'copy overwrite <dowry> <destination>' in this template and below: the template exists, the destination is plain; then 'template line mask'
# @group   template
# @see     template home copy overwrite
# @see     template home unmask overwrite
#@end
___template_home_mask_overwrite3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") home $(sq "copy overwrite $2 $3")"
}

#@help ___template_home_unmask_idem3
# @command template home unmask idem <template> <dowry> <destination>
# @summary Take such a mask back: the template exists, the line 'copy idem <dowry> <destination>' is masked here; then 'template line unmask' -- the inherited rule reaches this template and everything below it again
# @group   template
# @example vm-bake template home unmask idem freebsd-x claude-state .claude
# @see     template home mask idem
#@end
___template_home_unmask_idem3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") home $(sq "copy idem $2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") home $(sq "copy idem $2 $3")"
}

#@help ___template_home_unmask_overwrite3
# @command template home unmask overwrite <template> <dowry> <destination>
# @summary Take such a mask back: the template exists, the line 'copy overwrite <dowry> <destination>' is masked here; then 'template line unmask'
# @group   template
# @see     template home mask overwrite
#@end
___template_home_unmask_overwrite3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") home $(sq "copy overwrite $2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") home $(sq "copy overwrite $2 $3")"
}

#@help ___template_rc_add3
# @command template rc add <template> <variable> <value>
# @summary Add an rc.conf line '<variable>="<value>"' to the template's own list: the template exists, the variable is an rc.conf name, the value a plain word; then 'template line append'
# @group   template
# @example vm-bake template rc add freebsd-dev linux_enable YES
# @see     template rc drop
# @see     template rc show
#@end
___template_rc_add3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template rc valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") rc $(sq "$2=$3")"
}

#@help __template_rc_valid1
# @command template rc valid <variable>
# @summary The name is an rc.conf variable ([A-Za-z_][A-Za-z0-9_]*): a comment line, else an error line
# @group   template
# @internal
# @see     template rc add
#@end
__template_rc_valid1() {
	local ok=yes
	case "$1" in ""|[0-9]*|*[!A-Za-z0-9_]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'rc variable $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template rc: invalid variable name $1 ([A-Za-z_][A-Za-z0-9_]*)")"
	fi
}

#@help ___template_rc_drop3
# @command template rc drop <template> <variable> <value>
# @summary Remove the rc.conf line from the template's own list: the template exists, the line is listed there; then 'template line remove'
# @group   template
# @see     template rc add
#@end
___template_rc_drop3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") rc $(sq "$2=$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") rc $(sq "$2=$3")"
}

#@help ___template_rc_mask3
# @command template rc mask <template> <variable> <value>
# @summary Hide an inherited rc.conf line in this template and below: the template exists, the names are valid; then 'template line mask'
# @group   template
# @see     template rc drop
#@end
___template_rc_mask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template rc valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") rc $(sq "$2=$3")"
}

#@help ___template_rc_show1
# @command template rc show <template>
# @summary The rc.conf lines resolved over the chain, each with its origin: the template exists; then 'template chain table'
# @group   template
# @see     template show
#@end
___template_rc_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") rc"
}

#@help ___template_user_add3
# @command template user add <template> <name> <uid>|host
# @summary Add a user of the guest to the template's own list, with a numeric uid or 'host' (the uid the user has on the host, read at bake time): the template exists, name and uid are valid; then 'template line append'
# @group   template
# @example vm-bake template user add freebsd-dev brj host
# @see     template user drop
# @see     template user show
#@end
___template_user_add3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template user valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template uid valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") user $(sq "$2 $3")"
}

#@help __template_user_valid1
# @command template user valid <name>
# @summary The name is a login name ([a-z_][a-z0-9_-]*, at most 32 characters): a comment line, else an error line
# @group   template
# @internal
# @see     template user add
#@end
__template_user_valid1() {
	local ok=yes
	case "$1" in ""|[!a-z_]*|*[!a-z0-9_-]*) ok=no ;; esac
	test ${#1} -le 32 || ok=no
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'user name $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template user: invalid login name $1 ([a-z_][a-z0-9_-]*)")"
	fi
}

#@help __template_uid_valid1
# @command template uid valid <uid>|host
# @summary The uid is a number or the word host: a comment line, else an error line
# @group   template
# @internal
# @see     template user add
#@end
__template_uid_valid1() {
	local ok=yes
	case "$1" in host) ;; ""|*[!0-9]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'uid $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template user: uid is a number or host: $1")"
	fi
}

#@help ___template_user_drop3
# @command template user drop <template> <name> <uid>|host
# @summary Remove the user from the template's own list: the template exists, the entry is listed there; then 'template line remove'
# @group   template
# @see     template user add
#@end
___template_user_drop3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") user $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") user $(sq "$2 $3")"
}

#@help ___template_user_mask3
# @command template user mask <template> <name> <uid>|host
# @summary Hide an inherited user in this template and below: the template exists, name and uid are valid; then 'template line mask'
# @group   template
# @see     template user drop
#@end
___template_user_mask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template user valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template uid valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") user $(sq "$2 $3")"
}

#@help ___template_user_show1
# @command template user show <template>
# @summary The users resolved over the chain, each with its origin: the template exists; then 'template chain table'
# @group   template
# @see     template show
#@end
___template_user_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") user"
}

#@help ___template_service_add3
# @command template service add <template> <kind> <variant>
# @summary Add a host service the guest may use to the template's own list: the template exists, kind and variant are valid (display x|rdp|none, audio pulse|sndio|none, clipboard broker|none, files disk|none, net <switch>, token none); then 'template line append'
# @group   template
# @example vm-bake template service add freebsd-dev display x
# @example vm-bake template service add freebsd-dev net dev
# @see     template service drop
# @see     template service show
# @see     template forbid add
#@end
___template_service_add3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template service valid $(sq "$2") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") service $(sq "$2 $3")"
}

#@help __template_service_valid2
# @command template service valid <kind> <variant>
# @summary The kind is one of display, audio, clipboard, files, net, token and the variant a plain word: a comment line, else an error line
# @group   template
# @internal
# @see     template service add
#@end
__template_service_valid2() {
	local ok=yes
	case "$1" in display|audio|clipboard|files|net|token) ;; *) ok=no ;; esac
	case "$2" in ""|*[!A-Za-z0-9_.-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'service $1 $2 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template service: invalid service $1 $2 (display|audio|clipboard|files|net|token <word>)")"
	fi
}

#@help ___template_service_drop3
# @command template service drop <template> <kind> <variant>
# @summary Remove the service from the template's own list: the template exists, the entry is listed there; then 'template line remove'
# @group   template
# @see     template service add
#@end
___template_service_drop3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") service $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") service $(sq "$2 $3")"
}

#@help ___template_service_mask3
# @command template service mask <template> <kind> <variant>
# @summary Hide an inherited service in this template and below: the template exists, kind and variant are valid; then 'template line mask'
# @group   template
# @see     template service drop
#@end
___template_service_mask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template service valid $(sq "$2") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") service $(sq "$2 $3")"
}

#@help ___template_service_show1
# @command template service show <template>
# @summary The services resolved over the chain, each with its origin: the template exists; then 'template chain table'
# @group   template
# @see     template show
#@end
___template_service_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") service"
}

#@help ___template_forbid_add2
# @internal arity-2 sibling of 'template forbid add' (a kind without argument: usb): the template exists, the kind is valid; then 'template line append'
#@end
___template_forbid_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template forbid valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") forbid $(sq "$2")"
}

#@help ___template_forbid_add3
# @command template forbid add <template> <kind> [<argument>]
# @summary Add what the guest must not reach to the template's own list -- the list the witness module proves: usb (no device passthrough), net <cidr> (the network), switch <name> (the vm-bhyve switch): the template exists, kind and argument are valid; then 'template line append'
# @group   template
# @example vm-bake template forbid add freebsd-dev usb
# @example vm-bake template forbid add freebsd-dev net 192.168.1.0/24
# @see     template forbid drop
# @see     template forbid mask
# @see     template forbid show
#@end
___template_forbid_add3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template forbid valid $(sq "$2") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") forbid $(sq "$2 $3")"
}

#@help __template_forbid_valid1
# @internal arity-1 sibling of 'template forbid valid': the kind without argument is usb: a comment line, else an error line
#@end
__template_forbid_valid1() {
	if test "$1" = usb; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'forbid $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template forbid: $1 takes an argument or is unknown (usb | net <cidr> | switch <name>)")"
	fi
}

#@help __template_forbid_valid2
# @command template forbid valid <kind> [<argument>]
# @summary The kind with argument is net (a CIDR) or switch (a name), the argument a plain word: a comment line, else an error line
# @group   template
# @internal
# @see     template forbid add
#@end
__template_forbid_valid2() {
	local ok=yes
	case "$1" in net|switch) ;; *) ok=no ;; esac
	case "$2" in ""|*[!A-Za-z0-9_.:/-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'forbid $1 $2 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template forbid: invalid $1 $2 (net <cidr> | switch <name>)")"
	fi
}

#@help ___template_forbid_drop2
# @internal arity-2 sibling of 'template forbid drop' (a kind without argument): the template exists, the entry is listed there; then 'template line remove'
#@end
___template_forbid_drop2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") forbid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") forbid $(sq "$2")"
}

#@help ___template_forbid_drop3
# @command template forbid drop <template> <kind> [<argument>]
# @summary Remove the entry from the template's own list: the template exists, the entry is listed there; then 'template line remove'
# @group   template
# @see     template forbid add
#@end
___template_forbid_drop3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") forbid $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") forbid $(sq "$2 $3")"
}

#@help ___template_forbid_mask2
# @internal arity-2 sibling of 'template forbid mask' (a kind without argument): the template exists, the kind is valid; then 'template line mask'
#@end
___template_forbid_mask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template forbid valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") forbid $(sq "$2")"
}

#@help ___template_forbid_mask3
# @command template forbid mask <template> <kind> [<argument>]
# @summary Hide an inherited entry in this template and below: the template exists, kind and argument are valid; then 'template line mask'
# @group   template
# @see     template forbid drop
#@end
___template_forbid_mask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template forbid valid $(sq "$2") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") forbid $(sq "$2 $3")"
}

#@help ___template_forbid_show1
# @command template forbid show <template>
# @summary The forbidden list resolved over the chain, each with its origin: the template exists; then 'template chain table'
# @group   template
# @see     template show
#@end
___template_forbid_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") forbid"
}

#@help ___template_data_add4
# @command template data add <template> <name> <size> <class>
# @summary Add a data disk of the guest (a zvol outside the image, surviving every new image) to the template's own list, with its backup class (the value of enk-ode:backup): the template exists, name, size and class are valid; then 'template line append'
# @group   template
# @example vm-bake template data add freebsd-dev home 64G proton
# @see     template data drop
# @see     template data show
#@end
___template_data_add4() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template size valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$4")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") data $(sq "$2 $3 $4")"
}

#@help ___template_data_drop4
# @command template data drop <template> <name> <size> <class>
# @summary Remove the data disk from the template's own list: the template exists, the entry is listed there; then 'template line remove'
# @group   template
# @see     template data add
#@end
___template_data_drop4() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") data $(sq "$2 $3 $4")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") data $(sq "$2 $3 $4")"
}

#@help ___template_data_mask4
# @command template data mask <template> <name> <size> <class>
# @summary Hide an inherited data disk in this template and below: the template exists, the entry is valid; then 'template line mask'
# @group   template
# @see     template data drop
#@end
___template_data_mask4() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template size valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$4")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") data $(sq "$2 $3 $4")"
}

#@help ___template_data_show1
# @command template data show <template>
# @summary The data disks resolved over the chain, each with its origin: the template exists; then 'template chain table'
# @group   template
# @see     template show
#@end
___template_data_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") data"
}

#@help ___template_session_add2
# @command template session add <template> <protocol>
# @summary Add a session protocol the guest offers (rdp, ssh, x) to the template's own list: the template exists, the protocol is valid; then 'template line append'
# @group   template
# @example vm-bake template session add freebsd-dev ssh
# @see     template session drop
# @see     template session show
#@end
___template_session_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template protocol valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line append $(sq "$1") session $(sq "$2")"
}

#@help __template_protocol_valid1
# @command template protocol valid <protocol>
# @summary The protocol is rdp, ssh or x: a comment line, else an error line
# @group   template
# @internal
# @see     template session add
#@end
__template_protocol_valid1() {
	case "$1" in
		rdp|ssh|x) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'protocol $1 valid'" ;;
		*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template session: unknown protocol $1 (rdp | ssh | x)")" ;;
	esac
}

#@help ___template_session_drop2
# @command template session drop <template> <protocol>
# @summary Remove the protocol from the template's own list: the template exists, the entry is listed there; then 'template line remove'
# @group   template
# @see     template session add
#@end
___template_session_drop2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line listed $(sq "$1") session $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line remove $(sq "$1") session $(sq "$2")"
}

#@help ___template_session_mask2
# @command template session mask <template> <protocol>
# @summary Hide an inherited protocol in this template and below: the template exists, the protocol is valid; then 'template line mask'
# @group   template
# @see     template session drop
#@end
___template_session_mask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template protocol valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line mask $(sq "$1") session $(sq "$2")"
}

#@help ___template_session_show1
# @command template session show <template>
# @summary The protocols resolved over the chain, each with its origin: the template exists; then 'template chain table'
# @group   template
# @see     template show
#@end
___template_session_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template chain table $(sq "$1") session"
}

#@help _template_line_append3
# @command template line append <template> <family> <line>
# @summary Act terminal: append the line to the template's own list <family> unless listed (0600) and say so
# @group   template
# @internal
# @see     template package add
#@end
_template_line_append3() {
	printf '%s\n' "grep -qxF $(sq "$3") '$VM_BAKE_BASE/template/$1/$2' 2>/dev/null || printf '%s\\n' $(sq "$3") >> '$VM_BAKE_BASE/template/$1/$2'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$VM_BAKE_BASE/template/$1/$2'"
	printf '%s\n' "printf '# template %s: %s + %s\\n' '$1' '$2' $(sq "$3") >&2"
}

#@help __template_line_listed3
# @command template line listed <template> <family> <line>
# @summary The line is in the template's OWN list: a comment line, else an error line (an inherited line is masked, not dropped)
# @group   template
# @internal
# @see     template package drop
#@end
__template_line_listed3() {
	if grep -qxF "$3" "$VM_BAKE_BASE/template/$1/$2" 2>/dev/null; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "$2 entry $3 listed in $1")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template $1: no own $2 entry $3 (template $2 show $1; an inherited entry: template $2 mask)")"
	fi
}

#@help _template_line_remove3
# @command template line remove <template> <family> <line>
# @summary Act terminal: remove the line from the template's own list and say so
# @group   template
# @internal
# @see     template package drop
#@end
_template_line_remove3() {
	local f="$VM_BAKE_BASE/template/$1/$2"
	printf '%s\n' "{ grep -vxF $(sq "$3") '$f' > '$f.new' || true; } && mv -f '$f.new' '$f'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$f'"
	printf '%s\n' "printf '# template %s: %s - %s\\n' '$1' '$2' $(sq "$3") >&2"
}

#@help ___template_package_unmask2
# @command template package unmask <template> <package>
# @summary Take a mask back: the template exists, the name is a package name, the line is masked here; then 'template line unmask' -- what the chain inherits is visible again
# @group   template
# @example vm-bake template package unmask freebsd-dev emacs
# @see     template package mask
#@end
___template_package_unmask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template package valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") package $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") package $(sq "$2")"
}

#@help ___template_port_unmask2
# @command template port unmask <template> <origin>
# @summary Take a mask back: the template exists, the origin is valid, the line is masked here; then 'template line unmask'
# @group   template
# @see     template port mask
#@end
___template_port_unmask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template port valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") port $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") port $(sq "$2")"
}

#@help ___template_pkgfile_unmask2
# @command template pkgfile unmask <template> <file>
# @summary Take a mask back: the template exists, the name is valid, the line is masked here; then 'template line unmask'
# @group   template
# @see     template pkgfile mask
#@end
___template_pkgfile_unmask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template pkgfile valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") pkgfile $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") pkgfile $(sq "$2")"
}

#@help ___template_tag_unmask3
# @command template tag unmask <template> <key> <text>
# @summary Take a mask back: the template exists, the key is a word, the line is masked here; then 'template line unmask'
# @group   template
# @see     template tag mask
#@end
___template_tag_unmask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") tag $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") tag $(sq "$2 $3")"
}

#@help ___template_env_unmask3
# @command template env unmask <template> <variable> <value>
# @summary Take a mask back: the template exists, the name is a variable name, the line is masked here; then 'template line unmask'
# @group   template
# @see     template env mask
#@end
___template_env_unmask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template rc valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") env $(sq "$2=$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") env $(sq "$2=$3")"
}

#@help ___template_rc_unmask3
# @command template rc unmask <template> <variable> <value>
# @summary Take a mask back: the template exists, the name is a variable name and the value a word, the line is masked here; then 'template line unmask'
# @group   template
# @see     template rc mask
#@end
___template_rc_unmask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template rc valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") rc $(sq "$2=$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") rc $(sq "$2=$3")"
}

#@help ___template_user_unmask3
# @command template user unmask <template> <name> <uid>|host
# @summary Take a mask back: the template exists, name and uid are valid, the line is masked here; then 'template line unmask'
# @group   template
# @see     template user mask
#@end
___template_user_unmask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template user valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template uid valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") user $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") user $(sq "$2 $3")"
}

#@help __template_home_unmask2
# @command template home unmask <template> <path> [<mode>]
# @summary Take a mask back, the line being '<path> <mode>' with ro as the default: rewrite to 'template home unmask <template> <path> ro'
# @group   template
# @param   mode  ro (the default) or rw, as the masked line reads
# @example vm-bake template home unmask freebsd-x .themes/NsCDE
# @see     template home mask
#@end
__template_home_unmask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home unmask $(sq "$1") $(sq "$2") ro"
}

#@help ___template_home_unmask3
# @internal arity-3 sibling of 'template home unmask' (template home unmask <template> <path> <mode>): the template exists, the path and the mode are valid, the line '<path> <mode>' is masked here; then 'template line unmask'
#@end
___template_home_unmask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template home mode valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") home $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") home $(sq "$2 $3")"
}

#@help ___template_service_unmask3
# @command template service unmask <template> <kind> <variant>
# @summary Take a mask back: the template exists, kind and variant are valid, the line is masked here; then 'template line unmask'
# @group   template
# @example vm-bake template service unmask freebsd-x files view
# @see     template service mask
#@end
___template_service_unmask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template service valid $(sq "$2") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") service $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") service $(sq "$2 $3")"
}

#@help ___template_forbid_unmask2
# @internal arity-2 sibling of 'template forbid unmask' (a kind without argument): the template exists, the kind is valid, the line is masked here; then 'template line unmask'
#@end
___template_forbid_unmask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template forbid valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") forbid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") forbid $(sq "$2")"
}

#@help ___template_forbid_unmask3
# @command template forbid unmask <template> <kind> [<argument>]
# @summary Take a mask back: the template exists, kind and argument are valid, the line is masked here; then 'template line unmask'
# @group   template
# @see     template forbid mask
#@end
___template_forbid_unmask3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template forbid valid $(sq "$2") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") forbid $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") forbid $(sq "$2 $3")"
}

#@help ___template_data_unmask4
# @command template data unmask <template> <name> <size> <class>
# @summary Take a mask back: the template exists, the entry is valid, the line is masked here; then 'template line unmask'
# @group   template
# @see     template data mask
#@end
___template_data_unmask4() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template size valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$4")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") data $(sq "$2 $3 $4")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") data $(sq "$2 $3 $4")"
}

#@help ___template_session_unmask2
# @command template session unmask <template> <protocol>
# @summary Take a mask back: the template exists, the protocol is valid, the line is masked here; then 'template line unmask'
# @group   template
# @see     template session mask
#@end
___template_session_unmask2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template protocol valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line masked $(sq "$1") session $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template line unmask $(sq "$1") session $(sq "$2")"
}

#@help __template_line_masked3
# @command template line masked <template> <family> <line>
# @summary The line is masked in this template's own mask list (<family>.mask): a comment line, else an error line -- the guard of every unmask
# @group   template
# @internal
# @see     template line unmask
#@end
__template_line_masked3() {
	if grep -qxF "$3" "$VM_BAKE_BASE/template/$1/$2.mask" 2>/dev/null; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "template $1: $2 mask $3 is there")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template $1: $2 does not mask $3 here (template $2 show $1 names what the chain gives, template dump record $1 the masks)")"
	fi
}

#@help _template_line_unmask3
# @command template line unmask <template> <family> <line>
# @summary Act terminal: the line removed from the template's own mask list (<family>.mask, 0600) -- the counterpart of 'template line mask'; what the chain inherits reaches this template and everything below it again
# @group   template
# @internal
# @see     template line mask
# @see     template line masked
#@end
_template_line_unmask3() {
	local f="$VM_BAKE_BASE/template/$1/$2.mask"
	printf '%s\n' "{ grep -vxF $(sq "$3") '$f' > '$f.new' || true; } && mv -f '$f.new' '$f'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$f'"
	printf '%s\n' "printf '# template %s: %s unmask %s\\n' '$1' '$2' $(sq "$3") >&2"
}

#@help _template_line_mask3
# @command template line mask <template> <family> <line>
# @summary Act terminal: append the line to the template's mask of <family> unless listed (0600) and say so -- 'template show' hides what ancestors contributed under that line
# @group   template
# @internal
# @see     template package mask
#@end
_template_line_mask3() {
	local f="$VM_BAKE_BASE/template/$1/$2.mask"
	printf '%s\n' "grep -qxF $(sq "$3") '$f' 2>/dev/null || printf '%s\\n' $(sq "$3") >> '$f'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$f'"
	printf '%s\n' "printf '# template %s: %s mask %s\\n' '$1' '$2' $(sq "$3") >&2"
}

#@help __template_arch_valid1
# @command template arch valid <arch>
# @summary The architecture is amd64 or arm64: a comment line, else an error line
# @group   template
# @internal
# @see     template base release
#@end
__template_arch_valid1() {
	case "$1" in
		amd64|arm64) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'arch $1 valid'" ;;
		*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template base: unknown architecture $1 (amd64 | arm64)")" ;;
	esac
}

#@help __template_version_valid1
# @command template version valid <version>
# @summary The version names a FreeBSD release the pkgbase repositories carry: <major>.<minor>-RELEASE, -RCn or -BETAn (a future release is allowed here; the bake says whether the repository exists): a comment line, else an error line
# @group   template
# @internal
# @see     template base release
#@end
__template_version_valid1() {
	local ok=no
	case "$1" in
		[0-9]*.[0-9]*-RELEASE|[0-9]*.[0-9]*-RC[0-9]|[0-9]*.[0-9]*-RC[0-9][0-9]|[0-9]*.[0-9]*-BETA[0-9]|[0-9]*.[0-9]*-BETA[0-9][0-9]) ok=yes ;;
	esac
	case "$1" in *[!0-9A-Z.-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'version $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template base release: invalid version $1 (<major>.<minor>-RELEASE | -RCn | -BETAn)")"
	fi
}

#@help __template_sha256_valid1
# @command template sha256 valid <sha256>
# @summary The digest is 64 hexadecimal digits: a comment line, else an error line
# @group   template
# @internal
# @see     template base image
#@end
__template_sha256_valid1() {
	local ok=yes
	case "$1" in *[!0-9a-f]*) ok=no ;; esac
	test ${#1} -eq 64 || ok=no
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'sha256 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template base: the digest is 64 lowercase hex digits: $1")"
	fi
}

#@help __template_url_valid1
# @command template url valid <url>
# @summary The url is http(s) without quotes or blanks: a comment line, else an error line
# @group   template
# @internal
# @see     template base image
#@end
__template_url_valid1() {
	local ok=yes
	case "$1" in http://?*|https://?*) ;; *) ok=no ;; esac
	case "$1" in *"'"*|*'"'*|*[[:space:]]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'url valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template base image: invalid url (http:// or https://, no quotes or blanks): $1")"
	fi
}

#@help __template_path_valid1
# @command template path valid <path>
# @summary The path is absolute without .., quotes or blanks: a comment line, else an error line
# @group   template
# @internal
# @see     template base iso
#@end
__template_path_valid1() {
	local ok=yes
	case "$1" in /*) ;; *) ok=no ;; esac
	case "$1" in *..*|*"'"*|*'"'*|*[[:space:]]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'path $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template base iso: invalid path (absolute, no .., no quotes or blanks): $1")"
	fi
}

#@help __template_count_valid1
# @command template count valid <cpu>
# @summary The count is a number from 1 up: a comment line, else an error line
# @group   template
# @internal
# @see     template resource
#@end
__template_count_valid1() {
	local ok=yes
	case "$1" in ""|0|*[!0-9]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'count $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template resource: the cpu count is a number from 1 up: $1")"
	fi
}

#@help __template_size_valid1
# @command template size valid <size>
# @summary The size is a number with an optional unit K, M, G or T (as vm-bhyve and zfs read it): a comment line, else an error line
# @group   template
# @internal
# @see     template resource
#@end
__template_size_valid1() {
	local ok=yes
	case "$1" in ""|0|0[KMGT]|*[!0-9KMGT]*|*[KMGT]?*|[KMGT]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'size $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template: a size is a number with an optional unit K, M, G or T: $1")"
	fi
}

#@help __template_word_valid1
# @command template word valid <value>
# @summary The value is one plain word ([A-Za-z0-9_.:/@+-]): a comment line, else an error line
# @group   template
# @internal
# @see     template rc add
#@end
__template_word_valid1() {
	local ok=yes
	case "$1" in ""|*[!A-Za-z0-9_.:/@+-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'word $1 valid'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template: not a plain word ([A-Za-z0-9_.:/@+-]): $1")"
	fi
}

#@help ___template_dump1
# @command template dump <template>
# @summary The template as replay lines (template add, the scalars, every list entry and mask): the template exists; then 'template dump record'
# @group   template
# @example vm-bake template dump freebsd-dev > freebsd-dev.vmb
# @see     template dump all
# @see     template restore
#@end
___template_dump1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template dump record $(sq "$1")"
}

#@help ___template_dump_all0
# @command template dump all
# @summary Every template as replay lines, parents before children (a replay recreates the chain in order)
# @group   template
# @example vm-bake template dump all > templates.vmb
# @see     template dump
#@end
___template_dump_all0() {
	local emitted="
empty
" l="" name="" p="" progress=yes left=1
	while test "$left" -gt 0 && test "$progress" = yes; do
		progress=no; left=0
		for l in "$VM_BAKE_BASE"/template/*; do
			test -L "$l" || continue
			name=${l##*/}
			case "$emitted" in *"
$name
"*) continue ;; esac
			IFS= read -r p 2>/dev/null < "$l/parent" || p=empty
			case "$emitted" in
			*"
$p
"*)
				printf "%s\n" "\"\$VM_BAKE_CONTEXT_SCRIPT\" template dump record $(sq "$name")"
				emitted="$emitted$name
"
				progress=yes ;;
			*)	left=$((left + 1)) ;;
			esac
		done
	done
	test "$left" -eq 0 || printf "%s\n" "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "template dump all: $left template(s) whose chain of parents does not end at empty")"
	test "$emitted" != "
empty
" || printf "%s\n" "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'no templates to dump'"
}

#@help ___template_dump_record1
# @command template dump record <template>
# @summary The replay lines of one template, a batch pinned to cat so it is shown rather than run: 'template add' with its parent, the scalars, every own list entry and mask
# @group   template
# @internal
# @see     template dump
#@end
___template_dump_record1() {
	local d="$VM_BAKE_BASE/template/$1" p=empty v="" rest="" f="" l="" a=""
	IFS= read -r p 2>/dev/null < "$d/parent" || p=empty
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template add '$1' '$p'"
	if test -f "$d/base"; then
		IFS= read -r v < "$d/base"
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template base ${v%% *} '$1' $(printf '%s\n' "${v#* }" | sed "s/[^ ]*/'&'/g")"
	fi
	for f in bake firmware; do
		test -f "$d/$f" || continue
		IFS= read -r v < "$d/$f"
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template $f $v '$1'"
	done
	if test -f "$d/resource"; then
		IFS= read -r v < "$d/resource"
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template resource '$1' $(printf '%s\n' "$v" | sed "s/[^ ]*/'&'/g")"
	fi
	for f in $TEMPLATE_FAMILIES; do
		test -f "$d/$f" && while IFS= read -r l; do
			test -n "$l" || continue
			case "$f" in
			rc|env) a="$(sq "${l%%=*}") $(sq "${l#*=}")" ;;
			tag) a="$(sq "${l%% *}") $(sq "${l#* }")" ;;
			*) a=$(printf '%s\n' "$l" | sed "s/[^ ]*/'&'/g") ;;
			esac
			printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template $f add '$1' $a"
		done < "$d/$f"
		test -f "$d/$f.mask" && while IFS= read -r l; do
			test -n "$l" || continue
			case "$f" in
			rc|env) a="$(sq "${l%%=*}") $(sq "${l#*=}")" ;;
			tag) a="$(sq "${l%% *}") $(sq "${l#* }")" ;;
			*) a=$(printf '%s\n' "$l" | sed "s/[^ ]*/'&'/g") ;;
			esac
			printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template $f mask '$1' $a"
		done < "$d/$f.mask"
	done
	return 0
}

#@help __template_restore1
# @command template restore <file>
# @summary Replay a dump of templates (the lines 'template dump' wrote): rewrite to 'batch <file>' -- idempotent, an existing template is never re-minted, an identical scalar is a note
# @group   template
# @example vm-bake template restore templates.vmb
# @see     template dump all
#@end
__template_restore1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" batch $(sq "$1")"
}
