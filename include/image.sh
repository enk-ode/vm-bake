#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# image.sh - the images of vm-bake: a template baked onto a sparse UFS disk
# under VM_BAKE_IMAGE_DIR/<image> (a ZFS dataset of its own), sealed by the
# snapshot @image. Two kinds of base: 'release' installs pkgbase with pkg -r,
# 'image' starts from a FreeBSD VM image (fetched, verified, grown). The
# content terminals (mount, keys, pkg, repo, loader, packages, rc, users,
# doas, sshd, report, unmount) emit the same shell wherever it runs: on the
# host under 'sudo sh', or in the builder guest under 'ssh ... doas sh' --
# VM_BAKE_BAKE_IN names the place, 'image builder use' sets the pins.

#@help
# @defgroup image  Images
# @order   60
#   An image is a baked disk: the decisions of a template applied to a
#   FreeBSD base, on a sparse disk (GPT, an EFI system partition labelled
#   <image>-efi and a UFS root labelled <image>-root) under
#   VM_BAKE_IMAGE_DIR/<image>, sealed by the ZFS snapshot @image and
#   readonly. The base is the template's: 'release' installs pkgbase with
#   'pkg -r' (that needs securelevel -1, so it runs in the builder guest),
#   'image' writes a FreeBSD VM image fetched from its url and verified
#   against its sha256 (the host does it; this is how the builder itself is
#   made). 'image make freebsd <template>' names the image
#   <template>-<yyyymmdd> and runs create, base, burn, close and seal in
#   turn; each is a command of its own. VM_BAKE_BAKE_IN says where base,
#   burn and close act: 'host' (the acts pinned to sudo sh) or 'builder'
#   (pinned to ssh into the builder guest, which mounts the image's disk
#   under the same path); 'image builder use' and 'image builder leave'
#   switch between them, visibly, as setintp lines. One bake at a time:
#   create takes a lock under .tmp, seal drops it.
#@end

#@help
# @defcompletion image      image
# @defcompletion abi        none
# @defcompletion osversion  none
#@end

#@help __image_make_freebsd1
# @internal arity-1 sibling of 'image make freebsd' (image make freebsd <image>  -- the full name img:<template>:<version>): rewrite to 'image make freebsd from <template> <version> <image>'
#@end
__image_make_freebsd1() {
	local t="${1#img:}"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make freebsd from $(sq "${t%%:*}") $(sq "${1##*:}") $(sq "$1")"
}

#@help __image_make_freebsd2
# @command image make freebsd <template> <version>
# @summary Bake a FreeBSD image from the template under the version: the image is img:<template>:<version>, handed to 'image make freebsd from' -- a version is yours to choose (v1, v2, v20261107); a name that is taken stops at 'image create', and the next version is the answer; two more spellings: the full name alone (image make freebsd img:<template>:<version>) and a name of its own (image make freebsd <template> <version> img:<name>:<version>)
# @group   image
# @param   version  the version field of the image name, a word of [A-Za-z0-9_.+-]
# @example vm-bake image make freebsd freebsd-dev v1
# @see     image make freebsd from
# @see     image list
#@end
__image_make_freebsd2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make freebsd from $(sq "$1") $(sq "$2") $(sq "img:$1:$2")"
}

#@help __image_make_freebsd3
# @internal arity-3 sibling of 'image make freebsd' (image make freebsd <template> <version> <image>  -- a name of its own): rewrite to 'image make freebsd from <template> <version> <image>'
#@end
__image_make_freebsd3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make freebsd from $(sq "$1") $(sq "$2") $(sq "$3")"
}

#@help ___image_make_freebsd_from3
# @command image make freebsd from <template> <version> <image>
# @summary The bake behind the three spellings of 'image make freebsd': the template exists, the image name is img:<name>:<version> and free; then 'image create', 'image base', 'image burn', 'image close' and 'image seal' in turn (each a command of its own; create decides by the template's base kind)
# @group   image
# @internal
# @see     image make freebsd
# @see     image create
#@end
___image_make_freebsd_from3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image make freebsd: template $1, version $2 -> image $3 (create, base, burn, close, seal)")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image create $(sq "$1") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image base $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image burn $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image close $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seal $(sq "$3")"
}

#@help __image_create2
# @command image create <template> <image>
# @summary Step 1, the disk: by the template's resolved base kind (read at generation time) rewrite to 'image create release' (an empty GPT disk for pkgbase) or 'image create image' (the FreeBSD VM image written and grown); a stage base or none is an error line
# @group   image
# @example vm-bake image create freebsd-dev freebsd-dev-20261101
# @see     image create release
# @see     image create image
# @see     image base
#@end
__image_create2() {
	local cur="$1" chain="" p="" n=0 a="" base=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	case "${base%% *}" in
		release|image) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image create ${base%% *} $(sq "$1") $(sq "$2")" ;;
		*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create: template $1 has no release or image base (${base:-none}; a stage base is not baked yet)")" ;;
	esac
}

#@help ___image_create_release2
# @command image create release <template> <image>
# @summary The disk for a pkgbase install: the template exists with a resource, the image name is free; then the bake lock, the record, the dataset, disk0.img sparse in the resource's disk size, attached as md, GPT with the system partition <image>-efi and the root <image>-root, formatted, detached again (the base step mounts it where it bakes)
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  where the image's dataset is created
#@end
___image_create_release2() {
	local cur="$1" chain="" p="" n=0 a="" size=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r size < "$VM_BAKE_BASE/template/$a/resource"; done
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check resource $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image lock take $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record write $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image dataset create $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk create $(sq "$2") $(sq "${size##* }")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk attach $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk partition $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk format $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk detach $(sq "$2")"
}

#@help ___image_create_image2
# @command image create image <template> <image>
# @summary The disk from a FreeBSD VM image: the template exists with a resource, the image name is free; then the bake lock, the record, the dataset, the VM image fetched into VM_BAKE_IMAGE_CACHE (once) and verified against the template's sha256, written into disk0.img, the disk grown to the resource's size (gpart recover, resize, growfs), its partitions relabelled <image>-efi and <image>-root, detached again
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  where the image's dataset is created
#@end
___image_create_image2() {
	local cur="$1" chain="" p="" n=0 a="" size="" base=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r size < "$VM_BAKE_BASE/template/$a/resource"; done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	set -- "$1" "$2" $base
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check resource $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image lock take $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record write $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image dataset create $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image fetch $(sq "${6:-}")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image verify $(sq "${6:-}") $(sq "${7:-}")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk write $(sq "$2") $(sq "${6:-}") $(sq "${size##* }")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk attach $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk grow $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk relabel $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk detach $(sq "$2")"
}

#@help __image_base1
# @command image base <image>
# @summary Step 2, the operating system: by VM_BAKE_BAKE_IN rewrite to 'image base host' (the disk attached and mounted on the host) or 'image base builder' (the builder guest started with the disk, mounted there); any other value is an error line
# @group   image
# @example vm-bake image base freebsd-dev-20261101
# @see     image base host
# @see     image base builder
# @see     image builder use
# @env     VM_BAKE_BAKE_IN  host | builder
#@end
__image_base1() {
	case "$VM_BAKE_BAKE_IN" in
		host|builder) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image base $VM_BAKE_BAKE_IN $(sq "$1")" ;;
		*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image base: VM_BAKE_BAKE_IN is '$VM_BAKE_BAKE_IN' (host | builder: image builder use, image builder leave)")" ;;
	esac
}

#@help ___image_base_host1
# @command image base host <image>
# @summary The base on the host: the image has a record; the disk attached as md and mounted by its labels, then 'image base content'
# @group   image
# @internal
# @see     image base
#@end
___image_base_host1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk attach $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk mount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check mounted $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image base content $(sq "$1")"
}

#@help ___image_base_builder1
# @command image base builder <image>
# @summary The base in the builder guest: the image has a record; the builder's configuration gets the image's disk as its second disk, the builder starts, answers ssh, mounts the disk by its labels under the image's path, then 'image base content' runs there (the content terminals are pinned to ssh)
# @group   image
# @internal
# @see     image base
# @see     image builder start
#@end
___image_base_builder1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image builder start $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk mount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image base content $(sq "$1")"
}

#@help __image_base_content1
# @command image base content <image>
# @summary By the base kind of the image's template (read at generation time) rewrite to 'image base content release' (keys, pkgbase, repositories, loader) or 'image base content image' (repositories, loader: the VM image already holds the base)
# @group   image
# @internal
# @see     image base
#@end
__image_base_content1() {
	local t="" cur="" chain="" p="" n=0 a="" base=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	case "${base%% *}" in
		release|image) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image base content ${base%% *} $(sq "$1")" ;;
		*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image base: image $1 has no release or image base (${base:-none})")" ;;
	esac
}

#@help __image_check_pkgbase_place0
# @command image check pkgbase place
# @summary pkgbase can be installed where the bake acts: either VM_BAKE_BAKE_IN is 'builder' (the builder guest runs at securelevel -1), or this host runs at securelevel -1 itself (read at generation time): a comment line, else an error line. FreeBSD-runtime carries files with schg, and pkg refuses those at any securelevel above -1, wherever the root is -- the bake would die in the middle of 'image pkg base' ('image builder use' is the way; 05./06.11. it cost a bake)
# @group   image
# @internal
# @see     image base content release
# @see     image builder use
# @env     VM_BAKE_BAKE_IN  host or builder: where the content terminals act
#@end
__image_check_pkgbase_place0() {
	local lvl=""
	lvl=$(sysctl -n kern.securelevel 2>/dev/null || printf -- -1)
	if test "$VM_BAKE_BAKE_IN" = builder || test "$lvl" -le -1; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "pkgbase can be installed in $VM_BAKE_BAKE_IN (securelevel $lvl)")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image base content release: pkgbase cannot be installed on this host, which runs at securelevel $lvl -- FreeBSD-runtime carries schg files and pkg refuses them above -1. Bake in the builder guest: vm-bake image builder use")"
	fi
}

#@help ___image_base_content_release1
# @command image base content release <image>
# @summary The pkgbase install: the signing keys into the image, 'pkg -r' with FreeBSD-set-minimal, the GENERIC kernel, FreeBSD-ssh and pkg (ABI and OSVERSION from the template's release), the host's repository configuration, the EFI loader into the system partition, loader.conf and fstab
# @group   image
# @internal
# @see     image base content
#@end
___image_base_content_release1() {
	local t="" cur="" chain="" p="" n=0 a="" base="" abi="" osv=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	abi=$(printf '%s\n' "$base" | awk '{ split($3, v, /[.-]/); printf "FreeBSD:%d:%s", v[1], $2 }')
	osv=$(printf '%s\n' "$base" | awk '{ split($3, v, /[.-]/); printf "%d", v[1] * 100000 + v[2] * 1000 }')
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pkgbase place"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image keys write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg base $(sq "$1") $(sq "$abi") $(sq "$osv")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image repo write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image boot write $(sq "$1")"
}

#@help ___image_base_content_image1
# @command image base content image <image>
# @summary The VM image already holds the base: the host's repository configuration into the image, the EFI loader into the system partition, loader.conf and fstab (the relabelled partitions)
# @group   image
# @internal
# @see     image base content
#@end
___image_base_content_image1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image repo write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image boot write $(sq "$1")"
}

#@help ___image_burn1
# @command image burn <image>
# @summary Step 3, the template: the image has a record, every user of the template resolves (a host uid exists, the key file VM_BAKE_HOST_KEY is readable); then the template's packages via 'pkg -r', its package files from VM_BAKE_PKG_DIR staged and added, its ports built and installed in the builder (an error line when ports are listed and VM_BAKE_BAKE_IN is host), its rc.conf lines, its env variables as profile.d, its users with the host key in authorized_keys, the view of the host's home when the template says 'service files view', root locked (pkgbase ships root without a password), doas for them when the template lists doas, and sshd on VM_BAKE_SSH_PORT with keys only and no root -- where VM_BAKE_BAKE_IN says (the pins)
# @group   image
# @example vm-bake image burn freebsd-dev-20261101
# @see     image base
# @see     image close
# @see     template port add
# @env     VM_BAKE_BAKE_IN  host or builder: ports build only in the builder
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
___image_burn1() {
	local t="" cur="" chain="" p="" n=0 a="" base="" abi="" osv="" ports="" pkgfiles=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	abi=$(printf '%s\n' "$base" | awk '{ split($3, v, /[.-]/); printf "FreeBSD:%d:%s", v[1], $2 }')
	osv=$(printf '%s\n' "$base" | awk '{ split($3, v, /[.-]/); printf "%d", v[1] * 100000 + v[2] * 1000 }')
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check users $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg install $(sq "$1") $(sq "$abi") $(sq "$osv")"
	pkgfiles=$(awk -v base="$VM_BAKE_BASE" -v family=pkgfile -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -z "$pkgfiles" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pkgfiles $(sq "$1")" "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkgfile stage $(sq "$1")" "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkgfile add $(sq "$1")"
	ports=$(awk -v base="$VM_BAKE_BASE" -v family=port -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -z "$ports" || test "$VM_BAKE_BAKE_IN" != builder || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image port build $(sq "$1")" "\"\$VM_BAKE_CONTEXT_SCRIPT\" image port install $(sq "$1")"
	test -z "$ports" || test "$VM_BAKE_BAKE_IN" = builder || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image burn: ports build in the builder only (image builder use): $(printf '%s' "$ports" | tr '\n' ' ')")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image rc write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image env write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image user make $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image view write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image root lock $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image doas write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image ssh write $(sq "$1")"
}

#@help __image_close1
# @command image close <image>
# @summary Step 4, the disk closed: by VM_BAKE_BAKE_IN rewrite to 'image close host' or 'image close builder'; any other value is an error line
# @group   image
# @example vm-bake image close freebsd-dev-20261101
# @see     image close host
# @see     image close builder
# @see     image seal
# @env     VM_BAKE_BAKE_IN  host | builder
#@end
__image_close1() {
	case "$VM_BAKE_BAKE_IN" in
		host|builder) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image close $VM_BAKE_BAKE_IN $(sq "$1")" ;;
		*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image close: VM_BAKE_BAKE_IN is '$VM_BAKE_BAKE_IN' (host | builder)")" ;;
	esac
}

#@help ___image_close_host1
# @command image close host <image>
# @summary The disk closed on the host: the image has a record and is mounted; the package report into the image, unmounted, the md detached, the sha256 of disk0.img written beside it and into the record
# @group   image
# @internal
# @see     image close
#@end
___image_close_host1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check mounted $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg report $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk unmount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk detach $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image digest write $(sq "$1")"
}

#@help ___image_close_builder1
# @command image close builder <image>
# @summary The disk closed in the builder: the image has a record; the package report into the image, unmounted there, the builder shut down, then the sha256 of disk0.img on the host
# @group   image
# @internal
# @see     image close
# @see     image builder stop
#@end
___image_close_builder1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg report $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk unmount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image builder stop"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image digest write $(sq "$1")"
}

#@help ___image_seal1
# @command image seal <image>
# @summary Step 5, the seal: the image has a record and a digest, the bake lock is this image's; then the snapshot @image, the dataset readonly, the lock dropped
# @group   image
# @example vm-bake image seal freebsd-dev-20261101
# @see     image close
# @see     image list
#@end
___image_seal1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check closed $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check lock $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image snapshot take $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image readonly set $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image lock drop"
}

#@help ___image_drop1
# @command image drop <image>
# @summary Remove an image: it has a record; unmounted and detached on the host if it still is, its dataset destroyed (a guest cloned from it makes zfs refuse), the record removed, the bake lock dropped when it is this image's
# @group   image
# @example vm-bake image drop freebsd-dev-20261101
# @see     image list
# @see     image make freebsd
#@end
___image_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk release $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image dataset destroy $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record remove $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image lock release $(sq "$1")"
}

#@help ___image_builder_use0
# @command image builder use
# @summary Bake in the builder guest from now on: VM_BAKE_BAKE_IN=builder, and the content terminals (disk mount, keys, pkg base, repo, boot, pkg install, rc, user, view, root lock, doas, ssh, pkg report, disk unmount) pinned to 'ssh -p VM_BAKE_SSH_PORT -i <key> VM_BAKE_BUILDER_USER@VM_BAKE_BUILDER_ADDRESS doas sh' -- one setintp line each, so the pins are seen
# @group   image
# @example vm-bake image builder use
# @see     image builder leave
# @see     image base
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the builder's sshd port
# @env     VM_BAKE_BUILDER  the builder guest's name (its known_hosts file lives under .tmp)
# @env     VM_BAKE_BUILDER_USER  the user ssh logs in as (doas without a password)
# @env     VM_BAKE_BUILDER_ADDRESS  the builder's address
#@end
___image_builder_use0() {
	local key="$VM_BAKE_HOST_KEY" f="" ssh=""
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	ssh="ssh -p $VM_BAKE_SSH_PORT -i ${key%.pub} -o UserKnownHostsFile=$VM_BAKE_BASE/.tmp/known_hosts.$VM_BAKE_BUILDER -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 $VM_BAKE_BUILDER_USER@$VM_BAKE_BUILDER_ADDRESS doas sh"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setenv VM_BAKE_BAKE_IN builder"
	for f in image_disk_mount image_keys_write image_pkg_base image_repo_write image_boot_write image_pkg_install image_pkgfile_add image_port_build image_port_install image_rc_write image_env_write image_user_make image_view_write image_root_lock image_doas_write image_ssh_write image_pkg_report image_disk_unmount; do
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setintp $f $(sq "$ssh")"
	done
}

#@help ___image_builder_leave0
# @command image builder leave
# @summary Bake on the host again: VM_BAKE_BAKE_IN=host, the content terminals' pins dropped (their profile defaults, sudo sh, apply) -- one unsetintp line each
# @group   image
# @example vm-bake image builder leave
# @see     image builder use
#@end
___image_builder_leave0() {
	local f=""
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setenv VM_BAKE_BAKE_IN host"
	for f in image_disk_mount image_keys_write image_pkg_base image_repo_write image_boot_write image_pkg_install image_pkgfile_add image_port_build image_port_install image_rc_write image_env_write image_user_make image_view_write image_root_lock image_doas_write image_ssh_write image_pkg_report image_disk_unmount; do
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" unsetintp $f"
	done
}

#@help ___image_builder_start1
# @command image builder start <image>
# @summary Start the builder guest with the image's disk as its second disk: the builder guest has a record (guest make) and is not running; its configuration written with the disk, 'vm start', then wait until it answers ssh
# @group   image
# @example vm-bake image builder start freebsd-dev-20261101
# @see     image builder stop
# @see     guest make
# @env     VM_BAKE_BUILDER  the builder guest's name
#@end
___image_builder_start1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$VM_BAKE_BUILDER")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check stopped $(sq "$VM_BAKE_BUILDER")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image builder conf write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest start $(sq "$VM_BAKE_BUILDER")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image builder wait"
}

#@help ___image_builder_stop0
# @command image builder stop
# @summary Shut the builder guest down over ssh (doas shutdown -p now) and wait until its bhyve process is gone
# @group   image
# @example vm-bake image builder stop
# @see     image builder start
#@end
___image_builder_stop0() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image builder shutdown"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image builder gone"
}

#@help __image_check_resource1
# @command image check resource <template>
# @summary The template's resolved resource is set (the disk size of disk0.img comes from it): a comment line, else an error line
# @group   image
# @internal
# @see     image create
#@end
__image_check_resource1() {
	local cur="$1" chain="" p="" n=0 a="" res=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r res < "$VM_BAKE_BASE/template/$a/resource"; done
	if test -n "$res"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image: resource of $1 is $res")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create: template $1 has no resource (template resource $1 <cpu> <memory> <disk>)")"
	fi
}

#@help __image_name_valid1
# @command image name valid <image>
# @summary The image name is img:<name>:<version> -- three fields, ':' the one separator, name and version words of [A-Za-z0-9_.+-] -- of at most 30 characters (the GPT labels <image>-efi and <image>-root must fit 36): a comment line, else an error line
# @group   image
# @internal
# @see     image create
#@end
__image_name_valid1() {
	local ok=yes n="" v=""
	n=${1#img:}; v=${n#*:}; n=${n%%:*}
	case "$1" in img:?*:?*) ;; *) ok=no ;; esac
	case "$n$v" in *[!A-Za-z0-9_.+-]*) ok=no ;; esac
	test ${#1} -le 30 || ok=no
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image name $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create: invalid image name $1 (img:<name>:<version>, name and version of [A-Za-z0-9_.+-], at most 30 characters)")"
	fi
}

#@help __image_check_absent1
# @command image check absent <image>
# @summary No record and no directory of that name yet: a comment line, else an error line (an image is baked once; a new bake gets a new name)
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  where the image's directory would be
#@end
__image_check_absent1() {
	if test ! -e "$VM_BAKE_BASE/image/$1" && test ! -e "$VM_BAKE_IMAGE_DIR/$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1 is free")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create: $1 exists (record image/$1 or $VM_BAKE_IMAGE_DIR/$1); a new bake takes a new name, image drop removes an old one")"
	fi
}

#@help __image_check_record1
# @command image check record <image>
# @summary The image has a record (image/<image>/template): a comment line, else an error line -- the first line of every step after create
# @group   image
# @internal
# @see     image base
#@end
__image_check_record1() {
	if test -f "$VM_BAKE_BASE/image/$1/template"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1 has a record")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "unknown image $1 (image create <template> $1, or image list)")"
	fi
}

#@help __image_check_mounted1
# @command image check mounted <image>
# @summary The image's root is mounted at VM_BAKE_IMAGE_DIR/<image>/mnt on this host (read from mount at generation time): a comment line, else an error line
# @group   image
# @internal
# @see     image base host
# @env     VM_BAKE_IMAGE_DIR  where the image's mount point is
#@end
__image_check_mounted1() {
	if mount -p 2>/dev/null | awk -v m="$VM_BAKE_IMAGE_DIR/$1/mnt" '$2 == m { f = 1 } END { exit !f }'; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1 is mounted at $VM_BAKE_IMAGE_DIR/$1/mnt")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image $1 is not mounted at $VM_BAKE_IMAGE_DIR/$1/mnt on this host")"
	fi
}

#@help __image_check_closed1
# @command image check closed <image>
# @summary The image has its digest (image close ran): a comment line, else an error line
# @group   image
# @internal
# @see     image seal
#@end
__image_check_closed1() {
	if test -f "$VM_BAKE_BASE/image/$1/digest"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1 is closed")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image seal: $1 has no digest yet (image close $1)")"
	fi
}

#@help __image_check_lock1
# @command image check lock <image>
# @summary The bake lock under .tmp names this image: a comment line, else an error line
# @group   image
# @internal
# @see     image seal
# @see     image lock drop
#@end
__image_check_lock1() {
	local held=""
	IFS= read -r held 2>/dev/null < "$VM_BAKE_BASE/.tmp/image.lock/name" || held=""
	if test "$held" = "$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1 holds the bake lock")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image seal: the bake lock is not $1's (held by ${held:-nobody})")"
	fi
}

#@help __image_check_users1
# @command image check users <image>
# @summary Every user line of the image's template resolves: a uid 'host' names a user of this host, and when there are users the key file VM_BAKE_HOST_KEY is readable: a comment line, else an error line
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_HOST_KEY  the public key every user of the image gets in authorized_keys
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
__image_check_users1() {
	local name="$1" t="" cur="" chain="" p="" n=0 lines="" key="$VM_BAKE_HOST_KEY" line="" u="" s="" ok=yes
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	IFS='
'; set -- $lines; IFS='
'
	for line; do
		u=${line%% *}; s=${line#* }
		test "$s" != host || id -u "$u" > /dev/null 2>&1 || ok=no
	done
	test -z "$lines" || test -r "$key" || ok=no
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $name: users resolve ($(printf '%s' "$lines" | tr '\n' ';'))")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image burn: a user of $name does not resolve (uid host without a host user, or key file $key unreadable: setenv VM_BAKE_HOST_KEY <path>)")"
	fi
}

#@help _image_lock_take1
# @command image lock take <image>
# @summary Act terminal: the bake lock .tmp/image.lock (mkdir, atomic) with the image's name inside; held by another bake, an error and exit 1
# @group   image
# @internal
# @see     image create
# @see     image lock drop
#@end
_image_lock_take1() {
	local lock="$VM_BAKE_BASE/.tmp/image.lock"
	printf '%s\n' "mkdir '$lock' 2>/dev/null || { printf '# Error: the bake lock is held by %s (image lock drop when it is stale)\\n' \"\$(cat '$lock/name' 2>/dev/null)\" >&2; exit 1; }"
	printf '%s\n' "printf '%s\\n' $(sq "$1") > '$lock/name'"
	emit_note "image $1: bake lock taken"
}

#@help _image_lock_drop0
# @command image lock drop
# @summary Act terminal: remove the bake lock -- the last line of 'image seal', and the way out after a bake that died with the lock held
# @group   image
# @example vm-bake image lock drop
# @see     image seal
#@end
_image_lock_drop0() {
	printf '%s\n' "rm -rf '$VM_BAKE_BASE/.tmp/image.lock'"
	emit_note "image: bake lock dropped"
}

#@help _image_lock_release1
# @command image lock release <image>
# @summary Act terminal: remove the bake lock when it names this image, leave it when another bake holds it
# @group   image
# @internal
# @see     image drop
#@end
_image_lock_release1() {
	local lock="$VM_BAKE_BASE/.tmp/image.lock"
	printf '%s\n' "test \"\$(cat '$lock/name' 2>/dev/null)\" = $(sq "$1") && rm -rf '$lock' && printf '# image %s: bake lock dropped\\n' $(sq "$1") >&2 || true"
}

#@help _image_record_write2
# @command image record write <template> <image>
# @summary Act terminal: the record image/<image>/ with template, created (UTC) and dir (0600)
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  recorded as dir
#@end
_image_record_write2() {
	local rec="$VM_BAKE_BASE/image/$2" stamp=""
	stamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
	printf '%s\n' "$MODIFY_DIR_CREATE '$rec' && $MODIFY_FILE_PERMS 0700 '$rec'"
	printf '%s\n' "printf '%s\\n' $(sq "$1") > '$rec/template'"
	printf '%s\n' "printf '%s\\n' '$stamp' > '$rec/created'"
	printf '%s\n' "printf '%s\\n' $(sq "$VM_BAKE_IMAGE_DIR/$2") > '$rec/dir'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$rec/template' '$rec/created' '$rec/dir'"
	emit_note "image $2: record (template $1, created $stamp)"
}

#@help _image_record_remove1
# @command image record remove <image>
# @summary Act terminal: the record image/<image>/ removed
# @group   image
# @internal
# @see     image drop
#@end
_image_record_remove1() {
	printf '%s\n' "rm -rf '$VM_BAKE_BASE/image/$1'"
	emit_note "image $1: record removed"
}

#@help _image_tree_ensure0
# @command image tree ensure
# @summary Act terminal (the invoking user, delegated by zfs allow): vm-bake's datasets exist -- image and guest under the dataset mounted at VM_BAKE_DIR, which root made once and delegated, and the distfiles directories (VM images, package files) beside them -- idempotent, the first act of image create and guest make
# @group   image
# @internal
# @see     image create
# @see     guest make
# @env     VM_BAKE_DIR  vm-bake's dataset: image/, guest/ (datasets) and distfiles/ (directories) live in it
# @env     VM_BAKE_IMAGE_CACHE  the cache directory
# @env     VM_BAKE_PKG_DIR  the package-file directory
#@end
_image_tree_ensure0() {
	printf '%s\n' "ds=\$(zfs list -H -o name '$VM_BAKE_DIR') || { printf '# Error: %s is no dataset (root makes it once and delegates it: help env VM_BAKE_DIR)\\n' '$VM_BAKE_DIR' >&2; exit 1; }"
	printf '%s\n' "zfs list -H -o name \"\$ds/image\" > /dev/null 2>&1 || zfs create \"\$ds/image\" || exit 1"
	printf '%s\n' "zfs list -H -o name \"\$ds/guest\" > /dev/null 2>&1 || zfs create \"\$ds/guest\" || exit 1"
	printf '%s\n' "install -d -m 755 '$VM_BAKE_IMAGE_CACHE' '$VM_BAKE_PKG_DIR' || exit 1"
	printf '%s\n' "printf '# tree: %s/image, %s/guest, cache %s\\n' \"\$ds\" \"\$ds\" '$VM_BAKE_IMAGE_CACHE' >&2"
}

#@help _image_dataset_create1
# @command image dataset create <image>
# @summary Act terminal (the invoking user, delegated by zfs allow): the dataset of the image under the dataset mounted at VM_BAKE_IMAGE_DIR (mount point inherited, the directory the user's)
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  the images' dataset
#@end
_image_dataset_create1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "ds=\$(zfs list -H -o name '$VM_BAKE_IMAGE_DIR') || exit 1"
	printf '%s\n' "zfs create \"\$ds/$1\" || exit 1"
	printf '%s\n' "printf '# image %s: dataset %s at %s\\n' '$1' \"\$ds/$1\" '$dir' >&2"
}

#@help _image_dataset_destroy1
# @command image dataset destroy <image>
# @summary Act terminal (the invoking user, delegated by zfs allow): the image's dataset destroyed with its snapshots (zfs destroy -r; a clone of it makes zfs refuse); none is a note
# @group   image
# @internal
# @see     image drop
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_dataset_destroy1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "ds=\$(zfs list -H -o name '$dir' 2>/dev/null) || { printf '# image %s: no dataset at %s\\n' '$1' '$dir' >&2; exit 0; }"
	printf '%s\n' "zfs destroy -r \"\$ds\" || exit 1"
	printf '%s\n' "printf '# image %s: %s destroyed\\n' '$1' \"\$ds\" >&2"
}

#@help _image_fetch1
# @command image fetch <url>
# @summary Act terminal: the file behind the url fetched into VM_BAKE_IMAGE_CACHE under its base name unless already there (fetch(1), resumed)
# @group   image
# @internal
# @see     image create image
# @env     VM_BAKE_IMAGE_CACHE  the directory the VM images are fetched into
#@end
_image_fetch1() {
	local f="$VM_BAKE_IMAGE_CACHE/${1##*/}"
	printf '%s\n' "test -f '$f' && printf '# image: %s cached\\n' '$f' >&2 || fetch -q -R -o '$f' $(sq "$1") || exit 1"
}

#@help _image_verify2
# @command image verify <url> <sha256>
# @summary Act terminal: the sha256 of the cached file equals the template's record, else the file is removed and the bake fails
# @group   image
# @internal
# @see     image create image
# @env     VM_BAKE_IMAGE_CACHE  the directory the VM images are fetched into
#@end
_image_verify2() {
	local f="$VM_BAKE_IMAGE_CACHE/${1##*/}"
	printf '%s\n' "d=\$(sha256 -q '$f') || exit 1"
	printf '%s\n' "test \"\$d\" = $(sq "$2") || { printf '# Error: %s: sha256 %s, the template says %s (file removed)\\n' '$f' \"\$d\" $(sq "$2") >&2; rm -f '$f'; exit 1; }"
	printf '%s\n' "printf '# image: %s verified (%s)\\n' '$f' \"\$d\" >&2"
}

#@help _image_disk_write3
# @command image disk write <image> <url> <size>
# @summary Act terminal: the cached VM image (xz) decompressed into disk0.img, then the file extended to the resource's size (sparse); an existing disk0.img is an error
# @group   image
# @internal
# @see     image create image
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_IMAGE_CACHE  the directory the VM images are fetched into
#@end
_image_disk_write3() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img" f="$VM_BAKE_IMAGE_CACHE/${2##*/}"
	printf '%s\n' "test ! -e '$img' || { printf '# Error: %s exists\\n' '$img' >&2; exit 1; }"
	printf '%s\n' "xz -dc '$f' > '$img' || exit 1"
	printf '%s\n' "truncate -s $(sq "$3") '$img' || exit 1"
	emit_note "image $1: disk0.img from ${2##*/}, $3"
}

#@help _image_disk_create2
# @command image disk create <image> <size>
# @summary Act terminal: disk0.img as a sparse file of the given size (truncate) in the image's directory; an existing file is an error
# @group   image
# @internal
# @see     image create release
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_create2() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "test ! -e '$img' || { printf '# Error: %s exists\\n' '$img' >&2; exit 1; }"
	printf '%s\n' "truncate -s $(sq "$2") '$img' || exit 1"
	emit_note "image $1: disk0.img sparse, $2"
}

#@help _image_disk_attach1
# @command image disk attach <image>
# @summary Act terminal (root): disk0.img attached as a vnode md (already attached: a note)
# @group   image
# @internal
# @see     image create release
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_attach1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -z \"\$md\" || { printf '# image %s: already attached to %s\\n' '$1' \"\$md\" >&2; exit 0; }"
	printf '%s\n' "md=\$(mdconfig -a -t vnode -f '$img') || exit 1"
	printf '%s\n' "printf '# image %s: %s attached to %s\\n' '$1' '$img' \"\$md\" >&2"
}

#@help _image_disk_partition1
# @command image disk partition <image>
# @summary Act terminal (root): the md of disk0.img found by its path (mdconfig -lv), GPT, an EFI system partition of 260M labelled <image>-efi, the rest a freebsd-ufs partition labelled <image>-root (the labels fstab and the loader use in every guest of this image)
# @group   image
# @internal
# @see     image create release
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_partition1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -n \"\$md\" || { printf '# Error: %s is not attached\\n' '$img' >&2; exit 1; }"
	printf '%s\n' "gpart create -s gpt \"\$md\" || exit 1"
	printf '%s\n' "gpart add -t efi -s 260M -a 1m -l '$1-efi' \"\$md\" || exit 1"
	printf '%s\n' "gpart add -t freebsd-ufs -a 1m -l '$1-root' \"\$md\" || exit 1"
	printf '%s\n' "printf '# image %s: GPT on %s, %s-efi and %s-root\\n' '$1' \"\$md\" '$1' '$1' >&2"
}

#@help _image_disk_format1
# @command image disk format <image>
# @summary Act terminal (root): FAT32 on the system partition, UFS with soft updates journaling (newfs -j) on the root, both found by their labels
# @group   image
# @internal
# @see     image create release
#@end
_image_disk_format1() {
	printf '%s\n' "newfs_msdos -F 32 -c 1 '/dev/gpt/$1-efi' > /dev/null || exit 1"
	printf '%s\n' "newfs -j '/dev/gpt/$1-root' > /dev/null || exit 1"
	printf '%s\n' "printf '# image %s: gpt/%s-efi msdosfs, gpt/%s-root ufs\\n' '$1' '$1' '$1' >&2"
}

#@help _image_disk_grow1
# @command image disk grow <image>
# @summary Act terminal (root): the GPT of the attached VM image repaired after the file grew (gpart recover), its root partition (label rootfs) resized to the end, the file system grown (growfs)
# @group   image
# @internal
# @see     image create image
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_grow1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -n \"\$md\" || { printf '# Error: %s is not attached\\n' '$img' >&2; exit 1; }"
	printf '%s\n' "gpart recover \"\$md\" > /dev/null || exit 1"
	printf '%s\n' "i=\$(gpart show -l \"\$md\" | awk '\$4 == \"rootfs\" { print \$3 }'); test -n \"\$i\" || { printf '# Error: no partition labelled rootfs on %s\\n' \"\$md\" >&2; exit 1; }"
	printf '%s\n' "gpart resize -i \"\$i\" \"\$md\" > /dev/null || exit 1"
	printf '%s\n' "growfs -y \"/dev/\${md}p\$i\" > /dev/null || exit 1"
	printf '%s\n' "printf '# image %s: %sp%s grown to the disk\\n' '$1' \"\$md\" \"\$i\" >&2"
}

#@help _image_disk_relabel1
# @command image disk relabel <image>
# @summary Act terminal (root): the VM image's partitions efiboot0 and rootfs relabelled <image>-efi and <image>-root, so every image is addressed the same way and two of them never share a label
# @group   image
# @internal
# @see     image create image
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_relabel1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -n \"\$md\" || { printf '# Error: %s is not attached\\n' '$img' >&2; exit 1; }"
	printf '%s\n' "e=\$(gpart show -l \"\$md\" | awk '\$4 == \"efiboot0\" { print \$3 }'); r=\$(gpart show -l \"\$md\" | awk '\$4 == \"rootfs\" { print \$3 }'); test -n \"\$e\" && test -n \"\$r\" || { printf '# Error: efiboot0 or rootfs missing on %s\\n' \"\$md\" >&2; exit 1; }"
	printf '%s\n' "gpart modify -i \"\$e\" -l '$1-efi' \"\$md\" > /dev/null && gpart modify -i \"\$r\" -l '$1-root' \"\$md\" > /dev/null || exit 1"
	printf '%s\n' "printf '# image %s: labels %s-efi and %s-root\\n' '$1' '$1' '$1' >&2"
}

#@help _image_disk_mount1
# @command image disk mount <image>
# @summary Act terminal (root, host or builder): the root gpt/<image>-root at VM_BAKE_IMAGE_DIR/<image>/mnt, the system partition gpt/<image>-efi at mnt/boot/efi, devfs at mnt/dev (the package scripts run in a chroot and want /dev/null) -- the same path wherever it runs
# @group   image
# @internal
# @see     image base
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_mount1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "mkdir -p '$mnt' && mount -t ufs '/dev/gpt/$1-root' '$mnt' || exit 1"
	printf '%s\n' "mkdir -p '$mnt/boot/efi' && mount -t msdosfs '/dev/gpt/$1-efi' '$mnt/boot/efi' || exit 1"
	printf '%s\n' "install -d -m 755 '$mnt/dev' && mount -t devfs devfs '$mnt/dev' || exit 1"
	printf '%s\n' "printf '# image %s: mounted at %s\\n' '$1' '$mnt' >&2"
}

#@help _image_keys_write1
# @command image keys write <image>
# @summary Act terminal (root, host or builder): the trusted package signing keys under /usr/share/keys (pkg, pkgbase-<major>; whichever exist where it runs) copied into the image -- 'pkg -r' looks for the fingerprints below the root it installs into
# @group   image
# @internal
# @see     image base content release
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_keys_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "install -d -m 755 '$mnt/usr/share/keys' || exit 1"
	printf '%s\n' "for d in /usr/share/keys/*/; do test -d \"\$d\" && cp -R \"\${d%/}\" '$mnt/usr/share/keys/' || exit 1; done"
	printf '%s\n' "printf '# image %s: signing keys %s\\n' '$1' \"\$(ls '$mnt/usr/share/keys' | tr '\\n' ' ')\" >&2"
}

#@help _image_pkg_base3
# @command image pkg base <image> <abi> <osversion>
# @summary Act terminal (root, host or builder): 'pkg -r <mnt>' installs FreeBSD-set-minimal, FreeBSD-kernel-generic, FreeBSD-ssh (sshd is not in the minimal set) and pkg from the repositories configured where it runs, the ABI and OSVERSION pinned to the template's release (IGNORE_OSVERSION, ASSUME_ALWAYS_YES); pkg refuses this at securelevel 1 or higher (pkgbase carries schg files), hence the builder
# @group   image
# @internal
# @see     image base content release
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_pkg_base3() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "pkg -r '$mnt' -o ABI=$(sq "$2") -o OSVERSION=$(sq "$3") -o IGNORE_OSVERSION=yes -o ASSUME_ALWAYS_YES=yes install FreeBSD-set-minimal FreeBSD-kernel-generic FreeBSD-ssh pkg || exit 1"
	printf '%s\n' "printf '# image %s: base installed (%s, %s)\\n' '$1' $(sq "$2") $(sq "$3") >&2"
}

#@help _image_repo_write1
# @command image repo write <image>
# @summary Act terminal (root, host or builder): the host's repository overrides /usr/local/etc/pkg/repos/*.conf written into the image, read at generation time on the host (the guest follows the host: the same branches); pkgbase's own /etc/pkg/FreeBSD.conf is already in the image
# @group   image
# @internal
# @see     image base content
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_repo_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" f=""
	printf '%s\n' "install -d -m 755 '$mnt/usr/local/etc/pkg/repos' || exit 1"
	for f in /usr/local/etc/pkg/repos/*.conf; do
		test -f "$f" || continue
		printf '%s\n' "cat > '$mnt/usr/local/etc/pkg/repos/${f##*/}' <<'EOF_REPO'"
		cat "$f"
		printf '%s\n' "EOF_REPO"
	done
	printf '%s\n' "chmod 644 '$mnt/usr/local/etc/pkg/repos/'*.conf 2>/dev/null; true"
	printf '%s\n' "printf '# image %s: repository configuration of the host written\\n' '$1' >&2"
}

#@help _image_boot_write1
# @command image boot write <image>
# @summary Act terminal (root, host or builder): the image's own loader.efi into the system partition as EFI/BOOT/BOOTX64.efi and EFI/freebsd/loader.efi, loader.conf (serial console for the bhyve nmdm, root from gpt/<image>-root) and fstab (root rw, the system partition noauto)
# @group   image
# @internal
# @see     image base content
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_boot_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "mkdir -p '$mnt/boot/efi/EFI/BOOT' '$mnt/boot/efi/EFI/freebsd' || exit 1"
	printf '%s\n' "cp '$mnt/boot/loader.efi' '$mnt/boot/efi/EFI/BOOT/BOOTX64.efi' || exit 1"
	printf '%s\n' "cp '$mnt/boot/loader.efi' '$mnt/boot/efi/EFI/freebsd/loader.efi' || exit 1"
	printf '%s\n' "cat > '$mnt/boot/loader.conf' <<'EOF_LOADER'"
	printf '%s\n' 'autoboot_delay="2"' 'boot_serial="YES"' 'boot_multicons="YES"' 'console="comconsole,efi"' 'comconsole_speed="115200"' "vfs.root.mountfrom=\"ufs:/dev/gpt/$1-root\""
	printf '%s\n' "EOF_LOADER"
	printf '%s\n' "cat > '$mnt/etc/fstab' <<'EOF_FSTAB'"
	printf '%s\n' "/dev/gpt/$1-root	/		ufs	rw		1 1" "/dev/gpt/$1-efi	/boot/efi	msdosfs	rw,noauto	0 0"
	printf '%s\n' "EOF_FSTAB"
	printf '%s\n' "printf '# image %s: loader in the system partition, loader.conf, fstab\\n' '$1' >&2"
}

#@help _image_pkg_install3
# @command image pkg install <image> <abi> <osversion>
# @summary Act terminal (root, host or builder): the template's resolved package list (read at generation time) installed with 'pkg -c <mnt>' -- a chroot into the image, so the packages' scripts run with the image's own tools (indexinfo and the like) -- under the pinned ABI and OSVERSION, the resolver of the place copied in for the fetch, the image's package cache emptied afterwards; an empty list is a note
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_pkg_install3() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 pkgs=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	pkgs=$(awk -v base="$VM_BAKE_BASE" -v family=package -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | tr '\n' ' ')
	if test -n "${pkgs% }"; then
		printf '%s\n' "cp /etc/resolv.conf '$mnt/etc/resolv.conf' || exit 1"
		printf '%s\n' "pkg -c '$mnt' -o ABI=$(sq "$2") -o OSVERSION=$(sq "$3") -o IGNORE_OSVERSION=yes -o ASSUME_ALWAYS_YES=yes install $pkgs&& pkg -c '$mnt' clean -ay > /dev/null || exit 1"
		printf '%s\n' "printf '# image %s: packages %s\\n' '$1' $(sq "${pkgs% }") >&2"
	else
		emit_note "image $1: the template lists no packages"
	fi
}

#@help _image_rc_write1
# @command image rc write <image>
# @summary Act terminal (root, host or builder): /etc/rc.conf of the image from the template's resolved rc lines (read at generation time, each value quoted); hostname and network come with the guest, not here
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_rc_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 lines=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=rc -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | sed 's/^\([^=]*\)=\(.*\)$/\1="\2"/')
	printf '%s\n' "cat > '$mnt/etc/rc.conf' <<'EOF_RC'"
	printf '%s\n' "$lines"
	printf '%s\n' "EOF_RC"
	printf '%s\n' "printf '# image %s: rc.conf, %s lines\\n' '$1' '$(printf '%s\n' "$lines" | grep -c .)' >&2"
}

#@help _image_env_write1
# @command image env write <image>
# @summary Act terminal (root, host or builder): /etc/profile.d/vm-bake.sh of the image from the template's resolved env lines (read at generation time), one export per line, so every login shell of a guest carries them; an empty list writes nothing
# @group   image
# @internal
# @see     image burn
# @see     template env add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_env_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 lines=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=env -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | sed 's/^\([^=]*\)=\(.*\)$/export \1="\2"/')
	if test -n "$lines"; then
		printf '%s\n' "install -d -m 755 '$mnt/etc/profile.d' && cat > '$mnt/etc/profile.d/vm-bake.sh' <<'EOF_ENV'"
		printf '%s\n' "# written by vm-bake (template env) -- the sessions' environment"
		printf '%s\n' "$lines"
		printf '%s\n' "EOF_ENV"
		printf '%s\n' "chmod 644 '$mnt/etc/profile.d/vm-bake.sh' && printf '# image %s: profile.d/vm-bake.sh, %s variables\\n' '$1' '$(printf '%s\n' "$lines" | grep -c .)' >&2"
	else
		emit_note "image $1: the template lists no environment variables"
	fi
}

#@help _image_user_make1
# @command image user make <image>
# @summary Act terminal (root, host or builder): every user of the template's resolved user list (read at generation time) created in the image with 'pw -R' -- uid 'host' is the uid of that user on this host -- without a password, with the public key VM_BAKE_HOST_KEY in their authorized_keys and in /etc/ssh/authorized_keys/<user>, where sshd reads it without the home (a view arrives only after the mount, image ssh write names both places)
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_HOST_KEY  the public key file; a leading ~/ is the invoking user's home
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_user_make1() {
	local name="$1" mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 lines="" key="$VM_BAKE_HOST_KEY" keytext="" line="" u="" s="" uid=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	keytext=$(cat "$key" 2>/dev/null || true)
	IFS='
'; set -- $lines; IFS='
'
	for line; do
		u=${line%% *}; s=${line#* }; uid=$s
		test "$s" != host || uid=$(id -u "$u" 2>/dev/null || true)
		printf '%s\n' "pw -R '$mnt' usershow $(sq "$u") > /dev/null 2>&1 || pw -R '$mnt' useradd $(sq "$u") -u $(sq "$uid") -c $(sq "$u") -d '/home/$u' -s /bin/sh -w no || exit 1"
		printf '%s\n' "g=\$(awk -F: -v u=$(sq "$u") '\$1 == u { print \$3 }' '$mnt/etc/group'); test -n \"\$g\" || { printf '# Error: no group %s in the image\\n' $(sq "$u") >&2; exit 1; }"
		printf '%s\n' "install -d -m 755 '$mnt/home' && install -d -m 750 '$mnt/home/$u' && install -d -m 700 '$mnt/home/$u/.ssh' || exit 1"
		printf '%s\n' "printf '%s\\n' $(sq "$keytext") > '$mnt/home/$u/.ssh/authorized_keys' || exit 1"
		printf '%s\n' "chmod 700 '$mnt/home/$u/.ssh' && chmod 600 '$mnt/home/$u/.ssh/authorized_keys' && chown -R $(sq "$uid"):\"\$g\" '$mnt/home/$u' || exit 1"
		printf '%s\n' "install -d -m 755 '$mnt/etc/ssh/authorized_keys' && printf '%s\\n' $(sq "$keytext") > '$mnt/etc/ssh/authorized_keys/$u' && chmod 644 '$mnt/etc/ssh/authorized_keys/$u' || exit 1"
		printf '%s\n' "printf '# image %s: user %s (uid %s), key %s\\n' '$name' $(sq "$u") $(sq "$uid") $(sq "$key") >&2"
	done
	test -n "$lines" || emit_note "image $name: the template lists no users"
}

#@help _image_view_write1
# @command image view write <image>
# @summary Act terminal (root, host or builder): when the template's resolved services (read at generation time) say 'files view', the image learns to take its home from the host -- virtio_p9fs_load="YES" appended to loader.conf and the share home mounted on the home of the template's host-uid user by a p9fs line in fstab; after it the directory /var/git of the disk, owned by that user, hung by a nullfs line (failok: a view without the mount point does not stop the boot) on VM_BAKE_REPO_LOCAL under that home -- where the guest's clones live, because git cannot write its objects on p9fs; no view in the template is a note. The TRANSPORT has to come from the loader, not from kld_list in rc.conf: mountcritlocal works through the fstab before rc.d/kld loads anything, the mount then fails for want of the device, and the boot stops in the single-user shell (05.11., dalmatia)
# @group   image
# @internal
# @see     image burn
# @see     template service add
# @see     guest view ensure
# @see     guest repo add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_REPO_LOCAL  the clones' directory under the guest's home
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_view_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 u="" kld="" seen=0
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'files view' || { emit_note "image $1: no view in the template, the home of its guests stays on their disk"; return 0; }
	u=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | awk '$2 == "host" { print $1 }')
	seen=$(printf '%s\n' "$u" | grep -c . || true)
	test "$seen" -eq 1 || { generate_error "image view write: the view is the home of the template's host-uid user, and $t has $seen of them (template user add <template> <name> host)"; return 0; }
	printf '%s\n' "test -d '$mnt/home/$u' || { printf '# Error: no home of %s in the image (image user make first)\\n' $(sq "$u") >&2; exit 1; }"
	printf '%s\n' "printf '%s\\n' 'virtio_p9fs_load=\"YES\"' >> '$mnt/boot/loader.conf' || exit 1"
	printf '%s\n' "printf '%s\\t%s\\tp9fs\\trw\\t0 0\\n' home '/home/$u' >> '$mnt/etc/fstab' || exit 1"
	printf '%s\n' "g=\$(awk -F: -v u=$(sq "$u") '\$1 == u { print \$3 }' '$mnt/etc/group'); test -n \"\$g\" || { printf '# Error: no group %s in the image\\n' $(sq "$u") >&2; exit 1; }"
	printf '%s\n' "install -d -m 755 '$mnt/var/git' && chown $(sq "$(id -u "$u" 2>/dev/null || printf '%s' "$u")"):\"\$g\" '$mnt/var/git' || exit 1"
	printf '%s\n' "printf '%s\\t%s\\tnullfs\\trw,failok\\t0 0\\n' /var/git '/home/$u/$VM_BAKE_REPO_LOCAL' >> '$mnt/etc/fstab' || exit 1"
	printf '%s\n' "printf '# image %s: the share home as the home of %s (p9fs), transport virtio_p9fs from the loader; /var/git of the disk as %s in that home\\n' '$1' $(sq "$u") '$VM_BAKE_REPO_LOCAL' >&2"
}

#@help _image_root_lock1
# @command image root lock <image>
# @summary Act terminal (root, host or builder): root of the image gets no password ('pw -R usermod root -w no', the field becomes *) -- pkgbase and the VM images ship root with an empty password, which would log in on the console; the host is the only way to root in a guest
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_root_lock1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "pw -R '$mnt' usermod root -w no || exit 1"
	printf '%s\n' "printf '# image %s: root locked\\n' '$1' >&2"
}

#@help _image_doas_write1
# @command image doas write <image>
# @summary Act terminal (root, host or builder): when the template's resolved package list holds doas, /usr/local/etc/doas.conf in the image permits every user of the template without a password (the escalation is visible in the template: the package and the users); otherwise a note
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_doas_write1() {
	local name="$1" mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 pkgs="" users=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	pkgs=$(awk -v base="$VM_BAKE_BASE" -v family=package -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | awk '{ print "permit nopass " $1 }')
	if printf '%s\n' "$pkgs" | grep -qx doas; then
		printf '%s\n' "install -d -m 755 '$mnt/usr/local/etc' && cat > '$mnt/usr/local/etc/doas.conf' <<'EOF_DOAS'"
		printf '%s\n' "$users"
		printf '%s\n' "EOF_DOAS"
		printf '%s\n' "printf '# image %s: doas.conf: %s\\n' '$name' $(sq "$(printf '%s' "$users" | tr '\n' ';')") >&2"
	else
		emit_note "image $name: no doas in the template, no escalation"
	fi
}

#@help _image_ssh_write1
# @command image ssh write <image>
# @summary Act terminal (root, host or builder): sshd_config of the image gets Port VM_BAKE_SSH_PORT, PermitRootLogin no, PasswordAuthentication no, KbdInteractiveAuthentication no, LogLevel VERBOSE (a refused key says in auth.log WHY), AuthorizedKeysFile '/etc/ssh/authorized_keys/%u .ssh/authorized_keys' (the login must not hang on a mount, and a view arrives only after the home is mounted -- it would hide the keys on the disk), and X11Forwarding yes when the template's resolved services (read at generation time) list 'display x'. Every one of those directives the shipped sshd_config already sets is commented out first: sshd takes the FIRST value of a parameter, and FreeBSD ships an active 'AuthorizedKeysFile .ssh/authorized_keys' that would win over an appended one. Appended once, the Port line is the witness
# @group   image
# @internal
# @see     image burn
# @see     session create x
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_SSH_PORT  the port sshd listens on in every guest of this image
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_ssh_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 x11=no
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'display x' && x11=yes
	printf '%s\n' "test -d '$mnt/etc/ssh' || { printf '# Error: no /etc/ssh in the image (image base first)\\n' >&2; exit 1; }"
	printf '%s\n' "grep -q '^Port $VM_BAKE_SSH_PORT$' '$mnt/etc/ssh/sshd_config' || sed -i '' -E 's/^[[:space:]]*(Port|PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|LogLevel|AuthorizedKeysFile|X11Forwarding)[[:space:]]/#&/' '$mnt/etc/ssh/sshd_config' || exit 1"
	printf '%s\n' "grep -q '^Port $VM_BAKE_SSH_PORT$' '$mnt/etc/ssh/sshd_config' || cat >> '$mnt/etc/ssh/sshd_config' <<'EOF_SSHD'"
	printf '%s\n' "" "Port $VM_BAKE_SSH_PORT" "PermitRootLogin no" "PasswordAuthentication no" "KbdInteractiveAuthentication no" "LogLevel VERBOSE" "AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys"
	test "$x11" = no || printf '%s\n' "X11Forwarding yes"
	printf '%s\n' "EOF_SSHD"
	printf '%s\n' "printf '# image %s: sshd on port %s, keys only, no root, X11 forwarding %s\\n' '$1' '$VM_BAKE_SSH_PORT' '$x11' >&2"
}

#@help _image_port_build1
# @command image port build <image>
# @summary Act terminal (root, in the builder): the ports tree at /usr/ports (git, branch VM_BAKE_PORTS_BRANCH, cloned once), then for every port of the template's resolved list (read at generation time): the package name from the port, built already under /usr/ports/packages/All is kept, else the missing dependencies installed from the repositories ('make missing', pkg install by origin) and 'make package' with BATCH
# @group   image
# @internal
# @see     image burn
# @see     template port add
# @env     VM_BAKE_PORTS_BRANCH  the branch of the ports tree (main for latest, a quarter for quarterly)
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_port_build1() {
	local t="" cur="" chain="" p="" n=0 o="" origins=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	origins=$(awk -v base="$VM_BAKE_BASE" -v family=port -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "test -d /usr/ports/.git || git clone -q --depth 1 -b $(sq "$VM_BAKE_PORTS_BRANCH") https://git.FreeBSD.org/ports.git /usr/ports || exit 1"
	for o in $origins; do
		printf '%s\n' "n=\$(make -C '/usr/ports/$o' -V PKGNAME) && test -n \"\$n\" || { printf '# Error: no port %s in the tree\\n' '$o' >&2; exit 1; }"
		printf '%s\n' "if test -f \"/usr/ports/packages/All/\$n.pkg\"; then printf '# port %s: %s built already\\n' '$o' \"\$n\" >&2; else missing=\$(make -C '/usr/ports/$o' BATCH=yes missing) && { test -z \"\$missing\" || pkg install -y \$missing; } && make -C '/usr/ports/$o' BATCH=yes package > \"/usr/ports/packages/build-\$(echo '$o' | tr / -).log\" 2>&1 && printf '# port %s: %s built\\n' '$o' \"\$n\" >&2 || { printf '# Error: port %s failed, log /usr/ports/packages/build-%s.log in the builder\\n' '$o' \"\$(echo '$o' | tr / -)\" >&2; exit 1; }; fi"
	done
	test -n "$origins" || emit_note "image $1: the template lists no ports"
}

#@help _image_port_install1
# @command image port install <image>
# @summary Act terminal (root, in the builder): every built package of the template's ports copied into the image under /var/cache/vm-bake and installed there with 'pkg -c add' (dependencies from the repositories), the copy removed
# @group   image
# @internal
# @see     image burn
# @see     image port build
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_port_install1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 o="" origins=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	origins=$(awk -v base="$VM_BAKE_BASE" -v family=port -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "install -d -m 755 '$mnt/var/cache/vm-bake' || exit 1"
	for o in $origins; do
		printf '%s\n' "n=\$(make -C '/usr/ports/$o' -V PKGNAME) && test -f \"/usr/ports/packages/All/\$n.pkg\" || { printf '# Error: port %s: no package built\\n' '$o' >&2; exit 1; }"
		printf '%s\n' "cp \"/usr/ports/packages/All/\$n.pkg\" '$mnt/var/cache/vm-bake/' && pkg -c '$mnt' -o ASSUME_ALWAYS_YES=yes add \"/var/cache/vm-bake/\$n.pkg\" && rm -f '$mnt/var/cache/vm-bake/'\"\$n.pkg\" || exit 1"
		printf '%s\n' "printf '# image %s: port %s installed (%s)\\n' '$1' '$o' \"\$n\" >&2"
	done
	test -n "$origins" || emit_note "image $1: the template lists no ports"
}

#@help __image_check_pkgfiles1
# @command image check pkgfiles <image>
# @summary Every package file of the image's template (read at generation time over the chain) lies in VM_BAKE_PKG_DIR: a comment line, else an error line naming the missing one
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_PKG_DIR  the directory the package files are kept in
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
__image_check_pkgfiles1() {
	local t="" cur="" chain="" p="" n=0 f="" files="" missing=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	files=$(awk -v base="$VM_BAKE_BASE" -v family=pkgfile -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	for f in $files; do test -f "$VM_BAKE_PKG_DIR/$f" || missing="$missing $f"; done
	if test -z "$missing"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1: package files present ($(printf '%s' "$files" | tr '\n' ' '))")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image burn: package file missing in $VM_BAKE_PKG_DIR:$missing (copy it there)")"
	fi
}

#@help __image_pkgfile_stage1
# @command image pkgfile stage <image>
# @summary By VM_BAKE_BAKE_IN rewrite to 'image pkgfile stage host' (copied into the mounted image) or 'image pkgfile stage builder' (streamed over ssh into the image mounted in the builder); any other value is an error line
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_BAKE_IN  host | builder
#@end
__image_pkgfile_stage1() {
	case "$VM_BAKE_BAKE_IN" in
		host|builder) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkgfile stage $VM_BAKE_BAKE_IN $(sq "$1")" ;;
		*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image pkgfile stage: VM_BAKE_BAKE_IN is '$VM_BAKE_BAKE_IN' (host | builder)")" ;;
	esac
}

#@help _image_pkgfile_stage_host1
# @command image pkgfile stage host <image>
# @summary Act terminal (root, host): every package file of the template copied from VM_BAKE_PKG_DIR into the mounted image under /var/cache/vm-bake
# @group   image
# @internal
# @see     image pkgfile stage
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_PKG_DIR  the directory the package files are kept in
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_pkgfile_stage_host1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 f="" files=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	files=$(awk -v base="$VM_BAKE_BASE" -v family=pkgfile -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "install -d -m 755 '$mnt/var/cache/vm-bake' || exit 1"
	for f in $files; do
		printf '%s\n' "cp '$VM_BAKE_PKG_DIR/$f' '$mnt/var/cache/vm-bake/' || exit 1"
		printf '%s\n' "printf '# image %s: %s staged\\n' '$1' '$f' >&2"
	done
	test -n "$files" || emit_note "image $1: the template lists no package files"
}

#@help _image_pkgfile_stage_builder1
# @command image pkgfile stage builder <image>
# @summary Act terminal (the invoking user, host side): every package file of the template streamed over ssh into the builder, where doas writes it into the mounted image under /var/cache/vm-bake
# @group   image
# @internal
# @see     image pkgfile stage
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_PKG_DIR  the directory the package files are kept in
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the builder's sshd port
# @env     VM_BAKE_BUILDER  the builder guest's name
# @env     VM_BAKE_BUILDER_USER  the user ssh logs in as
# @env     VM_BAKE_BUILDER_ADDRESS  the builder's address
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_pkgfile_stage_builder1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" key="$VM_BAKE_HOST_KEY" t="" cur="" chain="" p="" n=0 f="" files="" ssh=""
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	ssh="ssh -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$VM_BAKE_BUILDER' -o StrictHostKeyChecking=accept-new -o BatchMode=yes '$VM_BAKE_BUILDER_USER@$VM_BAKE_BUILDER_ADDRESS'"
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	files=$(awk -v base="$VM_BAKE_BASE" -v family=pkgfile -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	for f in $files; do
		printf '%s\n' "$ssh \"doas sh -c \\\"install -d -m 755 '$mnt/var/cache/vm-bake' && cat > '$mnt/var/cache/vm-bake/$f'\\\"\" < '$VM_BAKE_PKG_DIR/$f' || exit 1"
		printf '%s\n' "printf '# image %s: %s streamed into the builder\\n' '$1' '$f' >&2"
	done
	test -n "$files" || emit_note "image $1: the template lists no package files"
}

#@help _image_pkgfile_add1
# @command image pkgfile add <image>
# @summary Act terminal (root, host or builder): every staged package file: its dependencies read from the file (pkg query -F) and installed from the repositories, then the file itself with 'pkg -c add' (a chroot; pkg add alone fetches nothing), the staged copy removed
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_pkgfile_add1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 f="" files=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	files=$(awk -v base="$VM_BAKE_BASE" -v family=pkgfile -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	for f in $files; do
		printf '%s\n' "deps=\$(pkg -c '$mnt' query -F '/var/cache/vm-bake/$f' %dn | tr '\\n' ' '); test -z \"\$deps\" || pkg -c '$mnt' -o ASSUME_ALWAYS_YES=yes install \$deps || exit 1"
		printf '%s\n' "pkg -c '$mnt' -o ASSUME_ALWAYS_YES=yes add '/var/cache/vm-bake/$f' && rm -f '$mnt/var/cache/vm-bake/$f' || exit 1"
		printf '%s\n' "printf '# image %s: %s installed\\n' '$1' '$f' >&2"
	done
	test -n "$files" || emit_note "image $1: the template lists no package files"
}

#@help _image_pkg_report1
# @command image pkg report <image>
# @summary Act terminal (root, host or builder): the package list of the image (pkg -r info) and its audit (pkg -r audit -F, the vulnerability list fetched into the image) written into the image under /var/log/vm-bake/ -- present in every guest; a vulnerable package is reported, not a failure
# @group   image
# @internal
# @see     image close
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_pkg_report1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "install -d -m 755 '$mnt/var/log/vm-bake' || exit 1"
	printf '%s\n' "pkg -r '$mnt' info > '$mnt/var/log/vm-bake/packages.txt' && chmod 644 '$mnt/var/log/vm-bake/packages.txt' || exit 1"
	printf '%s\n' "pkg -r '$mnt' audit -F > '$mnt/var/log/vm-bake/audit.txt' 2>&1; chmod 644 '$mnt/var/log/vm-bake/audit.txt'; printf '# image %s: %s packages, audit exit %s (/var/log/vm-bake in the image)\\n' '$1' \"\$(grep -c . '$mnt/var/log/vm-bake/packages.txt')\" \"\$?\" >&2"
}

#@help _image_disk_unmount1
# @command image disk unmount <image>
# @summary Act terminal (root, host or builder): devfs, the system partition and the root unmounted
# @group   image
# @internal
# @see     image close
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_unmount1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "umount '$mnt/dev' || exit 1"
	printf '%s\n' "umount '$mnt/boot/efi' || exit 1"
	printf '%s\n' "umount '$mnt' || exit 1"
	printf '%s\n' "printf '# image %s: unmounted\\n' '$1' >&2"
}

#@help _image_disk_detach1
# @command image disk detach <image>
# @summary Act terminal (root): the md of disk0.img, found by its path, detached (none attached: a note)
# @group   image
# @internal
# @see     image close host
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_detach1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -n \"\$md\" || { printf '# image %s: not attached\\n' '$1' >&2; exit 0; }"
	printf '%s\n' "mdconfig -d -u \"\${md#md}\" || exit 1"
	printf '%s\n' "printf '# image %s: %s detached\\n' '$1' \"\$md\" >&2"
}

#@help _image_disk_release1
# @command image disk release <image>
# @summary Act terminal (root): whatever of the image is still mounted on this host unmounted (the system partition, the root), the md detached if attached
# @group   image
# @internal
# @see     image drop
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_release1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "umount '$dir/mnt/dev' 2>/dev/null; umount '$dir/mnt/boot/efi' 2>/dev/null; umount '$dir/mnt' 2>/dev/null; true"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -z \"\$md\" || mdconfig -d -u \"\${md#md}\" || exit 1"
	printf '%s\n' "printf '# image %s: released on the host\\n' '$1' >&2"
}

#@help _image_digest_write1
# @command image digest write <image>
# @summary Act terminal: sha256 of disk0.img into digest beside it and into the record image/<image>/digest (0600)
# @group   image
# @internal
# @see     image close
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_digest_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" rec="$VM_BAKE_BASE/image/$1"
	printf '%s\n' "d=\$(sha256 -q '$dir/disk0.img') || exit 1"
	printf '%s\n' "printf '%s\\n' \"\$d\" > '$dir/digest' || exit 1"
	printf '%s\n' "printf '%s\\n' \"\$d\" > '$rec/digest' && $MODIFY_FILE_PERMS 0600 '$rec/digest' || exit 1"
	printf '%s\n' "printf '# image %s: sha256 %s\\n' '$1' \"\$d\" >&2"
}

#@help _image_snapshot_take1
# @command image snapshot take <image>
# @summary Act terminal (the invoking user, delegated by zfs allow): the snapshot @image of the image's dataset (found by its mount point)
# @group   image
# @internal
# @see     image seal
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_snapshot_take1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "ds=\$(zfs list -H -o name '$dir') || exit 1"
	printf '%s\n' "zfs snapshot \"\$ds@image\" || exit 1"
	printf '%s\n' "printf '# image %s: snapshot %s@image\\n' '$1' \"\$ds\" >&2"
}

#@help _image_readonly_set1
# @command image readonly set <image>
# @summary Act terminal (the invoking user, delegated by zfs allow): the image's dataset readonly -- the image is a product, guests are clones of its snapshot
# @group   image
# @internal
# @see     image seal
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_readonly_set1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "ds=\$(zfs list -H -o name '$dir') || exit 1"
	printf '%s\n' "zfs set readonly=on \"\$ds\" || exit 1"
	printf '%s\n' "printf '# image %s: %s readonly\\n' '$1' \"\$ds\" >&2"
}

#@help _image_builder_conf_write1
# @command image builder conf write <image>
# @summary Act terminal (the invoking user: the clone is theirs): the builder guest's vm-bhyve configuration VM_BAKE_GUEST_DIR/<builder>/<builder>.conf: UEFI, cpu and memory from the builder's template (through its guest record, read at generation time), its own disk0.img, the switch, and the image's disk0.img as disk1 (custom path)
# @group   image
# @internal
# @see     image builder start
# @env     VM_BAKE_GUEST_DIR  the guests' directory (vm-bhyve's vm_dir)
# @env     VM_BAKE_GUEST_SWITCH  the vm-bhyve switch the guests hang on
# @env     VM_BAKE_BUILDER  the builder guest's name
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_builder_conf_write1() {
	local g="$VM_BAKE_BUILDER" conf="$VM_BAKE_GUEST_DIR/$VM_BAKE_BUILDER/$VM_BAKE_BUILDER.conf" img="" t="" cur="" chain="" p="" n=0 a="" res=""
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$g/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r res < "$VM_BAKE_BASE/template/$a/resource"; done
	set -- "$1" ${res:-1 1G 0}
	printf '%s\n' "cat > '$conf' <<'EOF_CONF'"
	printf '%s\n' 'loader="uefi"' "cpu=$2" "memory=$3" 'network0_type="virtio-net"' "network0_switch=\"$VM_BAKE_GUEST_SWITCH\"" 'disk0_type="virtio-blk"' 'disk0_name="disk0.img"' 'disk1_type="virtio-blk"' "disk1_name=\"$VM_BAKE_IMAGE_DIR/$1/disk0.img\"" 'disk1_dev="custom"'
	printf '%s\n' "EOF_CONF"
	printf '%s\n' "printf '# builder %s: %s with disk1 %s\\n' '$g' '$conf' '$VM_BAKE_IMAGE_DIR/$1/disk0.img' >&2"
}

#@help _image_builder_wait0
# @command image builder wait
# @summary Act terminal: wait until the builder answers ssh (BatchMode, the host key accepted into .tmp/known_hosts.<builder>), two seconds between tries, 90 tries; then give up with an error
# @group   image
# @internal
# @see     image builder start
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the builder's sshd port
# @env     VM_BAKE_BUILDER  the builder guest's name
# @env     VM_BAKE_BUILDER_USER  the user ssh logs in as
# @env     VM_BAKE_BUILDER_ADDRESS  the builder's address
#@end
_image_builder_wait0() {
	local key="$VM_BAKE_HOST_KEY"
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	printf '%s\n' "n=0; until ssh -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$VM_BAKE_BUILDER' -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 -o BatchMode=yes '$VM_BAKE_BUILDER_USER@$VM_BAKE_BUILDER_ADDRESS' true 2>/dev/null; do n=\$((n + 1)); test \"\$n\" -lt 90 || { printf '# Error: builder %s at %s does not answer ssh\\n' '$VM_BAKE_BUILDER' '$VM_BAKE_BUILDER_ADDRESS' >&2; exit 1; }; sleep 2; done"
	printf '%s\n' "printf '# builder %s answers ssh after %s tries\\n' '$VM_BAKE_BUILDER' \"\$n\" >&2"
}

#@help _image_builder_shutdown0
# @command image builder shutdown
# @summary Act terminal: 'doas shutdown -p now' in the builder over ssh
# @group   image
# @internal
# @see     image builder stop
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the builder's sshd port
# @env     VM_BAKE_BUILDER  the builder guest's name
# @env     VM_BAKE_BUILDER_USER  the user ssh logs in as
# @env     VM_BAKE_BUILDER_ADDRESS  the builder's address
#@end
_image_builder_shutdown0() {
	local key="$VM_BAKE_HOST_KEY"
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	printf '%s\n' "ssh -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$VM_BAKE_BUILDER' -o StrictHostKeyChecking=accept-new -o BatchMode=yes '$VM_BAKE_BUILDER_USER@$VM_BAKE_BUILDER_ADDRESS' 'doas shutdown -p now' > /dev/null 2>&1; true"
	printf '%s\n' "printf '# builder %s: shutdown sent\\n' '$VM_BAKE_BUILDER' >&2"
}

#@help _image_builder_gone0
# @command image builder gone
# @summary Act terminal: wait until no bhyve process of the builder runs (pgrep), one second between looks, 120 looks; then an error
# @group   image
# @internal
# @see     image builder stop
# @env     VM_BAKE_BUILDER  the builder guest's name
#@end
_image_builder_gone0() {
	printf '%s\n' "n=0; while pgrep -q -f 'bhyve: $VM_BAKE_BUILDER\$'; do n=\$((n + 1)); test \"\$n\" -lt 120 || { printf '# Error: builder %s still runs\\n' '$VM_BAKE_BUILDER' >&2; exit 1; }; sleep 1; done"
	printf '%s\n' "printf '# builder %s is down\\n' '$VM_BAKE_BUILDER' >&2"
}

#@help _image_list0
# @command image list
# @summary List the image records (one line each): name, template, created, digest or 'open' while the bake is not closed
# @group   image
# @example vm-bake image list
# @see     image make freebsd
#@end
_image_list0() {
	local d="" t="" c="" g="" n=0
	printf '%s\n' "# images (name  template  created  digest)"
	for d in "$VM_BAKE_BASE"/image/*/; do
		test -f "$d/template" || continue
		IFS= read -r t < "$d/template"
		IFS= read -r c 2>/dev/null < "$d/created" || c=-
		IFS= read -r g 2>/dev/null < "$d/digest" || g=open
		printf '#   %-28s %-18s %-20s %s\n' "$(basename "$d")" "$t" "$c" "$g"
		n=$((n + 1))
	done
	test "$n" -gt 0 || printf '%s\n' "#   (none)"
}

#@help ___image_dump_all0
# @command image dump all
# @summary Every image record as replay lines, one 'image dump record' per record, no records a comment -- the dump's witness of what was baked (template, created, digest); the images themselves never travel, 'image make' bakes them anew
# @group   image
# @see     dump all
# @see     image dump record
#@end
___image_dump_all0() {
	local d="" n=0
	for d in "$VM_BAKE_BASE"/image/*/; do
		test -f "$d/template" || continue
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image dump record $(sq "$(basename "$d")")"
		n=$((n + 1))
	done
	test "$n" -gt 0 || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'no image records to dump'"
}

#@help ___image_dump_record1
# @command image dump record <image>
# @summary The replay line of one image record, a batch pinned to cat so it is shown rather than run: 'image record restore <image> <template> <created> <digest>', the digest 'open' while the bake was not closed
# @group   image
# @internal
# @see     image dump all
# @see     image record restore
#@end
___image_dump_record1() {
	local d="$VM_BAKE_BASE/image/$1" t="" c="" g=""
	IFS= read -r t 2>/dev/null < "$d/template" || t=-
	IFS= read -r c 2>/dev/null < "$d/created" || c=-
	IFS= read -r g 2>/dev/null < "$d/digest" || g=open
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record restore $(sq "$1") $(sq "$t") $(sq "$c") $(sq "$g")"
}

#@help ___image_record_restore4
# @command image record restore <image> <template> <created> <digest>
# @summary A record from a dump, the witness of an image baked elsewhere or before: the name valid; then 'image record compare' -- no record of that name here: placed; the same record: a comment; one that differs: an error. The record stands for an image that is NOT here (its dir is this host's VM_BAKE_IMAGE_DIR/<image>, empty until baked): 'image drop <image>' lets it go, 'image make <template> <image>' bakes it anew and the digest here says what it was
# @group   image
# @param   digest  the sha256 of the sealed image, or 'open' for a bake that was not closed
# @example vm-bake image record restore freebsd-dev-20261101 freebsd-dev 2026-11-01T12:42:19Z d98439466dc8fd0bb129ec224f6201e5c849f0edca9fc29f02414142718ff17f
# @see     image dump all
# @see     image record compare
# @see     image make freebsd
#@end
___image_record_restore4() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record compare $(sq "$1") $(sq "$2") $(sq "$3") $(sq "$4")"
}

#@help __image_record_compare4
# @command image record compare <image> <template> <created> <digest>
# @summary The record here against the one from the dump, read at generation: none -> 'image record place'; the same template, created and digest -> a comment line; a record that differs -> an error line (image drop <image> first, or keep yours)
# @group   image
# @internal
# @see     image record restore
# @see     image record place
#@end
__image_record_compare4() {
	local d="$VM_BAKE_BASE/image/$1" t="" c="" g=""
	IFS= read -r t 2>/dev/null < "$d/template" || t=""
	IFS= read -r c 2>/dev/null < "$d/created" || c=""
	IFS= read -r g 2>/dev/null < "$d/digest" || g=open
	if test ! -f "$d/template"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record place $(sq "$1") $(sq "$2") $(sq "$3") $(sq "$4")"
	elif test "$t" = "$2" && test "$c" = "$3" && test "$g" = "$4"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1: record identical, kept")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image record restore: $1 has a record here that differs (template $t, created $c, digest $g) -- image drop $1 first, or keep yours")"
	fi
}

#@help _image_record_place4
# @command image record place <image> <template> <created> <digest>
# @summary Act terminal: the record image/<image>/ written from a dump -- template, created and digest as given (no digest file for 'open'), dir as THIS host's VM_BAKE_IMAGE_DIR/<image>; 0700 and 0600
# @group   image
# @internal
# @env     VM_BAKE_IMAGE_DIR  the images' directory on this host
# @see     image record compare
# @see     image record write
#@end
_image_record_place4() {
	local rec="$VM_BAKE_BASE/image/$1"
	printf '%s\n' "$MODIFY_DIR_CREATE '$rec' && $MODIFY_FILE_PERMS 0700 '$rec'"
	printf '%s\n' "printf '%s\\n' $(sq "$2") > '$rec/template'"
	printf '%s\n' "printf '%s\\n' $(sq "$3") > '$rec/created'"
	printf '%s\n' "printf '%s\\n' $(sq "$VM_BAKE_IMAGE_DIR/$1") > '$rec/dir'"
	test "$4" = open || printf '%s\n' "printf '%s\\n' $(sq "$4") > '$rec/digest'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$rec'/*"
	emit_note "image $1: record restored (template $2, created $3, digest $4)"
}

#@help __image_make_linux1
# @internal arity-1 sibling of 'image make linux' (image make linux <image>  -- the full name img:<template>:<version>): rewrite to 'image make linux from <template> <version> <image>'
#@end
__image_make_linux1() {
	local t="${1#img:}"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make linux from $(sq "${t%%:*}") $(sq "${1##*:}") $(sq "$1")"
}

#@help __image_make_linux2
# @command image make linux <template> <version>
# @summary Bake a Linux image from the template under the version: the image is img:<template>:<version>, handed to 'image make linux from' -- a version is yours to choose (v1, v2, v20261107); two more spellings: the full name alone (image make linux img:<template>:<version>) and a name of its own (image make linux <template> <version> img:<name>:<version>)
# @group   image
# @param   version  the version field of the image name, a word of [A-Za-z0-9_.+-]
# @example vm-bake image make linux debian-dev v1
# @see     image make linux from
# @see     image list
#@end
__image_make_linux2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make linux from $(sq "$1") $(sq "$2") $(sq "img:$1:$2")"
}

#@help __image_make_linux3
# @internal arity-3 sibling of 'image make linux' (image make linux <template> <version> <image>  -- a name of its own): rewrite to 'image make linux from <template> <version> <image>'
#@end
__image_make_linux3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make linux from $(sq "$1") $(sq "$2") $(sq "$3")"
}

#@help ___image_make_linux_from3
# @command image make linux from <template> <version> <image>
# @summary The bake behind the three spellings of 'image make linux': the template exists, the image name is img:<name>:<version> and free; then 'image create cloud' (the distribution's cloud image as disk0.img), 'image firstboot' (the seed of the bake, one boot of the throwaway guest VM_BAKE_FIRSTBOOT in which cloud-init installs the packages and writes the configuration, then powers off), 'image close cloud' (the digest, nothing to unmount) and 'image seal' -- no builder and no chroot: a Linux disk is never mounted on the host
# @group   image
# @internal
# @see     image make linux
# @see     image create cloud
# @see     image firstboot
#@end
___image_make_linux_from3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image make linux: template $1, version $2 -> image $3 (create cloud, firstboot, close cloud, seal)")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image create cloud $(sq "$1") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image close cloud $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seal $(sq "$3")"
}

#@help __image_check_cloud1
# @command image check cloud <template>
# @summary The template's resolved base is of kind image and its resolved bake is cloud-init (both read at generation time): a comment line, else an error line -- a Linux bake boots the cloud image once and lets cloud-init work; a release base or a chroot bake has no first boot
# @group   image
# @internal
# @see     image create cloud
# @see     template bake cloud-init
#@end
__image_check_cloud1() {
	local cur="$1" chain="" p="" n=0 a="" base="" bake=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/bake" && IFS= read -r bake < "$VM_BAKE_BASE/template/$a/bake"; done
	if test "${base%% *}" = image && test "$bake" = cloud-init; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image: $1 is a cloud image baked by cloud-init")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create cloud: template $1 needs a base of kind image (has ${base:-none}) and the bake cloud-init (has ${bake:-none}): template base image, template bake cloud-init")"
	fi
}

#@help ___image_create_cloud2
# @command image create cloud <template> <image>
# @summary Step 1 of the Linux bake, the disk: the template exists with a resource, its base is a cloud image and its bake cloud-init, the image name is free; then the bake lock, the record, the dataset, the cloud image fetched into VM_BAKE_IMAGE_CACHE (once) and verified against the template's sha256, placed as disk0.img (raw copied, xz decompressed) and stretched to the resource's disk size -- no gpart and no growfs: cloud-init grows the root partition itself at the first boot (growpart)
# @group   image
# @internal
# @see     image make linux
# @see     image firstboot
# @env     VM_BAKE_IMAGE_DIR  where the image's dataset is created
#@end
___image_create_cloud2() {
	local cur="$1" chain="" p="" n=0 a="" size="" base=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r size < "$VM_BAKE_BASE/template/$a/resource"; done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	set -- "$1" "$2" $base
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check resource $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check cloud $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image lock take $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record write $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image dataset create $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image fetch $(sq "${6:-}")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image verify $(sq "${6:-}") $(sq "${7:-}")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk place $(sq "$2") $(sq "${6:-}") $(sq "${size##* }")"
}

#@help _image_disk_place3
# @command image disk place <image> <url> <size>
# @summary Act terminal: the cached cloud image as disk0.img -- a .raw or .img is copied, a .xz decompressed, any other suffix (qcow2, vmdk) is an error line at generation time: the host carries no qemu-img, take the distribution's raw image -- then the file stretched to the resource's size (sparse); an existing disk0.img is an error
# @group   image
# @internal
# @see     image create cloud
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_IMAGE_CACHE  the directory the cloud images are fetched into
#@end
_image_disk_place3() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img" f="$VM_BAKE_IMAGE_CACHE/${2##*/}"
	case "${2##*/}" in
		*.xz) printf '%s\n' "test ! -e '$img' || { printf '# Error: %s exists\\n' '$img' >&2; exit 1; }" "xz -dc '$f' > '$img' || exit 1" ;;
		*.raw|*.img) printf '%s\n' "test ! -e '$img' || { printf '# Error: %s exists\\n' '$img' >&2; exit 1; }" "cp '$f' '$img' || exit 1" ;;
		*) generate_error "image disk place: ${2##*/} is neither raw nor xz (qcow2 and vmdk need qemu-img, which the host does not carry; take the distribution's raw image)"; return 0 ;;
	esac
	printf '%s\n' "truncate -s $(sq "$3") '$img' || exit 1"
	emit_note "image $1: disk0.img from ${2##*/}, $3"
}

#@help ___image_firstboot1
# @command image firstboot <image>
# @summary Step 2 of the Linux bake, the first boot: the image has a record; then the seed of the bake written (image seed write), the throwaway guest VM_BAKE_FIRSTBOOT configured with the image's disk and the seed, linked where vm-bhyve looks, started, waited for until its bhyve process is gone (cloud-init powers the guest off when it is done), its link and configuration removed again -- the guest exists for this one boot
# @group   image
# @example vm-bake image firstboot img:debian-dev:v1
# @see     image make linux
# @see     image seed write
# @see     image firstboot conf
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name
#@end
___image_firstboot1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link write $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest run $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot gone"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link drop $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf drop"
}


#@help __image_firstboot_conf1
# @command image firstboot conf <image>
# @summary The throwaway guest's vm-bhyve configuration, by the bake of the image's template (read at generation time): rewrite to 'image firstboot conf cloud-init <image>' (the seed.iso as the CD) or 'image firstboot conf autoinstall <image>' (the site.iso as the CD; the install ISO comes with 'guest install'); both end in 'image firstboot conf write <image> <cd>'
# @group   image
# @internal
# @see     image firstboot
# @see     image install
#@end
__image_firstboot_conf1() {
	local t="" cur="" chain="" p="" n=0 a="" bake=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/bake" && IFS= read -r bake < "$VM_BAKE_BASE/template/$a/bake"; done
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf $(sq "${bake:-none}") $(sq "$1")"
}

#@help __image_firstboot_conf_cloud_init1
# @internal the cloud-init case of 'image firstboot conf <image>' (image firstboot conf cloud-init <image>): rewrite to 'image firstboot conf write <image> <seed.iso>'
#@end
__image_firstboot_conf_cloud_init1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf write $(sq "$1") $(sq "$VM_BAKE_IMAGE_DIR/$1/seed.iso")"
}

#@help __image_firstboot_conf_autoinstall1
# @internal the autoinstall case of 'image firstboot conf <image>' (image firstboot conf autoinstall <image>): rewrite to 'image firstboot conf write <image> <site.iso>' -- the install ISO is not in the configuration: 'guest install' hangs it on the first run only, so the reboot after the installation comes up from the disk
#@end
__image_firstboot_conf_autoinstall1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf write $(sq "$1") $(sq "$VM_BAKE_IMAGE_DIR/$1/site.iso")"
}

#@help __image_firstboot_conf2
# @internal dispatch fallback of 'image firstboot conf <bake> <image>' for a bake that is neither cloud-init nor autoinstall: an error line
#@end
__image_firstboot_conf2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image firstboot conf: the template of $2 bakes by $1, which has no first boot (cloud-init | autoinstall)")"
}

#@help _image_firstboot_conf_write2
# @command image firstboot conf write <image> <cd>
# @summary Act terminal (the invoking user: the directory is theirs): the throwaway guest's vm-bhyve configuration VM_BAKE_GUEST_DIR/<firstboot>/<firstboot>.conf -- UEFI, cpu and memory from the image's template (read at generation time), the switch, the MAC of VM_BAKE_FIRSTBOOT_ADDRESS, the image's disk0.img as disk0 (custom path) and <cd> as disk1 (ahci-cd: the seed.iso of a cloud-init bake, the site.iso of an autoinstall bake), bhyve_options -w (bhyve ignores the MSRs a guest kernel touches and bhyve does not implement -- OpenBSD's kernel dies without it, Linux does not mind); no dataset and no clone: the guest boots the image itself, once
# @group   image
# @internal
# @completion cd files
# @see     image firstboot
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_GUEST_SWITCH  the vm-bhyve switch the guests hang on
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name
# @env     VM_BAKE_FIRSTBOOT_ADDRESS  the throwaway guest's address, the MAC is derived from it
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_firstboot_conf_write2() {
	local g="$VM_BAKE_FIRSTBOOT" conf="$VM_BAKE_GUEST_DIR/$VM_BAKE_FIRSTBOOT/$VM_BAKE_FIRSTBOOT.conf" t="" cur="" chain="" p="" n=0 a="" res="" cd="$2"
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r res < "$VM_BAKE_BASE/template/$a/resource"; done
	set -- "$1" ${res:-1 1G 0} "$(printf '%s' "${VM_BAKE_FIRSTBOOT_ADDRESS%/*}" | awk -F. '{ printf "58:9c:fc:%02x:%02x:%02x", $2, $3, $4 }')"
	printf '%s\n' "install -d -m 755 '$VM_BAKE_GUEST_DIR/$g' && cat > '$conf' <<'EOF_CONF'"
	printf '%s\n' 'loader="uefi"' "cpu=$2" "memory=$3" 'network0_type="virtio-net"' "network0_switch=\"$VM_BAKE_GUEST_SWITCH\"" "network0_mac=\"$5\"" 'disk0_type="virtio-blk"' "disk0_name=\"$VM_BAKE_IMAGE_DIR/$1/disk0.img\"" 'disk0_dev="custom"' 'disk1_type="ahci-cd"' "disk1_name=\"$cd\"" 'disk1_dev="custom"' 'bhyve_options="-w"' 'debug="yes"'
	printf '%s\n' "EOF_CONF"
	printf '%s\n' "printf '# firstboot %s: %s boots %s with %s\\n' '$g' '$conf' '$VM_BAKE_IMAGE_DIR/$1/disk0.img' '$cd' >&2"
}

#@help _image_firstboot_gone0
# @command image firstboot gone
# @summary Act terminal: the first boot waited out -- 'vm start' returns before bhyve runs, so first the wait until the throwaway guest is up (vm-bhyve's run.lock or its bhyve process, one second between looks, 60 looks), then the wait until both are gone (two seconds between looks, 1800 looks -- an hour, apt has to download the packages); each wait ends in an error when its looks are spent
# @group   image
# @internal
# @see     image firstboot
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name
# @env     VM_BAKE_GUEST_DIR  vm-bhyve's vm_dir, where the guest's run.lock lies
#@end
_image_firstboot_gone0() {
	local lock="$VM_BAKE_GUEST_DIR/$VM_BAKE_FIRSTBOOT/run.lock" up="test -e '$VM_BAKE_GUEST_DIR/$VM_BAKE_FIRSTBOOT/run.lock' || pgrep -q -f 'bhyve: $VM_BAKE_FIRSTBOOT\$'"
	printf '%s\n' "n=0; until $up; do n=\$((n + 1)); test \"\$n\" -lt 60 || { printf '# Error: firstboot %s did not come up within a minute (no %s, no bhyve)\\n' '$VM_BAKE_FIRSTBOOT' '$lock' >&2; exit 1; }; sleep 1; done"
	printf '%s\n' "printf '# firstboot %s is up after %s looks\\n' '$VM_BAKE_FIRSTBOOT' \"\$n\" >&2"
	printf '%s\n' "n=0; while $up; do n=\$((n + 1)); test \"\$n\" -lt 1800 || { printf '# Error: firstboot %s still runs after an hour\\n' '$VM_BAKE_FIRSTBOOT' >&2; exit 1; }; sleep 2; done"
	printf '%s\n' "printf '# firstboot %s is down after %s looks\\n' '$VM_BAKE_FIRSTBOOT' \"\$n\" >&2"
}

#@help _image_firstboot_conf_drop0
# @command image firstboot conf drop
# @summary Act terminal: the throwaway guest's directory under VM_BAKE_GUEST_DIR removed with its configuration and vm-bhyve's log -- when the configuration is there; nothing there is a note
# @group   image
# @internal
# @see     image firstboot
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name
#@end
_image_firstboot_conf_drop0() {
	local dir="$VM_BAKE_GUEST_DIR/$VM_BAKE_FIRSTBOOT"
	printf '%s\n' "test -f '$dir/$VM_BAKE_FIRSTBOOT.conf' && rm -rf '$dir' && printf '# firstboot %s: %s removed\\n' '$VM_BAKE_FIRSTBOOT' '$dir' >&2 || printf '# firstboot %s: nothing under %s\\n' '$VM_BAKE_FIRSTBOOT' '$dir' >&2"
}

#@help ___image_close_cloud1
# @command image close cloud <image>
# @summary Step 3 of the Linux bake, the disk closed: the image has a record; then the sha256 of disk0.img written beside it and into the record -- nothing was mounted, the first boot wrote the disk from inside
# @group   image
# @internal
# @see     image make linux
# @see     image seal
#@end
___image_close_cloud1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image digest write $(sq "$1")"
}

#@help __image_make_openbsd1
# @internal arity-1 sibling of 'image make openbsd' (image make openbsd <image>  -- the full name img:<template>:<version>): rewrite to 'image make openbsd from <template> <version> <image>'
#@end
__image_make_openbsd1() {
	local t="${1#img:}"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make openbsd from $(sq "${t%%:*}") $(sq "${1##*:}") $(sq "$1")"
}

#@help __image_make_openbsd2
# @command image make openbsd <template> <version>
# @summary Bake an OpenBSD image from the template under the version: the image is img:<template>:<version>, handed to 'image make openbsd from' -- the same three spellings as 'image make linux' (the full name alone, or a name of its own as third word)
# @group   image
# @param   version  the version field of the image name, a word of [A-Za-z0-9_.+-]
# @example vm-bake image make openbsd openbsd-dev v1
# @see     image make openbsd from
# @see     image make linux
# @see     image list
#@end
__image_make_openbsd2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make openbsd from $(sq "$1") $(sq "$2") $(sq "img:$1:$2")"
}

#@help __image_make_openbsd3
# @internal arity-3 sibling of 'image make openbsd' (image make openbsd <template> <version> <image>  -- a name of its own): rewrite to 'image make openbsd from <template> <version> <image>'
#@end
__image_make_openbsd3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make openbsd from $(sq "$1") $(sq "$2") $(sq "$3")"
}

#@help ___image_make_openbsd_from3
# @command image make openbsd from <template> <version> <image>
# @summary The bake behind the three spellings of 'image make openbsd': the template exists, the image name is img:<name>:<version> and free; then 'image create iso' (an empty disk0.img of the resource's size), 'image install' (the response file and the site set of the template as site.iso, one run of the throwaway guest VM_BAKE_FIRSTBOOT from the install ISO, its console driven into autoinstall(8); the installed system boots once more, adds the packages and powers off), 'image close iso' (the digest) and 'image seal' -- no builder and no chroot: an OpenBSD disk is never mounted on the host
# @group   image
# @internal
# @see     image make openbsd
# @see     image create iso
# @see     image install
#@end
___image_make_openbsd_from3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image make openbsd: template $1, version $2 -> image $3 (create iso, install, close iso, seal)")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image create iso $(sq "$1") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image install $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image close iso $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seal $(sq "$3")"
}

#@help __image_check_autoinstall1
# @command image check autoinstall <template>
# @summary The template's resolved base is of kind iso, its file is named install<NN>.iso (the release NN and the set directory are read from that name) and readable, and its resolved bake is autoinstall (all read at generation time): a comment line, else an error line
# @group   image
# @internal
# @see     image create iso
# @see     template base iso
# @see     template bake autoinstall
#@end
__image_check_autoinstall1() {
	local cur="$1" chain="" p="" n=0 a="" base="" bake="" kind="" path="" f=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/bake" && IFS= read -r bake < "$VM_BAKE_BASE/template/$a/bake"; done
	kind=${base%% *}; path=$(printf '%s' "$base" | awk '{ print $3 }'); f=${path##*/}
	case "$f" in install[0-9][0-9].iso) ;; *) f="" ;; esac
	if test "$kind" = iso && test "$bake" = autoinstall && test -n "$f" && test -r "$path"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image: $1 installs from $path by autoinstall")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create iso: template $1 needs a readable base of kind iso named install<NN>.iso (has ${base:-none}) and the bake autoinstall (has ${bake:-none}): template base iso, template bake autoinstall")"
	fi
}

#@help ___image_create_iso2
# @command image create iso <template> <image>
# @summary Step 1 of the OpenBSD bake, the disk: the template exists with a resource, its base is an install ISO and its bake autoinstall, the image name is free; then the bake lock, the record, the dataset and an empty disk0.img of the resource's disk size (image disk create) -- the installer partitions and fills it
# @group   image
# @internal
# @see     image make openbsd
# @see     image install
# @env     VM_BAKE_IMAGE_DIR  where the image's dataset is created
#@end
___image_create_iso2() {
	local cur="$1" chain="" p="" n=0 a="" size=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r size < "$VM_BAKE_BASE/template/$a/resource"; done
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check resource $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check autoinstall $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image lock take $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record write $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image dataset create $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk create $(sq "$2") $(sq "${size##* }")"
}

#@help ___image_install1
# @command image install <image>
# @summary Step 2 of the OpenBSD bake, the installation: the image has a record; then the response file (image response write) and the site set (image site write) rendered from the template and packed as site.iso (image site pack), the throwaway guest VM_BAKE_FIRSTBOOT configured with the image's disk and the site.iso (image firstboot conf), linked where vm-bhyve looks, run from the template's install ISO (guest install: the ISO rides along for this one run), its console typed into autoinstall(8) (image console drive), waited for until bhyve is gone (the installer reboots, the installed system adds the packages and powers off), its link and configuration removed again
# @group   image
# @example vm-bake image install img:openbsd-dev:v1
# @see     image make openbsd
# @see     image response write
# @see     image site write
# @see     image console drive
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name
#@end
___image_install1() {
	local t="" cur="" chain="" p="" n=0 a="" base="" iso=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	iso=$(printf '%s' "$base" | awk '{ print $3 }')
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image response write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site pack $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link write $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest install $(sq "$VM_BAKE_FIRSTBOOT") $(sq "$iso")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image console drive $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot gone"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link drop $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf drop"
}

#@help _image_response_write1
# @command image response write <image>
# @summary Act terminal: the response file of autoinstall(8), VM_BAKE_IMAGE_DIR/<image>/site/install.conf -- hostname VM_BAKE_FIRSTBOOT, vio0 static on VM_BAKE_FIRSTBOOT_ADDRESS, route and nameserver VM_BAKE_GUEST_GATEWAY, domain VM_BAKE_GUEST_DOMAIN, root with a throwaway password (install.site locks it) and no key, sshd on, no root login, the X sets only when the template says 'service display x', com0 at 115200, no user (install.site makes the template's users with their host uids), the host's timezone (/var/db/zoneinfo, else UTC), sd0 whole-disk GPT with the auto layout; the sets from the install CD, then the site set from the site CD -- the installer numbers the CDs, so the console driver fills in @INSTCD@ and @SITECD@ when it copies the file. The template is read at generation time
# @group   image
# @internal
# @see     image install
# @see     image site write
# @see     image console drive
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, the hostname of the installation
# @env     VM_BAKE_FIRSTBOOT_ADDRESS  the installation's address, with prefix length
# @env     VM_BAKE_GUEST_GATEWAY  route and nameserver of the installation
# @env     VM_BAKE_GUEST_DOMAIN  its DNS domain
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_response_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 a="" base="" svc="" x=no nn="" rel="" arch="" mask="" tz=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	svc=$(awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "$svc" | grep -qx 'display x' && x=yes
	arch=$(printf '%s' "$base" | awk '{ print $2 }'); nn=$(printf '%s' "$base" | awk '{ print $3 }'); nn=${nn##*/install}; nn=${nn%.iso}; rel="${nn%?}.${nn#?}"
	mask=$(printf '%s\n' "${VM_BAKE_FIRSTBOOT_ADDRESS#*/}" | awk '{ m = $1 ? 4294967296 - 2 ^ (32 - $1) : 0; printf "%d.%d.%d.%d", int(m / 16777216) % 256, int(m / 65536) % 256, int(m / 256) % 256, m % 256 }')
	IFS= read -r tz 2>/dev/null < /var/db/zoneinfo || tz=UTC
	printf '%s\n' "install -d -m 700 '$dir/site/$rel/$arch' || exit 1"
	printf '%s\n' "cat > '$dir/site/install.conf' <<'EOF_RESPONSE'"
	printf '%s\n' "System hostname = $VM_BAKE_FIRSTBOOT" "Which network interface do you wish to configure = vio0" "IPv4 address for vio0 = ${VM_BAKE_FIRSTBOOT_ADDRESS%/*}" "Netmask for vio0 = $mask" "IPv6 address for vio0 = none" "Which network interface do you wish to configure = done" "Default IPv4 route = $VM_BAKE_GUEST_GATEWAY" "DNS domain name = $VM_BAKE_GUEST_DOMAIN" "DNS nameservers = $VM_BAKE_GUEST_GATEWAY" "Password for root account = *************" "Public ssh key for root account = none" "Start sshd(8) by default = yes" "Do you expect to run the X Window System = $x" "Change the default console to com0 = yes" "Which speed should com0 use = 115200" "Setup a user = no" "Allow root ssh login = no" "What timezone are you in = $tz" "Which disk is the root disk = sd0" "Encrypt the root disk with a passphrase = no" "Encrypt the root disk with a (p)assphrase or (k)eydisk = no" "Use (W)hole disk MBR, whole disk (G)PT or (E)dit = gpt" "Use (A)uto layout, (E)dit auto layout, or create (C)ustom layout = a" "Location of sets = @INSTCD@" "Pathname to the sets = $rel/$arch/"
	test "$x" = yes || printf '%s\n' "Set name(s) = -x*"
	printf '%s\n' "Set name(s) = done" "Location of sets = @SITECD@" "Pathname to the sets = $rel/$arch/" "Set name(s) = site$nn.tgz" "Set name(s) = done" "Directory does not contain SHA256.sig. Continue without verification = yes" "Location of sets = done"
	printf '%s\n' "EOF_RESPONSE"
	printf '%s\n' "printf '# image %s: install.conf -- %s on %s netmask %s, sets %s/%s from the install CD and site%s.tgz from the site CD, X %s, timezone %s\\n' $(sq "$1") '$VM_BAKE_FIRSTBOOT' '${VM_BAKE_FIRSTBOOT_ADDRESS%/*}' '$mask' '$rel' '$arch' '$nn' '$x' '$tz' >&2"
}

#@help _image_site_write1
# @command image site write <image>
# @summary Act terminal: the site set's one file, VM_BAKE_IMAGE_DIR/<image>/site.d/install.site, which autoinstall(8) runs chrooted in the installed system at the end -- sshd on VM_BAKE_SSH_PORT without root or passwords, AuthorizedKeysFile /etc/ssh/authorized_keys/%u before the home, X11Forwarding when the template says 'service display x'; the template's users with their host uids in wheel, each with VM_BAKE_HOST_KEY as authorized key; /etc/doas.conf permitting them without a password when the template's packages name doas (doas is in OpenBSD's base: the word switches the escalation on and is not handed to pkg_add); the env lines appended to /etc/profile; /etc/installurl; root's password locked; the address and netmask of the bake under /etc/vm-bake and /usr/local/libexec/vm-bake-seed as the only line of /etc/hostname.vio0 (at every boot it mounts a seed CD when there is one -- guest seed write autoinstall -- and names, addresses and keys the guest, else addresses the bake); /etc/rc.firsttime extended by pkg_add of the packages and the power-off. The template is read at generation time
# @group   image
# @internal
# @see     image install
# @see     image site pack
# @see     guest seed write autoinstall
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_HOST_KEY  the public key file; a leading ~/ is the invoking user's home
# @env     VM_BAKE_SSH_PORT  the port sshd listens on in every guest of this image
# @env     VM_BAKE_FIRSTBOOT_ADDRESS  the bake's address, the fallback of the seed script
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_site_write1() {
	local name="$1" dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 pkgs="" users="" envl="" svc="" key="$VM_BAKE_HOST_KEY" keytext="" line="" u="" s="" uid="" doas=no x11=no mask=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	pkgs=$(awk -v base="$VM_BAKE_BASE" -v family=package -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	envl=$(awk -v base="$VM_BAKE_BASE" -v family=env -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | sed 's/^\([^=]*\)=\(.*\)$/export \1="\2"/')
	svc=$(awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "$pkgs" | grep -qx doas && doas=yes
	pkgs=$(printf '%s\n' "$pkgs" | grep -vx doas || true)
	printf '%s\n' "$svc" | grep -qx 'display x' && x11=yes
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	keytext=$(cat "$key" 2>/dev/null || true)
	mask=$(printf '%s\n' "${VM_BAKE_FIRSTBOOT_ADDRESS#*/}" | awk '{ m = $1 ? 4294967296 - 2 ^ (32 - $1) : 0; printf "%d.%d.%d.%d", int(m / 16777216) % 256, int(m / 65536) % 256, int(m / 256) % 256, m % 256 }')
	printf '%s\n' "install -d -m 700 '$dir/site.d' || exit 1"
	printf '%s\n' "cat > '$dir/site.d/install.site' <<'EOF_SITE'"
	printf '%s\n' '#!/bin/sh' '# written by vm-bake (image site write) -- run by autoinstall(8), chrooted in the installed system' 'set -e'
	printf '%s\n' 'install -d -m 755 /etc/ssh/authorized_keys /etc/vm-bake /usr/local/libexec'
	printf '%s\n' "cat >> /etc/ssh/sshd_config <<'EOF_SSHD'" "Port $VM_BAKE_SSH_PORT" "PermitRootLogin no" "PasswordAuthentication no" "KbdInteractiveAuthentication no" "AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys"
	test "$x11" = no || printf '%s\n' "X11Forwarding yes"
	printf '%s\n' "EOF_SSHD"
	if test -n "$users"; then
		IFS='
'; set -- $users; IFS='
'
		for line; do
			u=${line%% *}; s=${line#* }; uid=$s
			test "$s" != host || uid=$(id -u "$u" 2>/dev/null || true)
			printf '%s\n' "useradd -m${uid:+ -u $uid} -G wheel -s /bin/ksh '$u'"
			printf '%s\n' "printf '%s\\n' '$keytext' > '/etc/ssh/authorized_keys/$u' && chmod 644 '/etc/ssh/authorized_keys/$u'"
		done
		if test "$doas" = yes; then
			printf '%s\n' "cat > /etc/doas.conf <<'EOF_DOAS'"
			for line; do printf '%s\n' "permit nopass keepenv ${line%% *} as root"; done
			printf '%s\n' "EOF_DOAS" "chmod 600 /etc/doas.conf"
		fi
	fi
	if test -n "$envl"; then
		printf '%s\n' "cat >> /etc/profile <<'EOF_ENV'" "# written by vm-bake (template env) -- the sessions' environment"
		printf '%s\n' "$envl"
		printf '%s\n' "EOF_ENV"
	fi
	printf '%s\n' "printf '%s\\n' 'https://cdn.openbsd.org/pub/OpenBSD' > /etc/installurl"
	printf '%s\n' "usermod -p '*' root"
	printf '%s\n' "printf '%s\\n' '${VM_BAKE_FIRSTBOOT_ADDRESS%/*}' > /etc/vm-bake/address" "printf '%s\\n' '$mask' > /etc/vm-bake/netmask"
	printf '%s\n' "cat > /usr/local/libexec/vm-bake-seed <<'EOF_SEED'" '#!/bin/sh' "# written by vm-bake (image site write) -- the one line of /etc/hostname.vio0: a seed CD (guest seed write autoinstall) names, addresses and keys this guest; without one, the address of the bake" 'a=$(cat /etc/vm-bake/address) m=$(cat /etc/vm-bake/netmask)' 'for c in cd0 cd1; do' '	mount -r -t cd9660 /dev/${c}a /mnt 2>/dev/null || continue' '	if test -f /mnt/vm-bake-seed; then' '		a=$(cat /mnt/address) m=$(cat /mnt/netmask)' '		cp /mnt/myname /mnt/mygate /mnt/resolv.conf /etc/' '		install -m 600 /mnt/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key' '		install -m 644 /mnt/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub' '		hostname "$(cat /etc/myname)"' '	fi' '	umount /mnt' 'done' 'ifconfig vio0 inet "$a" netmask "$m" up' "EOF_SEED"
	printf '%s\n' "chmod 755 /usr/local/libexec/vm-bake-seed" "printf '%s\\n' '!/usr/local/libexec/vm-bake-seed' > /etc/hostname.vio0"
	printf '%s\n' "cat >> /etc/rc.firsttime <<'EOF_FIRST'" "# written by vm-bake (image site write) -- the bake's first boot: the packages, then power off; the host seals the disk"
	test -z "$pkgs" || printf '%s\n' "pkg_add -I $(printf '%s\n' "$pkgs" | tr '\n' ' ')2>&1 | tee /dev/console"
	printf '%s\n' "pkg_info -q > /etc/vm-bake/packages" "shutdown -p now" "EOF_FIRST"
	printf '%s\n' "EOF_SITE"
	printf '%s\n' "chmod 755 '$dir/site.d/install.site'"
	printf '%s\n' "printf '# image %s: install.site -- sshd on %s, users %s, doas %s, X11 %s, %s packages at the first boot\\n' $(sq "$name") '$VM_BAKE_SSH_PORT' $(sq "$(printf '%s\n' "$users" | awk '{ print $1 }' | tr '\n' ' ' | sed 's/ $//')") '$doas' '$x11' '$(printf '%s\n' "$pkgs" | grep -c . || true)' >&2"
}

#@help _image_site_pack1
# @command image site pack <image>
# @summary Act terminal: install.site packed as the site set VM_BAKE_IMAGE_DIR/<image>/site/<release>/<arch>/site<NN>.tgz (bsdtar, owned by root:wheel) with its SHA256 beside it, then the site directory -- install.conf at its root, the set under the release directory the installer expects -- becomes site.iso (makefs cd9660, rockridge, label vmbakesite), the CD the throwaway guest carries besides the install ISO
# @group   image
# @internal
# @see     image install
# @see     image site write
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_site_pack1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 a="" base="" nn="" rel="" arch=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	arch=$(printf '%s' "$base" | awk '{ print $2 }'); nn=$(printf '%s' "$base" | awk '{ print $3 }'); nn=${nn##*/install}; nn=${nn%.iso}; rel="${nn%?}.${nn#?}"
	printf '%s\n' "bsdtar -czf '$dir/site/$rel/$arch/site$nn.tgz' --uid 0 --gid 0 --uname root --gname wheel -C '$dir/site.d' install.site || exit 1"
	printf '%s\n' "(cd '$dir/site/$rel/$arch' && sha256 site$nn.tgz > SHA256) || exit 1"
	printf '%s\n' "rm -f '$dir/site.iso' && makefs -t cd9660 -o rockridge -o label=vmbakesite '$dir/site.iso' '$dir/site' && chmod 600 '$dir/site.iso' || exit 1"
	printf '%s\n' "printf '# image %s: site.iso -- install.conf and %s/%s/site%s.tgz\\n' $(sq "$1") '$rel' '$arch' '$nn' >&2"
}

#@help __image_console_drive1
# @command image console drive <image>
# @summary The throwaway guest's serial console typed into autoinstall(8), by VM_BAKE_CONSOLE (the way vm-bhyve offers consoles): rewrite to 'image console drive tmux <image>' or 'image console drive nmdm <image>'
# @group   image
# @internal
# @see     image install
# @env     VM_BAKE_CONSOLE  tmux or nmdm, vm-bhyve's console= setting
#@end
__image_console_drive1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image console drive $(sq "$VM_BAKE_CONSOLE") $(sq "$1")"
}

#@help __image_console_drive2
# @internal dispatch fallback of 'image console drive <console> <image>' for a console that is neither tmux nor nmdm: an error line
#@end
__image_console_drive2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image console drive: VM_BAKE_CONSOLE is $1, which is no console of vm-bhyve (tmux | nmdm)")"
}

#@help _image_console_drive_tmux1
# @command image console drive tmux <image>
# @summary Act terminal (root): the installer of the throwaway guest answered over vm-bhyve's tmux session (capture-pane reads, send-keys types) -- the loader told to use com0 and to boot; the installer sent into its shell, where it mounts the two CDs, finds install.conf on the site CD, writes it as /auto_install.conf with the CD names filled in (@INSTCD@, @SITECD@) and leaves the shell; then (A)utoinstall, which takes the local file; the act returns when the installer reports CONGRATULATIONS and reboots -- what follows is the first boot, waited for by 'image firstboot gone'. Every wait has its seconds and ends in an error with the last screen and the guest powered off (vm poweroff -f): a guest whose install went wrong sits in vm-bhyve's restart loop otherwise, and the next 'guest install' would find it running
# @group   image
# @internal
# @see     image console drive
# @see     image response write
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, the tmux session
#@end
_image_console_drive_tmux1() {
	printf '%s\n' "g=$(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' 'pane() { tmux capture-pane -p -t "$g" 2>/dev/null || true; }'
	printf '%s\n' 'send() { tmux send-keys -t "$g" "$1" Enter; }'
	printf '%s\n' 'n=0; until tmux has-session -t "$g" 2>/dev/null; do n=$((n + 1)); test "$n" -lt 60 || { printf "# Error: console %s: no tmux session within a minute (VM_BAKE_CONSOLE says tmux; vm-bhyve console= in system.conf?)\n" "$g" >&2; exit 1; }; sleep 1; done'
	cat <<'EOF_STEPS'
give_up() { printf '# Error: console %s: %s\n' "$g" "$1" >&2; pane | tail -15 >&2; vm poweroff -f "$g" >/dev/null 2>&1; printf '# console %s: powered off\n' "$g" >&2; exit 1; }
wait_for() { n=0; until pane | grep -q -- "$1"; do n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 within $2 s"; sleep 1; done; }
wait_last() { n=0; until pane | grep . | tail -1 | grep -q -- "$1"; do n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 as last line within $2 s"; sleep 1; done; }
wait_for 'boot>' 120
send 'set tty com0'; sleep 1; send 'boot'
wait_for '(I)nstall, (U)pgrade, (A)utoinstall or (S)hell?' 300
send 's'; sleep 2
send 'cd /dev && sh MAKEDEV cd0 cd1; cd /'
send 's=; for d in cd0 cd1; do mount_cd9660 /dev/${d}a /mnt 2>/dev/null || continue; test -f /mnt/install.conf && s=$d; umount /mnt; done'
send 'case $s in cd0) i=cd1 ;; *) i=cd0 ;; esac; mount_cd9660 /dev/${s}a /mnt && sed "s/@INSTCD@/$i/;s/@SITECD@/$s/" /mnt/install.conf > /auto_install.conf && umount /mnt && echo "response file from $s, sets from $i"'
wait_for 'response file from cd' 30
send 'exit'
wait_last '(S)hell?' 60
send 'a'
wait_for 'CONGRATULATIONS' 1800
printf '# console %s: installed, the guest reboots into its first boot\n' "$g" >&2
EOF_STEPS
}

#@help _image_console_drive_nmdm1
# @command image console drive nmdm <image>
# @summary Act terminal (root): the same dialogue as 'image console drive tmux', over vm-bhyve's nmdm pair -- /dev/nmdm-<firstboot>.1B is opened once on descriptor 3 and put into raw mode without echo (a freshly opened tty has echo and canonical mode, which sends every byte the guest prints back into the guest as keystrokes and turns each line end into an Enter -- the loader then shows prompt after prompt; the settings hold as long as the descriptor stays open), read into VM_BAKE_GUEST_DIR/<firstboot>/console.log by a cat in the background (the last forty lines stand for the screen) and written with a carriage return per line; the device appears when bhyve runs, waited for a minute
# @group   image
# @internal
# @see     image console drive
# @see     image console drive tmux
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, in the device name
# @env     VM_BAKE_GUEST_DIR  the guests' directory, where the console log lies
#@end
_image_console_drive_nmdm1() {
	printf '%s\n' "g=$(sq "$VM_BAKE_FIRSTBOOT") dev=$(sq "/dev/nmdm-$VM_BAKE_FIRSTBOOT.1B") log=$(sq "$VM_BAKE_GUEST_DIR/$VM_BAKE_FIRSTBOOT/console.log")"
	printf '%s\n' 'n=0; until test -c "$dev"; do n=$((n + 1)); test "$n" -lt 60 || { printf "# Error: console %s: no %s within a minute (VM_BAKE_CONSOLE says nmdm; vm-bhyve console= in system.conf?)\n" "$g" "$dev" >&2; exit 1; }; sleep 1; done'
	printf '%s\n' 'exec 3<> "$dev"; stty raw -echo <&3'
	printf '%s\n' ': > "$log"; cat <&3 >> "$log" & rd=$!' 'trap '"'"'kill "$rd" 2>/dev/null'"'"' EXIT'
	printf '%s\n' 'pane() { tail -n 40 "$log" 2>/dev/null | tr -d "\r"; }'
	printf '%s\n' 'send() { printf "%s\r" "$1" >&3; }'
	cat <<'EOF_STEPS'
give_up() { printf '# Error: console %s: %s\n' "$g" "$1" >&2; pane | tail -15 >&2; vm poweroff -f "$g" >/dev/null 2>&1; printf '# console %s: powered off\n' "$g" >&2; exit 1; }
wait_for() { n=0; until pane | grep -q -- "$1"; do n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 within $2 s"; sleep 1; done; }
wait_last() { n=0; until pane | grep . | tail -1 | grep -q -- "$1"; do n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 as last line within $2 s"; sleep 1; done; }
wait_for 'boot>' 120
send 'set tty com0'; sleep 1; send 'boot'
wait_for '(I)nstall, (U)pgrade, (A)utoinstall or (S)hell?' 300
send 's'; sleep 2
send 'cd /dev && sh MAKEDEV cd0 cd1; cd /'
send 's=; for d in cd0 cd1; do mount_cd9660 /dev/${d}a /mnt 2>/dev/null || continue; test -f /mnt/install.conf && s=$d; umount /mnt; done'
send 'case $s in cd0) i=cd1 ;; *) i=cd0 ;; esac; mount_cd9660 /dev/${s}a /mnt && sed "s/@INSTCD@/$i/;s/@SITECD@/$s/" /mnt/install.conf > /auto_install.conf && umount /mnt && echo "response file from $s, sets from $i"'
wait_for 'response file from cd' 30
send 'exit'
wait_last '(S)hell?' 60
send 'a'
wait_for 'CONGRATULATIONS' 1800
printf '# console %s: installed, the guest reboots into its first boot\n' "$g" >&2
EOF_STEPS
}

#@help ___image_close_iso1
# @command image close iso <image>
# @summary Step 3 of the OpenBSD bake, the disk closed: the image has a record; then the sha256 of disk0.img written beside it and into the record -- nothing was mounted, the installer and the first boot wrote the disk from inside
# @group   image
# @internal
# @see     image make openbsd
# @see     image seal
#@end
___image_close_iso1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image digest write $(sq "$1")"
}


#@help _image_seed_meta_write1
# @command image seed meta write <image>
# @summary Act terminal: the seed directory VM_BAKE_IMAGE_DIR/<image>/seed (0700) and its meta-data -- instance-id bake-<image>, local-hostname VM_BAKE_FIRSTBOOT, the name of the throwaway guest that boots the image once
# @group   image
# @internal
# @see     image seed write
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, the hostname of the first boot
#@end
_image_seed_meta_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "install -d -m 700 '$dir/seed' || exit 1"
	printf '%s\n' "cat > '$dir/seed/meta-data' <<'EOF_META'"
	printf '%s\n' "instance-id: bake-$1" "local-hostname: $VM_BAKE_FIRSTBOOT"
	printf '%s\n' "EOF_META"
}

#@help _image_seed_net_write1
# @command image seed net write <image>
# @summary Act terminal: the seed's network-config (v2) for the first boot -- the interface matched by the MAC 58:9c:fc:<octets 2-4 of VM_BAKE_FIRSTBOOT_ADDRESS>, that address static, the default route and the nameserver VM_BAKE_GUEST_GATEWAY. Without it cloud-init asks DHCP, the switch has none, and apt resolves nothing: the packages of the template would stay uninstalled
# @group   image
# @internal
# @see     image seed write
# @see     image firstboot conf write
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_FIRSTBOOT_ADDRESS  the throwaway guest's address with prefix length
# @env     VM_BAKE_GUEST_GATEWAY  gateway and nameserver of the guests' switch
#@end
_image_seed_net_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" addr="$VM_BAKE_FIRSTBOOT_ADDRESS" mac=""
	mac=$(printf '%s' "${addr%/*}" | awk -F. '{ printf "58:9c:fc:%02x:%02x:%02x", $2, $3, $4 }')
	printf '%s\n' "cat > '$dir/seed/network-config' <<'EOF_NET'"
	printf '%s\n' "version: 2" "ethernets:" "  net0:" "    match:" "      macaddress: '$mac'" "    set-name: net0" "    dhcp4: false" "    addresses:" "      - $addr" "    routes:" "      - to: default" "        via: $VM_BAKE_GUEST_GATEWAY" "    nameservers:" "      addresses:" "        - $VM_BAKE_GUEST_GATEWAY"
	printf '%s\n' "EOF_NET"
	printf '%s\n' "printf '# image %s: first boot on %s (%s), gateway %s\\n' '$1' '$addr' '$mac' '$VM_BAKE_GUEST_GATEWAY' >&2"
}

#@help _image_seed_user_write1
# @command image seed user write <image>
# @summary Act terminal: user-data begins -- '#cloud-config', root disabled, no password login, the package index refreshed; the template's packages; its users (uid host is the uid of that user on this host) with bash, a locked password and the public key VM_BAKE_HOST_KEY as authorized key, with passwordless sudo when sudo is among the packages. The template is read at generation time
# @group   image
# @internal
# @see     image seed write
# @see     image user make
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_HOST_KEY  the public key file; a leading ~/ is the invoking user's home
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_seed_user_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 pkgs="" users="" key="$VM_BAKE_HOST_KEY" keytext="" line="" u="" s="" uid="" sudo=no
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	pkgs=$(awk -v base="$VM_BAKE_BASE" -v family=package -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "$pkgs" | grep -qx sudo && sudo=yes
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	keytext=$(cat "$key" 2>/dev/null || true)
	printf '%s\n' "cat > '$dir/seed/user-data' <<'EOF_USER'"
	printf '%s\n' "#cloud-config" "disable_root: true" "ssh_pwauth: false" "package_update: true" "package_upgrade: false"
	if test -n "$pkgs"; then
		printf '%s\n' "packages:"
		printf '%s\n' "$pkgs" | sed 's/^/  - /'
	fi
	if test -n "$users"; then
		printf '%s\n' "users:"
		IFS='
'; set -- $users; IFS='
'
		for line; do
			u=${line%% *}; s=${line#* }; uid=$s
			test "$s" != host || uid=$(id -u "$u" 2>/dev/null || true)
			printf '%s\n' "  - name: $u"
			test -z "$uid" || printf '%s\n' "    uid: $uid"
			printf '%s\n' "    shell: /bin/bash" "    lock_passwd: true" "    ssh_authorized_keys:" "      - $keytext"
			test "$sudo" = no || printf '%s\n' "    sudo: ALL=(ALL) NOPASSWD:ALL"
		done
	fi
	printf '%s\n' "EOF_USER"
}

#@help _image_seed_sshd_write1
# @command image seed sshd write <image>
# @summary Act terminal: the write_files of user-data -- /etc/ssh/sshd_config.d/vm-bake.conf (Port VM_BAKE_SSH_PORT, no root, no passwords, AuthorizedKeysFile /etc/ssh/authorized_keys/%u before the home, X11Forwarding when the template says 'service display x'), /etc/ssh/authorized_keys/<user> with VM_BAKE_HOST_KEY for every user of the template, /etc/profile.d/vm-bake.sh from its env lines, and /etc/modules-load.d/vm-bake.conf (9p, 9pnet_virtio) when it says 'service files view'. The template is read at generation time
# @group   image
# @internal
# @see     image seed write
# @see     image ssh write
# @see     image env write
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_HOST_KEY  the public key file; a leading ~/ is the invoking user's home
# @env     VM_BAKE_SSH_PORT  the port sshd listens on in every guest of this image
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_seed_sshd_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 users="" envl="" svc="" key="$VM_BAKE_HOST_KEY" keytext="" line="" u="" view=no x11=no
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	envl=$(awk -v base="$VM_BAKE_BASE" -v family=env -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | sed 's/^\([^=]*\)=\(.*\)$/export \1="\2"/')
	svc=$(awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "$svc" | grep -qx 'files view' && view=yes
	printf '%s\n' "$svc" | grep -qx 'display x' && x11=yes
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	keytext=$(cat "$key" 2>/dev/null || true)
	printf '%s\n' "cat >> '$dir/seed/user-data' <<'EOF_FILES'"
	printf '%s\n' "write_files:"
	printf '%s\n' "  - path: /etc/ssh/sshd_config.d/vm-bake.conf" "    permissions: '0644'" "    content: |" "      Port $VM_BAKE_SSH_PORT" "      PermitRootLogin no" "      PasswordAuthentication no" "      KbdInteractiveAuthentication no" "      LogLevel VERBOSE" "      AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys"
	test "$x11" = no || printf '%s\n' "      X11Forwarding yes"
	if test -n "$users"; then
		IFS='
'; set -- $users; IFS='
'
		for line; do
			u=${line%% *}
			printf '%s\n' "  - path: /etc/ssh/authorized_keys/$u" "    permissions: '0644'" "    content: |" "      $keytext"
		done
	fi
	if test -n "$envl"; then
		printf '%s\n' "  - path: /etc/profile.d/vm-bake.sh" "    permissions: '0644'" "    content: |" "      # written by vm-bake (template env) -- the sessions' environment"
		printf '%s\n' "$envl" | sed 's/^/      /'
	fi
	test "$view" = no || printf '%s\n' "  - path: /etc/modules-load.d/vm-bake.conf" "    permissions: '0644'" "    content: |" "      9p" "      9pnet_virtio"
	printf '%s\n' "EOF_FILES"
}

#@help _image_seed_view_write1
# @command image seed view write <image>
# @summary Act terminal: the view in user-data when the template says 'service files view' (read at generation time) -- bootcmd creates /var/git, mounts hangs the 9p share 'home' (trans=virtio, 9p2000.L) on the home of the host-uid user and binds /var/git to VM_BAKE_REPO_LOCAL below it, runcmd gives /var/git to that user; a template without a view gets a comment line
# @group   image
# @internal
# @see     image seed write
# @see     image view write
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_REPO_LOCAL  the clones' directory under the guest's home
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_seed_view_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 users="" svc="" hostuser=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	svc=$(awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	hostuser=$(printf '%s\n' "$users" | awk '$2 == "host" { print $1; exit }')
	if ! printf '%s\n' "$svc" | grep -qx 'files view'; then
		printf '%s\n' "# image $1: no 'service files view' in $t -- no 9p mounts"
		return 0
	fi
	printf '%s\n' "cat >> '$dir/seed/user-data' <<'EOF_VIEW'"
	printf '%s\n' "bootcmd:" "  - [install, -d, -m, '755', /var/git]"
	printf '%s\n' "mounts:" "  - [home, /home/$hostuser, 9p, 'trans=virtio,version=9p2000.L,rw,_netdev,nofail', '0', '0']" "  - [/var/git, /home/$hostuser/$VM_BAKE_REPO_LOCAL, none, 'bind,nofail', '0', '0']"
	printf '%s\n' "runcmd:" "  - [chown, '$hostuser:$hostuser', /var/git]"
	printf '%s\n' "EOF_VIEW"
}

#@help _image_seed_pack1
# @command image seed pack <image>
# @summary Act terminal: user-data ends with power_state poweroff (the throwaway guest halts itself when cloud-init is through, which 'image firstboot gone' waits for), then the seed directory becomes VM_BAKE_IMAGE_DIR/<image>/seed.iso (makefs cd9660, rockridge, label cidata -- the label NoCloud looks for)
# @group   image
# @internal
# @see     image seed write
# @see     image firstboot gone
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_seed_pack1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "cat >> '$dir/seed/user-data' <<'EOF_POWER'"
	printf '%s\n' "power_state:" "  mode: poweroff" "  timeout: 30" "  condition: true"
	printf '%s\n' "EOF_POWER"
	printf '%s\n' "rm -f '$dir/seed.iso' && makefs -t cd9660 -o rockridge -o label=cidata '$dir/seed.iso' '$dir/seed' || exit 1"
	printf '%s\n' "printf '# image %s: seed.iso (cidata) -- %s\\n' $(sq "$1") \"\$(wc -l < '$dir/seed/user-data') lines of user-data\" >&2"
}

#@help __image_check_seed1
# @command image check seed <image>
# @summary The template of the image (read at generation time) can be rendered as a NoCloud seed: when it says 'service files view', exactly one of its users has uid host -- that user's home is the view; a comment line, else an error line
# @group   image
# @internal
# @see     image seed write
# @see     template user add
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
__image_check_seed1() {
	local t="" cur="" chain="" p="" n=0 users="" svc="" seen=0
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	svc=$(awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	seen=$(printf '%s\n' "$users" | awk '$2 == "host" { print $1 }' | grep -c . || true)
	if printf '%s\n' "$svc" | grep -qx 'files view' && test "$seen" -ne 1; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image seed write: the view is the home of the template's host-uid user, and $t has $seen of them (template user add <template> <name> host)")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1: the template $t renders as a seed")"
	fi
}

#@help ___image_seed_write1
# @command image seed write <image>
# @summary The NoCloud seed of the bake, VM_BAKE_IMAGE_DIR/<image>/seed.iso: 'image check seed' (a view needs exactly one host-uid user), then six acts -- 'image seed meta write' (meta-data: instance-id bake-<image>, hostname VM_BAKE_FIRSTBOOT), 'image seed net write' (network-config: VM_BAKE_FIRSTBOOT_ADDRESS static on the MAC derived from it, gateway and nameserver VM_BAKE_GUEST_GATEWAY), 'image seed user write' (user-data begins: packages and users of the template), 'image seed sshd write' (write_files: sshd on VM_BAKE_SSH_PORT without root or passwords, the authorized key of every user, the env lines as /etc/profile.d/vm-bake.sh), 'image seed view write' (the 9p mounts when the template says 'service files view'), 'image seed pack' (power_state poweroff, makefs). The template's rc lines are FreeBSD's rc.conf and are noted, not written (read at generation time)
# @group   image
# @internal
# @see     image firstboot
# @see     image check seed
# @see     image seed pack
# @see     image view write
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
___image_seed_write1() {
	local t="" cur="" chain="" p="" n=0 rcl=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	rcl=$(awk -v base="$VM_BAKE_BASE" -v family=rc -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check seed $(sq "$1")"
	test -z "$rcl" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image $1: rc lines are FreeBSD's rc.conf, a Linux image ignores them: $(printf '%s' "$rcl" | tr '\n' ' ')")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed meta write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed net write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed user write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed sshd write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed view write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed pack $(sq "$1")"
}
