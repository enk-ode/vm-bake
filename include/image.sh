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
# @summary The bake behind the three spellings of 'image make freebsd': the template exists, the image name is img:<name>:<version> and free, the content terminals are pinned where VM_BAKE_BAKE_IN says (image check pins, before anything is made); then 'image create', 'image base', 'image burn', 'image close' and 'image seal' in turn (each a command of its own; create decides by the template's base kind)
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pins"
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
# @summary The base on the host: the image has a record and no content terminal is pinned away (image check pins host); the disk attached as md and mounted by its labels, then 'image base content'
# @group   image
# @internal
# @see     image base
#@end
___image_base_host1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pins host"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk attach $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk mount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check mounted $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image base content $(sq "$1")"
}

#@help ___image_base_builder1
# @command image base builder <image>
# @summary The base in the builder guest: the image has a record and the content terminals are pinned into the builder (image check pins builder); the builder's configuration gets the image's disk as its second disk, the builder starts, answers ssh, mounts the disk by its labels under the image's path, then 'image base content' runs there (the content terminals are pinned to ssh)
# @group   image
# @internal
# @see     image base
# @see     image builder start
#@end
___image_base_builder1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pins builder"
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
# @summary Step 3, the template: the image has a record, the content terminals are pinned where VM_BAKE_BAKE_IN says (image check pins), every user of the template resolves (a host uid exists, the key file VM_BAKE_HOST_KEY is readable); then the template's packages via 'pkg -r', its package files from VM_BAKE_PKG_DIR staged and added, its ports built and installed in the builder (an error line when ports are listed and VM_BAKE_BAKE_IN is host), its rc.conf lines, its env variables as profile.d, its users with the host key in authorized_keys, the view of the host's home when the template says 'service files view', root locked (pkgbase ships root without a password), doas for them when the template lists doas, and sshd on VM_BAKE_SSH_PORT with keys only and no root -- where VM_BAKE_BAKE_IN says (the pins)
# @group   image
# @example vm-bake image burn freebsd-dev-20261101
# @see     image base
# @see     image close
# @see     template port add
# @env     VM_BAKE_BAKE_IN  host or builder: ports build only in the builder
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
___image_burn1() {
	local t="" cur="" chain="" p="" n=0 a="" base="" abi="" osv="" ports="" pkgfiles="" srcs=""
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pins"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check users $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check daemons $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg install $(sq "$1") $(sq "$abi") $(sq "$osv")"
	pkgfiles=$(awk -v base="$VM_BAKE_BASE" -v family=pkgfile -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -z "$pkgfiles" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pkgfiles $(sq "$1")" "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkgfile stage $(sq "$1")" "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkgfile add $(sq "$1")"
	ports=$(awk -v base="$VM_BAKE_BASE" -v family=port -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -z "$ports" || test "$VM_BAKE_BAKE_IN" != builder || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image port build $(sq "$1")" "\"\$VM_BAKE_CONTEXT_SCRIPT\" image port install $(sq "$1")"
	test -z "$ports" || test "$VM_BAKE_BAKE_IN" = builder || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image burn: ports build in the builder only (image builder use): $(printf '%s' "$ports" | tr '\n' ' ')")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image rc write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image env write $(sq "$1")"
	test -z "$(awk -v base="$VM_BAKE_BASE" -v family=daemon -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image daemon write $(sq "$1")"
	test -z "$(awk -v base="$VM_BAKE_BASE" -v family=file -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image file write $(sq "$1")"
	srcs=$(awk -v base="$VM_BAKE_BASE" -v family=source -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -z "$srcs" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image $1: source lines are apt sources, a FreeBSD image takes its packages from pkg's repositories: $(printf '%s' "$srcs" | awk '{ print $1 }' | tr '\n' ' ')")"
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
# @summary The disk closed on the host: the image has a record and is mounted, no content terminal is pinned away (image check pins host); the package report into the image, unmounted, the md detached, the sha256 of disk0.img written beside it and into the record
# @group   image
# @internal
# @see     image close
#@end
___image_close_host1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pins host"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check mounted $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg report $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk unmount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk detach $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image digest write $(sq "$1")"
}

#@help ___image_close_builder1
# @command image close builder <image>
# @summary The disk closed in the builder: the image has a record and the content terminals are pinned into the builder (image check pins builder); the package report into the image, unmounted there, the builder shut down, then the sha256 of disk0.img on the host
# @group   image
# @internal
# @see     image close
# @see     image builder stop
#@end
___image_close_builder1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pins builder"
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

#@help ___image_prune0
# @command image prune
# @summary Drop every image no guest is made from: the image records and the image file of every guest record read at generation time; a sealed image (it has a digest) that no guest names gets its 'image drop' line, an open image (no digest: a bake under way, or one that died with the lock -- image lock drop, then image drop by name) is left with a note; every image in use is a comment
# @group   image
# @example vm-bake image prune
# @see     image drop
# @see     image list
#@end
___image_prune0() {
	local d="" g="" n="" img="" used="" dropped=0
	for g in "$VM_BAKE_BASE"/guest/*/; do
		IFS= read -r img 2>/dev/null < "$g/image" || continue
		used="$used
$img"
	done
	for d in "$VM_BAKE_BASE"/image/*/; do
		test -f "$d/template" || continue
		n=$(basename "$d")
		test -f "$d/digest" || { printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image prune: $n is open (no digest), left alone")"; continue; }
		printf '%s\n' "$used" | grep -qxF -- "$n" && continue
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image drop $(sq "$n")"
		dropped=$((dropped + 1))
	done
	test "$dropped" -gt 0 || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'image prune: every sealed image has a guest, nothing to drop'"
}

#@help __image_check_pins0
# @command image check pins
# @summary The content terminals are pinned where VM_BAKE_BAKE_IN says: by its value rewrite to 'image check pins host' or 'image check pins builder'; any other value is an error line. The pins are read when a step acts, so a pull that brings a new content terminal leaves it on the profile's sudo sh until 'image builder use' runs again -- the check stops a bake before such an act writes into a path the host has not mounted
# @group   image
# @internal
# @see     image make freebsd from
# @see     image burn
# @see     image builder use
# @see     image builder leave
# @env     VM_BAKE_BAKE_IN  the place: host or builder
#@end
__image_check_pins0() {
	case "$VM_BAKE_BAKE_IN" in
		host|builder) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check pins $VM_BAKE_BAKE_IN" ;;
		*) printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image check pins: VM_BAKE_BAKE_IN is '$VM_BAKE_BAKE_IN' (host | builder: image builder use, image builder leave)")" ;;
	esac
}

#@help __image_check_pins_builder0
# @command image check pins builder
# @summary The builder branch of 'image check pins' (VM_BAKE_BAKE_IN=builder): every one of the twenty content terminals is pinned to the builder's ssh line as 'image builder use' spells it now (the pins read at generation time from the environment, VM_BAKE_INTERPRETER_<terminal>) -- a comment line, else an error line naming the strays and 'image builder use'
# @group   image
# @internal
# @see     image check pins
# @see     image base builder
# @see     image close builder
# @see     image builder use
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the builder's sshd port
# @env     VM_BAKE_BUILDER  the builder guest's name (its known_hosts file lives under .tmp)
# @env     VM_BAKE_BUILDER_USER  the user ssh logs in as
# @env     VM_BAKE_BUILDER_ADDRESS  the builder's address
#@end
__image_check_pins_builder0() {
	local key="$VM_BAKE_HOST_KEY" f="" ssh="" pin="" bad=""
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	ssh="ssh -p $VM_BAKE_SSH_PORT -i ${key%.pub} -o UserKnownHostsFile=$VM_BAKE_BASE/.tmp/known_hosts.$VM_BAKE_BUILDER -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 $VM_BAKE_BUILDER_USER@$VM_BAKE_BUILDER_ADDRESS doas sh"
	for f in image_disk_mount image_keys_write image_pkg_base image_repo_write image_boot_write image_pkg_install image_pkgfile_add image_port_build image_port_install image_rc_write image_env_write image_daemon_write image_file_write image_user_make image_view_write image_root_lock image_doas_write image_ssh_write image_pkg_report image_disk_unmount; do
		eval "pin=\${VM_BAKE_INTERPRETER_$f:-}"
		test "$pin" = "$ssh" || bad="$bad $f"
	done
	if test -z "$bad"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'image check pins: the twenty content terminals are pinned into the builder'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image check pins: VM_BAKE_BAKE_IN is builder, but these content terminals are not pinned to the builder's ssh line:$bad -- run 'image builder use' again (a pull that brings a new content terminal leaves it on the profile's pin)")"
	fi
}

#@help __image_check_pins_host0
# @command image check pins host
# @summary The host branch of 'image check pins' (VM_BAKE_BAKE_IN=host): no content terminal is pinned to an ssh line (the pins read at generation time from the environment, VM_BAKE_INTERPRETER_<terminal>): on the host the twenty run under the profile's sudo sh -- a comment line, else an error line naming the strays and 'image builder leave'
# @group   image
# @internal
# @see     image check pins
# @see     image base host
# @see     image close host
# @see     image builder leave
#@end
__image_check_pins_host0() {
	local f="" pin="" bad=""
	for f in image_disk_mount image_keys_write image_pkg_base image_repo_write image_boot_write image_pkg_install image_pkgfile_add image_port_build image_port_install image_rc_write image_env_write image_daemon_write image_file_write image_user_make image_view_write image_root_lock image_doas_write image_ssh_write image_pkg_report image_disk_unmount; do
		eval "pin=\${VM_BAKE_INTERPRETER_$f:-}"
		case "$pin" in "ssh "*) bad="$bad $f" ;; esac
	done
	if test -z "$bad"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'image check pins: no content terminal is pinned away from the host'"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image check pins: VM_BAKE_BAKE_IN is host, but these content terminals are pinned to an ssh line:$bad -- run 'image builder leave' (or 'image builder use' to bake in the builder)")"
	fi
}

#@help ___image_builder_use0
# @command image builder use
# @summary Bake in the builder guest from now on: VM_BAKE_BAKE_IN=builder, and the content terminals (disk mount, keys, pkg base, repo, boot, pkg install, rc, user, view, root lock, doas, ssh, pkg report, disk unmount) pinned to 'ssh -p VM_BAKE_SSH_PORT -i <key> VM_BAKE_BUILDER_USER@VM_BAKE_BUILDER_ADDRESS doas sh' -- one setintp line each, so the pins are seen. Run it again after a pull that brings a new content terminal: it would sit on the profile's sudo sh, and every bake step checks the pins first (image check pins) and names the strays
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
	for f in image_disk_mount image_keys_write image_pkg_base image_repo_write image_boot_write image_pkg_install image_pkgfile_add image_port_build image_port_install image_rc_write image_env_write image_daemon_write image_file_write image_user_make image_view_write image_root_lock image_doas_write image_ssh_write image_pkg_report image_disk_unmount; do
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
	for f in image_disk_mount image_keys_write image_pkg_base image_repo_write image_boot_write image_pkg_install image_pkgfile_add image_port_build image_port_install image_rc_write image_env_write image_daemon_write image_file_write image_user_make image_view_write image_root_lock image_doas_write image_ssh_write image_pkg_report image_disk_unmount; do
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
# @summary Act terminal (the invoking user, delegated by zfs allow): vm-bake's datasets exist -- image, guest and data under the dataset mounted at VM_BAKE_DIR, which root made once and delegated, and the distfiles directories (VM images, package files) beside them -- idempotent, the first act of image create and guest make
# @group   image
# @internal
# @see     image create
# @see     guest make
# @env     VM_BAKE_DIR  vm-bake's dataset: image/, guest/, data/ (datasets) and distfiles/ (directories) live in it
# @env     VM_BAKE_IMAGE_CACHE  the cache directory
# @env     VM_BAKE_PKG_DIR  the package-file directory
#@end
_image_tree_ensure0() {
	printf '%s\n' "ds=\$(zfs list -H -o name '$VM_BAKE_DIR') || { printf '# Error: %s is no dataset (root makes it once and delegates it: help env VM_BAKE_DIR)\\n' '$VM_BAKE_DIR' >&2; exit 1; }"
	printf '%s\n' "zfs list -H -o name \"\$ds/image\" > /dev/null 2>&1 || zfs create \"\$ds/image\" || exit 1"
	printf '%s\n' "zfs list -H -o name \"\$ds/guest\" > /dev/null 2>&1 || zfs create \"\$ds/guest\" || exit 1"
	printf '%s\n' "zfs list -H -o name \"\$ds/data\" > /dev/null 2>&1 || zfs create \"\$ds/data\" || exit 1"
	printf '%s\n' "install -d -m 755 '$VM_BAKE_IMAGE_CACHE' '$VM_BAKE_PKG_DIR' || exit 1"
	printf '%s\n' "printf '# tree: %s/image, %s/guest, %s/data, cache %s\\n' \"\$ds\" \"\$ds\" \"\$ds\" '$VM_BAKE_IMAGE_CACHE' >&2"
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
	printf '%s\n' "cp -R /usr/share/keys/. '$mnt/usr/share/keys/' || exit 1"
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
# @summary Step 2 of the Linux bake, the first boot: the image has a record; then the seed of the bake written (image seed write), the throwaway guest VM_BAKE_FIRSTBOOT configured with the image's disk and the seed, linked where vm-bhyve looks, started, its console read until the first boot reports its packages (image firstboot report: a missing package ends the bake with an error naming it), waited for until its bhyve process is gone (cloud-init powers the guest off when it is done), its link and configuration removed again -- the guest exists for this one boot
# @group   image
# @example vm-bake image firstboot img:debian-dev:v1
# @see     image make linux
# @see     image seed write
# @see     image firstboot conf
# @see     image firstboot report
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name
#@end
___image_firstboot1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link write $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest run $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot report"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot gone"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link drop $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf drop"
}


#@help __image_firstboot_conf1
# @command image firstboot conf <image>
# @summary The throwaway guest's vm-bhyve configuration, by the bake of the image's template (read at generation time): rewrite to 'image firstboot conf cloud-init <image>' (the seed.iso as the CD) or 'image firstboot conf autoinstall <image>' (the site.iso as the CD; the install ISO comes with 'guest install') or 'image firstboot conf apkovl <image>' (the overlay.iso as the CD, the live ISO likewise with 'guest install'); all end in 'image firstboot conf write <image> <cd>'
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

#@help __image_firstboot_conf_apkovl1
# @internal the apkovl case of 'image firstboot conf <image>' (image firstboot conf apkovl <image>): rewrite to 'image firstboot conf write <image> <overlay.iso>' -- the live ISO is not in the configuration: 'guest install' hangs it on the first run only, so the restart after the installation comes up from the disk
#@end
__image_firstboot_conf_apkovl1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf write $(sq "$1") $(sq "$VM_BAKE_IMAGE_DIR/$1/overlay.iso")"
}

#@help __image_firstboot_conf2
# @internal dispatch fallback of 'image firstboot conf <bake> <image>' for a bake that is neither cloud-init, autoinstall nor apkovl: an error line
#@end
__image_firstboot_conf2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image firstboot conf: the template of $2 bakes by $1, which has no first boot (cloud-init | autoinstall | apkovl)")"
}

#@help _image_firstboot_conf_write2
# @command image firstboot conf write <image> <cd>
# @summary Act terminal (the invoking user: the directory is theirs): the throwaway guest's vm-bhyve configuration VM_BAKE_GUEST_DIR/<firstboot>/<firstboot>.conf -- UEFI, cpu and memory from the image's template (read at generation time), the switch, the MAC of VM_BAKE_FIRSTBOOT_ADDRESS, the image's disk0.img as disk0 (custom path) and <cd> as disk1 (ahci-cd: the seed.iso of a cloud-init bake, the site.iso of an autoinstall bake, the overlay.iso of an apkovl bake), bhyve_options -w (bhyve ignores the MSRs a guest kernel touches and bhyve does not implement -- OpenBSD's kernel dies without it, Linux does not mind); no dataset and no clone: the guest boots the image itself, once
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
# @summary Step 2 of the OpenBSD bake, the installation: the image has a record; then the response file (image response write) and the site set (image site write) rendered from the template and packed as site.iso (image site pack), the throwaway guest VM_BAKE_FIRSTBOOT configured with the image's disk and the site.iso (image firstboot conf), linked where vm-bhyve looks, run from the template's install ISO (guest install: the ISO rides along for this one run), its console typed into autoinstall(8) (image console drive), waited for until bhyve is gone (the installer reboots, the installed system adds the packages and powers off), its link and configuration removed again. The root acts (guest link write, guest install, image console drive, guest link drop) are pinned 'sudo sh'; sudo stamps its ticket when a command starts, so a console drive of ten minutes outlives the ticket and guest link drop asks for the PIN again (a bake on illyria failed there). One sudo for the whole batch instead: pin image_install to 'sudo -E sh -c "$VM_BAKE_BATCH_COMBINATOR_INTERPRETER"' (the engine runs a pin through eval, so the class default's name expands to its text, but a variable's text is split into words and its quotes stay letters -- the bare name broke the first one-sudo bake on illyria with 'Unterminated quoted string'; sh -c hands the text to a shell that parses it; -E keeps the environment vm-bake builds and is allowed because a sudoers ALL implies SETENV) and the acts that write the image's files (image_response_write, the five acts of image site write, image_site_files_place, image_site_pack, image_firstboot_conf_write, image_firstboot_conf_drop) to 'sudo -u <user> sh', which root runs without authentication -- one PIN at the start; the engine's traces and logs of that run are then root's
# @group   image
# @example vm-bake image install img:openbsd-dev:v1
# @see     image make openbsd
# @see     image response write
# @see     image site write
# @see     image console drive
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
___image_install1() {
	local t="" cur="" chain="" p="" n=0 a="" base="" iso="" srcs=""
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check daemons $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image response write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site files place $(sq "$1")"
	srcs=$(awk -v base="$VM_BAKE_BASE" -v family=source -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -z "$srcs" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image $1: source lines are apt sources, an OpenBSD image takes its packages from installurl: $(printf '%s' "$srcs" | awk '{ print $1 }' | tr '\n' ' ')")"
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
# @summary Act terminal: the response file of autoinstall(8), VM_BAKE_IMAGE_DIR/<image>/site/install.conf -- hostname VM_BAKE_FIRSTBOOT, vio0 static on VM_BAKE_FIRSTBOOT_ADDRESS, route and nameserver VM_BAKE_GUEST_GATEWAY, domain VM_BAKE_GUEST_DOMAIN, root with a throwaway password (install.site locks it) and no key, sshd on, no root login, the X sets only when the template says 'service display x', com0 at 115200, no user (install.site makes the template's users with their host uids), the host's timezone (/var/db/zoneinfo, else UTC), sd0 whole-disk GPT with the auto layout (the question has one more word when the disk already carries an OpenBSD area, from an earlier run, so both spellings are answered); the sets from the install CD, then the site set from the site CD (which carries no INSTALL.<arch>, so the installer asks whether to use it anyway: yes); neither CD's set directory carries SHA256.sig, and the installer asks once per CD whether to go on without verification: yes, as two lines, because autoinstall(8) spends an answer line on every question it matches (a bake on illyria had one line, and the second question took its default, no) -- the installer numbers the CDs, so the console driver fills in @INSTCD@ and @SITECD@ when it copies the file. The template is read at generation time
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
	printf '%s\n' "System hostname = $VM_BAKE_FIRSTBOOT" "Which network interface do you wish to configure = vio0" "IPv4 address for vio0 = ${VM_BAKE_FIRSTBOOT_ADDRESS%/*}" "Netmask for vio0 = $mask" "IPv6 address for vio0 = none" "Which network interface do you wish to configure = done" "Default IPv4 route = $VM_BAKE_GUEST_GATEWAY" "DNS domain name = $VM_BAKE_GUEST_DOMAIN" "DNS nameservers = $VM_BAKE_GUEST_GATEWAY" "Password for root account = *************" "Public ssh key for root account = none" "Start sshd(8) by default = yes" "Do you expect to run the X Window System = $x" "Change the default console to com0 = yes" "Which speed should com0 use = 115200" "Setup a user = no" "Allow root ssh login = no" "What timezone are you in = $tz" "Which disk is the root disk = sd0" "Encrypt the root disk with a passphrase = no" "Encrypt the root disk with a (p)assphrase or (k)eydisk = no" "Use (W)hole disk MBR, whole disk (G)PT or (E)dit = gpt" "Use (W)hole disk MBR, whole disk (G)PT, (O)penBSD area or (E)dit = gpt" "Use (A)uto layout, (E)dit auto layout, or create (C)ustom layout = a" "Location of sets = @INSTCD@" "Pathname to the sets = $rel/$arch/"
	test "$x" = yes || printf '%s\n' "Set name(s) = -x*"
	printf '%s\n' "Set name(s) = done" "Directory does not contain SHA256.sig. Continue without verification = yes" "Location of sets = @SITECD@" "Pathname to the sets = $rel/$arch/" "INSTALL.$arch not found. Use sets found here anyway = yes" "Set name(s) = site$nn.tgz" "Set name(s) = done" "Directory does not contain SHA256.sig. Continue without verification = yes" "Location of sets = done"
	printf '%s\n' "EOF_RESPONSE"
	printf '%s\n' "printf '# image %s: install.conf -- %s on %s netmask %s, sets %s/%s from the install CD and site%s.tgz from the site CD, X %s, timezone %s\\n' $(sq "$1") '$VM_BAKE_FIRSTBOOT' '${VM_BAKE_FIRSTBOOT_ADDRESS%/*}' '$mask' '$rel' '$arch' '$nn' '$x' '$tz' >&2"
}

#@help ___image_site_write1
# @command image site write <image>
# @summary The site set's install.site, VM_BAKE_IMAGE_DIR/<image>/site.d/install.site, written aspect by aspect -- 'image site head write' (the file, its directories, sshd on VM_BAKE_SSH_PORT), 'image site user write' (the template's users with the host key, doas for them when the template lists doas), 'image site env write' (the env lines into /etc/profile), 'image site net write' (installurl, root locked, the bake's address and the seed hook as hostname.vio0), 'image site firsttime write' (rc.firsttime: the packages, each checked, the report line, power off; the file made executable). autoinstall(8) runs install.site chrooted in the installed system; every writer reads the template at generation time and appends to the one file, so the acts run in this order
# @group   image
# @internal
# @see     image install
# @see     image site head write
# @see     image site user write
# @see     image site env write
# @see     image site net write
# @see     image site firsttime write
# @see     image site pack
#@end
___image_site_write1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site head write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site user write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site env write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site net write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site daemon write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image site firsttime write $(sq "$1")"
}

#@help _image_site_head_write1
# @command image site head write <image>
# @summary Act terminal: install.site begun -- site.d made, the script's header with set -e, the directories it fills (/etc/ssh/authorized_keys, /etc/vm-bake, /usr/local/libexec), and sshd: the stock lines for Port, PermitRootLogin, PasswordAuthentication, KbdInteractiveAuthentication, AuthorizedKeysFile and X11Forwarding commented out, then VM_BAKE_SSH_PORT, no root, keys only under /etc/ssh/authorized_keys/<user>, and X11Forwarding when the template says 'service display x' (read at generation time)
# @group   image
# @internal
# @see     image site write
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_SSH_PORT  the port sshd listens on in every guest
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_site_head_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 svc="" x11=no
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	svc=$(awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "$svc" | grep -qx 'display x' && x11=yes
	printf '%s\n' "install -d -m 700 '$dir/site.d' || exit 1"
	printf '%s\n' "cat > '$dir/site.d/install.site' <<'EOF_SITE'"
	printf '%s\n' '#!/bin/sh' '# written by vm-bake (image site write) -- run by autoinstall(8), chrooted in the installed system' 'set -e'
	printf '%s\n' 'install -d -m 755 /etc/ssh/authorized_keys /etc/vm-bake /usr/local/libexec'
	printf '%s\n' "sed -i -E 's/^[[:space:]]*(Port|PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|AuthorizedKeysFile|X11Forwarding)[[:space:]]/#&/' /etc/ssh/sshd_config"
	printf '%s\n' "cat >> /etc/ssh/sshd_config <<'EOF_SSHD'" "Port $VM_BAKE_SSH_PORT" "PermitRootLogin no" "PasswordAuthentication no" "KbdInteractiveAuthentication no" "AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys"
	test "$x11" = no || printf '%s\n' "X11Forwarding yes"
	printf '%s\n' "EOF_SSHD" "EOF_SITE"
	printf '%s\n' "printf '# image %s: install.site begun -- sshd on %s, X11 %s\\n' $(sq "$1") '$VM_BAKE_SSH_PORT' '$x11' >&2"
}

#@help _image_site_user_write1
# @command image site user write <image>
# @summary Act terminal: the template's users (read at generation time) appended to install.site -- useradd with the host's uid for 'host', in wheel, ksh, VM_BAKE_HOST_KEY as the key under /etc/ssh/authorized_keys/<user>; when the template's packages name doas, /etc/doas.conf with 'permit nopass keepenv <user> as root' for each (doas is base on OpenBSD: the word is read, no package is added). No users: a comment
# @group   image
# @internal
# @see     image site write
# @see     template user add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_HOST_KEY  the public key of the host, every user's authorized key
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_site_user_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 users="" key="$VM_BAKE_HOST_KEY" keytext="" line="" u="" s="" uid="" doas=no oifs="$IFS"
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	awk -v base="$VM_BAKE_BASE" -v family=package -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx doas && doas=yes
	test -n "$users" || { printf '%s\n' "# image $1: no users in $t -- install.site makes none"; return 0; }
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	keytext=$(cat "$key" 2>/dev/null || true)
	printf '%s\n' "cat >> '$dir/site.d/install.site' <<'EOF_SITE'"
	IFS='
'; set -- $users; IFS=$oifs
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
	printf '%s\n' "EOF_SITE"
	printf '%s\n' "printf '# image %s: install.site -- users %s, doas %s\\n' $(sq "$1") $(sq "$(printf '%s\n' "$users" | awk '{ print $1 }' | tr '\n' ' ' | sed 's/ $//')") '$doas' >&2"
}

#@help _image_site_env_write1
# @command image site env write <image>
# @summary Act terminal: the template's env lines (read at generation time) appended to install.site as export lines at the end of /etc/profile, the sessions' environment. No env lines: a comment
# @group   image
# @internal
# @see     image site write
# @see     template env add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_site_env_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 envl=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	envl=$(awk -v base="$VM_BAKE_BASE" -v family=env -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | sed 's/^\([^=]*\)=\(.*\)$/export \1="\2"/')
	test -n "$envl" || { printf '%s\n' "# image $1: no env lines in $t -- /etc/profile stays"; return 0; }
	printf '%s\n' "cat >> '$dir/site.d/install.site' <<'EOF_SITE'"
	printf '%s\n' "cat >> /etc/profile <<'EOF_ENV'" "# written by vm-bake (template env) -- the sessions' environment"
	printf '%s\n' "$envl"
	printf '%s\n' "EOF_ENV" "EOF_SITE"
	printf '%s\n' "printf '# image %s: install.site -- %s env lines into /etc/profile\\n' $(sq "$1") '$(printf '%s\n' "$envl" | grep -c .)' >&2"
}

#@help _image_site_net_write1
# @command image site net write <image>
# @summary Act terminal: appended to install.site -- installurl (cdn.openbsd.org), root locked (usermod -p '*'), the bake's address and netmask under /etc/vm-bake, and the seed hook /usr/local/libexec/vm-bake-seed as the one line of /etc/hostname.vio0: at every boot it looks on cd0 and cd1 for a seed CD (guest seed write autoinstall -- the marker vm-bake-seed, address, netmask, myname, mygate, resolv.conf and the ssh host key), takes what it finds and configures vio0; without a seed the bake's address holds. The two CD devices are two calls of one function in the hook, no loop
# @group   image
# @internal
# @see     image site write
# @see     guest seed write autoinstall
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_FIRSTBOOT_ADDRESS  the bake's address, with prefix length
#@end
_image_site_net_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" mask=""
	mask=$(printf '%s\n' "${VM_BAKE_FIRSTBOOT_ADDRESS#*/}" | awk '{ m = $1 ? 4294967296 - 2 ^ (32 - $1) : 0; printf "%d.%d.%d.%d", int(m / 16777216) % 256, int(m / 65536) % 256, int(m / 256) % 256, m % 256 }')
	printf '%s\n' "cat >> '$dir/site.d/install.site' <<'EOF_SITE'"
	printf '%s\n' "printf '%s\\n' 'https://cdn.openbsd.org/pub/OpenBSD' > /etc/installurl"
	printf '%s\n' "usermod -p '*' root"
	printf '%s\n' "printf '%s\\n' '${VM_BAKE_FIRSTBOOT_ADDRESS%/*}' > /etc/vm-bake/address" "printf '%s\\n' '$mask' > /etc/vm-bake/netmask"
	printf '%s\n' "cat > /usr/local/libexec/vm-bake-seed <<'EOF_SEED'" '#!/bin/sh' "# written by vm-bake (image site net write) -- the one line of /etc/hostname.vio0: a seed CD (guest seed write autoinstall) names, addresses and keys this guest; without one, the address of the bake" 'a=$(cat /etc/vm-bake/address) m=$(cat /etc/vm-bake/netmask)' 'seed() {' '	mount -r -t cd9660 "/dev/${1}a" /mnt 2>/dev/null || return 0' '	if test -f /mnt/vm-bake-seed; then' '		a=$(cat /mnt/address) m=$(cat /mnt/netmask)' '		cp /mnt/myname /mnt/mygate /mnt/resolv.conf /etc/' '		install -m 600 /mnt/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key' '		install -m 644 /mnt/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub' '		hostname "$(cat /etc/myname)"' '	fi' '	umount /mnt' '}' 'seed cd0' 'seed cd1' 'ifconfig vio0 inet "$a" netmask "$m" up' "EOF_SEED"
	printf '%s\n' "chmod 755 /usr/local/libexec/vm-bake-seed" "printf '%s\\n' '!/usr/local/libexec/vm-bake-seed' > /etc/hostname.vio0"
	printf '%s\n' "EOF_SITE"
	printf '%s\n' "printf '# image %s: install.site -- installurl, root locked, %s netmask %s as the bake address, the seed hook as hostname.vio0\\n' $(sq "$1") '${VM_BAKE_FIRSTBOOT_ADDRESS%/*}' '$mask' >&2"
}

#@help _image_site_firsttime_write1
# @command image site firsttime write <image>
# @summary Act terminal: the end of install.site -- /etc/rc.firsttime, the bake's first boot: the template's packages (read at generation time) with pkg_add -I onto the console, pkg_info into /etc/vm-bake/packages, one check line per package (the stem before a flavor's --), the report '# vm-bake firstboot: missing <packages>' or '# vm-bake firstboot: packages complete' on the console (image console drive reads it), power off; then install.site made executable
# @group   image
# @internal
# @see     image site write
# @see     image console drive
# @see     template package add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_site_firsttime_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 pkgs=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	pkgs=$(awk -v base="$VM_BAKE_BASE" -v family=package -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -vx doas || true)
	printf '%s\n' "cat >> '$dir/site.d/install.site' <<'EOF_SITE'"
	printf '%s\n' "cat >> /etc/rc.firsttime <<'EOF_FIRST'" "# written by vm-bake (image site firsttime write) -- the bake's first boot: the packages, each checked against pkg_info, the report line on the console, then power off; the host seals the disk"
	test -z "$pkgs" || printf '%s\n' "pkg_add -I $(printf '%s\n' "$pkgs" | tr '\n' ' ')2>&1 | tee /dev/console"
	printf '%s\n' "pkg_info -q > /etc/vm-bake/packages"
	printf '%s\n' "missing="
	for p in $pkgs; do printf '%s\n' "grep -q '^${p%%--*}-[0-9]' /etc/vm-bake/packages || missing=\"\$missing $p\""; done
	printf '%s\n' "test -n \"\$missing\" && printf '# vm-bake firstboot: missing%s\\n' \"\$missing\" > /dev/console || printf '# vm-bake firstboot: packages complete\\n' > /dev/console"
	printf '%s\n' "shutdown -p now" "EOF_FIRST" "EOF_SITE"
	printf '%s\n' "chmod 755 '$dir/site.d/install.site'"
	printf '%s\n' "printf '# image %s: install.site done -- %s packages at the first boot\\n' $(sq "$1") '$(printf '%s\n' "$pkgs" | grep -c . || true)' >&2"
}

#@help _image_site_pack1
# @command image site pack <image>
# @summary Act terminal: the files of site.d -- install.site and the files of the template's file lines at their paths (image site files place) -- packed as the site set VM_BAKE_IMAGE_DIR/<image>/site/<release>/<arch>/site<NN>.tgz (bsdtar from a find -type f list, owned by root:wheel; the files alone, no directory entry: the installer unpacks the set with -p over the installed system, and a directory entry would set its mode on / or /etc -- the sixth bake of openbsd-dev packed '.' of a site.d made 0700 and came out with / unreadable for every user but root, pkg_add could not even fetch) with its SHA256 beside it, then the site directory -- install.conf at its root, the set under the release directory the installer expects -- becomes site.iso (makefs cd9660, rockridge, label vmbakesite), the CD the throwaway guest carries besides the install ISO
# @group   image
# @internal
# @see     image install
# @see     image site write
# @see     image site files place
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
	printf '%s\n' "(cd '$dir/site.d' && find . -type f | sed 's|^\\./||' | bsdtar -czf '$dir/site/$rel/$arch/site$nn.tgz' --uid 0 --gid 0 --uname root --gname wheel -n -T -) || exit 1"
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
# @summary Act terminal (root): the installer of the throwaway guest answered over vm-bhyve's tmux session (capture-pane reads, send-keys types) -- the loader told to use com0, then to boot: after the switch the loader reads the serial port directly while the firmware console keeps reading it too, so typed bytes split between the two (a bake on illyria saw a lone b), and boot is sent up to five times, each followed by five seconds of looking for the loader's booting line, a row of backspaces clearing what got through before; the installer sent into its shell, where it mounts the two CDs, finds install.conf on the site CD, writes it as /auto_install.conf with the CD names filled in (@INSTCD@, @SITECD@) and leaves the shell; then (A)utoinstall, which takes the local file (an installer that reports 'failed; check /tmp/ai/ai.log' ends the wait at once, instead of after the full timeout); when the installer reports CONGRATULATIONS and the kernel its reboot, the guest is powered off and started again with 'vm start', from its disk (vm-bhyve keeps the install ISO first in the boot order through every restart of its run loop, so the reboot would run the installer once more) -- that is the first boot, and the driver stays on the console until rc.firsttime (image site write) reports it: '# vm-bake firstboot: missing <packages>' ends the bake with an error naming them (pkg_add -I skips an ambiguous name without a word -- openvpn on 8.0 has two flavors, and the first bake of openbsd-dev sealed an image without it), '# vm-bake firstboot: packages complete' hands over to 'image firstboot gone'. Every wait has its seconds and ends in an error with the last screen and the guest powered off (vm poweroff -f): a guest whose install went wrong sits in vm-bhyve's restart loop otherwise, and the next 'guest install' would find it running
# @group   image
# @internal
# @see     image console drive
# @see     image response write
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, the tmux session
# @env     VM_BAKE_CONSOLE  tmux or nmdm, named in the error when the session or the device does not appear
#@end
_image_console_drive_tmux1() {
	printf '%s\n' "g=$(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' 'pane() { tmux capture-pane -p -t "$g" 2>/dev/null || true; }'
	printf '%s\n' 'send() { tmux send-keys -t "$g" "$1" Enter; }'
	printf '%s\n' 'n=0; until tmux has-session -t "$g" 2>/dev/null; do n=$((n + 1)); test "$n" -lt 60 || { printf "# Error: console %s: no tmux session within a minute (VM_BAKE_CONSOLE says tmux; vm-bhyve console= in system.conf?)\n" "$g" >&2; exit 1; }; sleep 1; done'
	cat <<'EOF_STEPS'
give_up() { printf '# Error: console %s: %s\n' "$g" "$1" >&2; pane | tail -15 >&2; vm poweroff -f "$g" >/dev/null 2>&1; printf '# console %s: powered off\n' "$g" >&2; exit 1; }
wait_for() { n=0; until pane | grep -- "$1" >/dev/null; do pane | grep "failed; check /tmp/ai/ai.log" >/dev/null && give_up "the installer failed before $1"; n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 within $2 s"; sleep 1; done; }
wait_last() { n=0; until pane | grep . | tail -1 | grep -q -- "$1"; do n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 as last line within $2 s"; sleep 1; done; }
wait_for 'boot>' 120
send 'set tty com0'; sleep 1
bs=$(printf '\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b')
booting() { pane | grep 'booting ' >/dev/null; }
n=0; until booting; do n=$((n + 1)); test "$n" -le 5 || give_up "no booting after $((n - 1)) boot commands"; send "${bs}boot"; m=0; until booting || test "$m" -ge 5; do m=$((m + 1)); sleep 1; done; done
wait_for '(I)nstall, (U)pgrade, (A)utoinstall or (S)hell?' 300
send 's'; sleep 2
send 'cd /dev && sh MAKEDEV cd0 cd1; cd /'
send 's=; mount_cd9660 /dev/cd0a /mnt 2>/dev/null && { test -f /mnt/install.conf && s=cd0; umount /mnt; }; mount_cd9660 /dev/cd1a /mnt 2>/dev/null && { test -f /mnt/install.conf && s=cd1; umount /mnt; }'
send 'case $s in cd0) i=cd1 ;; *) i=cd0 ;; esac; mount_cd9660 /dev/${s}a /mnt && sed "s/@INSTCD@/$i/;s/@SITECD@/$s/" /mnt/install.conf > /auto_install.conf && umount /mnt && echo "response file from $s, sets from $i"'
wait_for 'response file from cd' 30
send 'exit'
wait_last '(S)hell?' 60
send 'a'
wait_for 'CONGRATULATIONS' 1800
wait_for 'rebooted by root' 120
n=0; until vm list | grep "^$g  *.*Stopped" >/dev/null; do n=$((n + 1)); test "$n" -le 30 || give_up "still running a minute after the install's reboot"; vm poweroff -f "$g" >/dev/null 2>&1; sleep 2; done
vm start "$g" >&2 || give_up "vm start failed after the install"
printf '# console %s: installed, powered off at its reboot and started again from its disk for the first boot\n' "$g" >&2
wait_for '# vm-bake firstboot:' 1800
pane | grep -q '# vm-bake firstboot: missing' && give_up "the first boot left packages out: $(pane | grep '# vm-bake firstboot: missing' | tail -1 | tr -d '\r' | sed 's/.*missing //')"
printf '# console %s: the first boot reports its packages complete\n' "$g" >&2
EOF_STEPS
}

#@help _image_console_drive_nmdm1
# @command image console drive nmdm <image>
# @summary Act terminal (root): the same dialogue as 'image console drive tmux', over vm-bhyve's nmdm pair -- /dev/nmdm-<firstboot>.1B is opened once on descriptor 3 and put into raw mode without echo (a freshly opened tty has echo and canonical mode, which sends every byte the guest prints back into the guest as keystrokes and turns each line end into an Enter -- the loader then shows prompt after prompt; the settings hold as long as the descriptor stays open), read into VM_BAKE_GUEST_DIR/<firstboot>/console.log by a cat in the background (the last forty lines stand for the screen, through cat -v, read by a grep that takes all its input so that no writer gets a broken pipe: the firmware and the loader emit terminal control sequences, one of them resizes an xterm) and written with a carriage return per line; the device appears when bhyve runs, waited for a minute
# @group   image
# @internal
# @see     image console drive
# @see     image console drive tmux
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, in the device name
# @env     VM_BAKE_GUEST_DIR  the guests' directory, where the console log lies
# @env     VM_BAKE_CONSOLE  tmux or nmdm, named in the error when the session or the device does not appear
#@end
_image_console_drive_nmdm1() {
	printf '%s\n' "g=$(sq "$VM_BAKE_FIRSTBOOT") dev=$(sq "/dev/nmdm-$VM_BAKE_FIRSTBOOT.1B") log=$(sq "$VM_BAKE_GUEST_DIR/$VM_BAKE_FIRSTBOOT/console.log")"
	printf '%s\n' 'n=0; until test -c "$dev"; do n=$((n + 1)); test "$n" -lt 60 || { printf "# Error: console %s: no %s within a minute (VM_BAKE_CONSOLE says nmdm; vm-bhyve console= in system.conf?)\n" "$g" "$dev" >&2; exit 1; }; sleep 1; done'
	printf '%s\n' 'exec 3<> "$dev"; stty raw -echo <&3'
	printf '%s\n' ': > "$log"; cat <&3 >> "$log" & rd=$!' 'trap '"'"'kill "$rd" 2>/dev/null'"'"' EXIT'
	printf '%s\n' 'pane() { tail -n 40 "$log" 2>/dev/null | tr -d "\r" | cat -v; }'
	printf '%s\n' 'send() { printf "%s\r" "$1" >&3; }'
	cat <<'EOF_STEPS'
give_up() { printf '# Error: console %s: %s\n' "$g" "$1" >&2; pane | tail -15 >&2; vm poweroff -f "$g" >/dev/null 2>&1; printf '# console %s: powered off\n' "$g" >&2; exit 1; }
wait_for() { n=0; until pane | grep -- "$1" >/dev/null; do pane | grep "failed; check /tmp/ai/ai.log" >/dev/null && give_up "the installer failed before $1"; n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 within $2 s"; sleep 1; done; }
wait_last() { n=0; until pane | grep . | tail -1 | grep -q -- "$1"; do n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 as last line within $2 s"; sleep 1; done; }
wait_for 'boot>' 120
send 'set tty com0'; sleep 1
bs=$(printf '\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b')
booting() { pane | grep 'booting ' >/dev/null; }
n=0; until booting; do n=$((n + 1)); test "$n" -le 5 || give_up "no booting after $((n - 1)) boot commands"; send "${bs}boot"; m=0; until booting || test "$m" -ge 5; do m=$((m + 1)); sleep 1; done; done
wait_for '(I)nstall, (U)pgrade, (A)utoinstall or (S)hell?' 300
send 's'; sleep 2
send 'cd /dev && sh MAKEDEV cd0 cd1; cd /'
send 's=; mount_cd9660 /dev/cd0a /mnt 2>/dev/null && { test -f /mnt/install.conf && s=cd0; umount /mnt; }; mount_cd9660 /dev/cd1a /mnt 2>/dev/null && { test -f /mnt/install.conf && s=cd1; umount /mnt; }'
send 'case $s in cd0) i=cd1 ;; *) i=cd0 ;; esac; mount_cd9660 /dev/${s}a /mnt && sed "s/@INSTCD@/$i/;s/@SITECD@/$s/" /mnt/install.conf > /auto_install.conf && umount /mnt && echo "response file from $s, sets from $i"'
wait_for 'response file from cd' 30
send 'exit'
wait_last '(S)hell?' 60
send 'a'
wait_for 'CONGRATULATIONS' 1800
wait_for 'rebooted by root' 120
n=0; until vm list | grep "^$g  *.*Stopped" >/dev/null; do n=$((n + 1)); test "$n" -le 30 || give_up "still running a minute after the install's reboot"; vm poweroff -f "$g" >/dev/null 2>&1; sleep 2; done
vm start "$g" >&2 || give_up "vm start failed after the install"
printf '# console %s: installed, powered off at its reboot and started again from its disk for the first boot\n' "$g" >&2
wait_for '# vm-bake firstboot:' 1800
pane | grep -q '# vm-bake firstboot: missing' && give_up "the first boot left packages out: $(pane | grep '# vm-bake firstboot: missing' | tail -1 | tr -d '\r' | sed 's/.*missing //')"
printf '# console %s: the first boot reports its packages complete\n' "$g" >&2
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

#@help __image_make_alpine1
# @internal arity-1 sibling of 'image make alpine' (image make alpine <image>  -- the full name img:<template>:<version>): rewrite to 'image make alpine from <template> <version> <image>'
#@end
__image_make_alpine1() {
	local t="${1#img:}"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make alpine from $(sq "${t%%:*}") $(sq "${1##*:}") $(sq "$1")"
}

#@help __image_make_alpine2
# @command image make alpine <template> <version>
# @summary Bake an Alpine image from the template under the version: the image is img:<template>:<version>, handed to 'image make alpine from' -- the same three spellings as 'image make linux' (the full name alone, or a name of its own as third word)
# @group   image
# @param   version  the version field of the image name, a word of [A-Za-z0-9_.+-]
# @example vm-bake image make alpine alpine-dev v1
# @see     image make alpine from
# @see     image make openbsd
# @see     image make linux
# @see     image list
#@end
__image_make_alpine2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make alpine from $(sq "$1") $(sq "$2") $(sq "img:$1:$2")"
}

#@help __image_make_alpine3
# @internal arity-3 sibling of 'image make alpine' (image make alpine <template> <version> <image>  -- a name of its own): rewrite to 'image make alpine from <template> <version> <image>'
#@end
__image_make_alpine3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image make alpine from $(sq "$1") $(sq "$2") $(sq "$3")"
}

#@help ___image_make_alpine_from3
# @command image make alpine from <template> <version> <image>
# @summary The bake behind the three spellings of 'image make alpine': the template exists, the image name is img:<name>:<version> and free; then 'image create apkovl' (an empty disk0.img of the resource's size), 'image install apkovl' (the overlay rendered from the template as overlay.iso, one run of the throwaway guest VM_BAKE_FIRSTBOOT from the live ISO, which takes the overlay from the second CD and installs itself unattended; the installed system boots once more, adds the packages and powers off), 'image close iso' (the digest) and 'image seal' -- no builder and no chroot: an Alpine disk is never mounted on the host
# @group   image
# @internal
# @see     image make alpine
# @see     image create apkovl
# @see     image install apkovl
#@end
___image_make_alpine_from3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image make alpine: template $1, version $2 -> image $3 (create apkovl, install apkovl, close iso, seal)")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image create apkovl $(sq "$1") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image install apkovl $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image close iso $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seal $(sq "$3")"
}

#@help __image_check_apkovl1
# @command image check apkovl <template>
# @summary The template's resolved base is of kind iso, its file is named alpine-<flavor>-<release>-<arch>.iso (a live ISO of Alpine, alpine-virt-3.22.1-x86_64.iso say; the flavor virt carries the kernel linux-virt with the virtio and 9p drivers) and readable, and its resolved bake is apkovl (all read at generation time): a comment line, else an error line
# @group   image
# @internal
# @see     image create apkovl
# @see     template base iso
# @see     template bake apkovl
#@end
__image_check_apkovl1() {
	local cur="$1" chain="" p="" n=0 a="" base="" bake="" kind="" path="" f=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/bake" && IFS= read -r bake < "$VM_BAKE_BASE/template/$a/bake"; done
	kind=${base%% *}; path=$(printf '%s' "$base" | awk '{ print $3 }'); f=${path##*/}
	case "$f" in alpine-*.iso) ;; *) f="" ;; esac
	if test "$kind" = iso && test "$bake" = apkovl && test -n "$f" && test -r "$path"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image: $1 installs from $path by apkovl")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create apkovl: template $1 needs a readable base of kind iso named alpine-*.iso (has ${base:-none}) and the bake apkovl (has ${bake:-none}): template base iso, template bake apkovl")"
	fi
}

#@help ___image_create_apkovl2
# @command image create apkovl <template> <image>
# @summary Step 1 of the Alpine bake, the disk: the template exists with a resource, its base is a live ISO of Alpine and its bake apkovl, the image name is free; then the bake lock, the record, the dataset and an empty disk0.img of the resource's disk size (image disk create) -- setup-disk partitions and fills it
# @group   image
# @internal
# @see     image make alpine
# @see     image install apkovl
# @env     VM_BAKE_IMAGE_DIR  where the image's dataset is created
#@end
___image_create_apkovl2() {
	local cur="$1" chain="" p="" n=0 a="" size=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r size < "$VM_BAKE_BASE/template/$a/resource"; done
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check resource $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check apkovl $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image lock take $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record write $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image dataset create $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk create $(sq "$2") $(sq "${size##* }")"
}

#@help ___image_install_apkovl1
# @command image install apkovl <image>
# @summary Step 2 of the Alpine bake, the installation: the image has a record; then the overlay rendered from the template (image overlay write: the answer file of setup-alpine, the installer hook of the live system and the first boot's script) with the files of the template's file lines (image overlay files place), packed as the apkovl and the apkovl as overlay.iso (image overlay pack), the throwaway guest VM_BAKE_FIRSTBOOT configured with the image's disk and the overlay.iso (image firstboot conf), linked where vm-bhyve looks, run from the template's live ISO (guest install: the ISO rides along for this one run; the live system looks on every mountable device for a *.apkovl.tar.gz, finds ours on the second CD, unpacks it over itself before any service starts, and its local service runs setup-alpine against the answer file), its console read until the installer powers the guest off and, started again from its disk, the first boot reports its packages (image console watch), waited for until bhyve is gone, its link and configuration removed again. The root acts (guest link write, guest install, image console watch, guest link drop) are pinned 'sudo sh'; for one sudo over the whole batch pin image_install_apkovl to 'sudo -E sh -c "$VM_BAKE_BATCH_COMBINATOR_INTERPRETER"' and the acts that write the image's files (the ten acts of image overlay write, image_overlay_files_place, image_overlay_pack, image_firstboot_conf_write, image_firstboot_conf_drop) to 'sudo -u <user> sh', as 'image install' explains
# @group   image
# @internal
# @see     image make alpine
# @see     image overlay write
# @see     image overlay files place
# @see     image overlay pack
# @see     image console watch
# @see     image install
# @see     guest install
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
___image_install_apkovl1() {
	local t="" cur="" chain="" p="" n=0 a="" base="" iso="" srcs=""
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check daemons $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay files place $(sq "$1")"
	srcs=$(awk -v base="$VM_BAKE_BASE" -v family=source -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -z "$srcs" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image $1: source lines are apt sources, an Alpine image takes its packages from the repositories setup-apkrepos picks: $(printf '%s' "$srcs" | awk '{ print $1 }' | tr '\n' ' ')")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay pack $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link write $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest install $(sq "$VM_BAKE_FIRSTBOOT") $(sq "$iso")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image console watch $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot gone"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link drop $(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot conf drop"
}

#@help ___image_overlay_write1
# @command image overlay write <image>
# @summary The overlay of the Alpine bake under VM_BAKE_IMAGE_DIR/<image>/overlay.d, written aspect by aspect; everything lies under etc because setup-disk carries the live system's etc onto the disk (lbu package) and nothing else. 'image overlay answer write' (the answer file of setup-alpine and the link that starts the local service), 'image overlay install write' (the live system's hook: setup-alpine unattended, power off), then the first boot's script etc/local.d/vm-bake-firstboot.start -- 'image overlay firstboot write' (its head: nothing on the live tmpfs, the packages added and checked), 'image overlay sshd write', 'image overlay user write', 'image overlay env write', 'image overlay file write' (the template's files from their staging), 'image overlay view write' (the modules, the view's fstab lines), 'image overlay net write' (root locked, the bake's address, the seed hook as the up command of eth0), 'image overlay report write' (the report line on the console, power off, both hooks executable). Every writer reads the template at generation time and appends to the one file, so the acts run in this order
# @group   image
# @internal
# @see     image install apkovl
# @see     image overlay answer write
# @see     image overlay install write
# @see     image overlay firstboot write
# @see     image overlay sshd write
# @see     image overlay user write
# @see     image overlay env write
# @see     image overlay file write
# @see     image overlay daemon write
# @see     image overlay view write
# @see     image overlay net write
# @see     image overlay report write
# @see     image overlay files place
# @see     image overlay pack
#@end
___image_overlay_write1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay answer write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay install write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay firstboot write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay sshd write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay user write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay env write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay file write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay daemon write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay view write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay net write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image overlay report write $(sq "$1")"
}

#@help _image_overlay_answer_write1
# @command image overlay answer write <image>
# @summary Act terminal: overlay.d begun -- its directories, the link etc/runlevels/default/local that starts the local service on the live system, the marker etc/.default_boot_services (an apkovl is meant to bring its own runlevels: without the marker the live init adds none of its default services -- devfs, mdev, hwdrivers, modloop -- and setup-disk finds no kernel modules for the filesystems it makes), and etc/vm-bake/answerfile, the answers of setup-alpine -f: no keymap, hostname VM_BAKE_FIRSTBOOT, mdev, eth0 static on VM_BAKE_FIRSTBOOT_ADDRESS with the gateway VM_BAKE_GUEST_GATEWAY, DNS domain VM_BAKE_GUEST_DOMAIN and nameserver VM_BAKE_GUEST_GATEWAY, the host's timezone (/var/db/zoneinfo, else UTC), no proxy, the repositories the first mirror of the list and community (-1 -c), no user (the first boot makes the template's users with their host uids), openssh, chrony, the whole disk vda in the sys mode (-m sys), no lbu and no apk cache
# @group   image
# @internal
# @see     image overlay write
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, the hostname of the installation
# @env     VM_BAKE_FIRSTBOOT_ADDRESS  the installation's address, with prefix length
# @env     VM_BAKE_GUEST_GATEWAY  gateway and nameserver of the installation
# @env     VM_BAKE_GUEST_DOMAIN  its DNS domain
#@end
_image_overlay_answer_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" mask="" tz=""
	mask=$(printf '%s\n' "${VM_BAKE_FIRSTBOOT_ADDRESS#*/}" | awk '{ m = $1 ? 4294967296 - 2 ^ (32 - $1) : 0; printf "%d.%d.%d.%d", int(m / 16777216) % 256, int(m / 65536) % 256, int(m / 256) % 256, m % 256 }')
	IFS= read -r tz 2>/dev/null < /var/db/zoneinfo || tz=UTC
	printf '%s\n' "install -d -m 755 '$dir/overlay.d/etc/local.d' '$dir/overlay.d/etc/vm-bake' '$dir/overlay.d/etc/runlevels/default' || exit 1"
	printf '%s\n' "ln -sf /etc/init.d/local '$dir/overlay.d/etc/runlevels/default/local'"
	printf '%s\n' "touch '$dir/overlay.d/etc/.default_boot_services'"
	printf '%s\n' "cat > '$dir/overlay.d/etc/vm-bake/answerfile' <<'EOF_ANSWER'"
	printf '%s\n' "# written by vm-bake (image overlay answer write) -- the answers of setup-alpine -f" "KEYMAPOPTS=none" "HOSTNAMEOPTS=$VM_BAKE_FIRSTBOOT" "DEVDOPTS=mdev" "INTERFACESOPTS=\"auto lo" "iface lo inet loopback" "" "auto eth0" "iface eth0 inet static" "    address ${VM_BAKE_FIRSTBOOT_ADDRESS%/*}" "    netmask $mask" "    gateway $VM_BAKE_GUEST_GATEWAY" "\"" "DNSOPTS=\"-d $VM_BAKE_GUEST_DOMAIN $VM_BAKE_GUEST_GATEWAY\"" "TIMEZONEOPTS=$tz" "PROXYOPTS=none" "APKREPOSOPTS=\"-1 -c\"" "USEROPTS=none" "SSHDOPTS=openssh" "NTPOPTS=chrony" "DISKOPTS=\"-m sys /dev/vda\"" "LBUOPTS=none" "APKCACHEOPTS=none"
	printf '%s\n' "EOF_ANSWER"
	printf '%s\n' "printf '# image %s: answerfile -- setup-alpine for %s on %s netmask %s, gateway %s, timezone %s\\n' $(sq "$1") '$VM_BAKE_FIRSTBOOT' '${VM_BAKE_FIRSTBOOT_ADDRESS%/*}' '$mask' '$VM_BAKE_GUEST_GATEWAY' '$tz' >&2"
}

#@help _image_overlay_install_write1
# @command image overlay install write <image>
# @summary Act terminal: etc/local.d/vm-bake-install.start, run by the local service of the live system: it removes itself first (what stays in etc travels onto the disk), names vda in ERASE_DISKS (setup-disk asks otherwise), runs setup-alpine -e -f against the answer file (-e: no root password prompt; root is locked at the first boot) and reports on the console -- '# vm-bake install: complete, powering off' and the power-off, or '# vm-bake install: failed' (image console watch reads both; the line goes to ttyS0 as well as to the console, whichever the kernel was told)
# @group   image
# @internal
# @see     image overlay write
# @see     image console watch
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_overlay_install_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "cat > '$dir/overlay.d/etc/local.d/vm-bake-install.start' <<'EOF_INSTALL'"
	printf '%s\n' '#!/bin/sh' '# written by vm-bake (image overlay install write) -- run by the local service of the live system: the unattended installation, then power off; what stays in /etc travels onto the disk, so this hook removes itself first' 'exec > /dev/ttyS0 2>&1' 'rm -f /etc/local.d/vm-bake-install.start' 'export ERASE_DISKS=/dev/vda' 'if setup-alpine -e -f /etc/vm-bake/answerfile; then' "	sync; printf '# vm-bake install: complete, powering off\\n' | tee /dev/console; poweroff" 'else' "	printf '# vm-bake install: failed\\n' | tee /dev/console" 'fi'
	printf '%s\n' "EOF_INSTALL"
	printf '%s\n' "printf '# image %s: vm-bake-install.start -- setup-alpine -e -f, ERASE_DISKS=/dev/vda, power off\\n' $(sq "$1") >&2"
}

#@help _image_overlay_firstboot_write1
# @command image overlay firstboot write <image>
# @summary Act terminal: etc/local.d/vm-bake-firstboot.start begun -- it travels onto the disk with etc and does nothing on the live system, whose root is a tmpfs; at the first boot from the disk it removes itself, makes the directories the writers below fill, adds the template's packages (read at generation time) with apk add onto the console, writes apk info into /etc/vm-bake/packages and checks every package against it, one line each, into the variable missing that 'image overlay report write' reports
# @group   image
# @internal
# @see     image overlay write
# @see     image overlay report write
# @see     template package add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_overlay_firstboot_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 pkgs=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	pkgs=$(awk -v base="$VM_BAKE_BASE" -v family=package -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "cat > '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start' <<'EOF_FIRST'"
	printf '%s\n' '#!/bin/sh' "# written by vm-bake (image overlay write) -- the bake's first boot from the disk (on the live system, whose root is a tmpfs, it does nothing): the packages, each checked against apk info, sshd, the users, the seed hook, the report line on the console, then power off; the host seals the disk" "test \"\$(awk '\$2 == \"/\" { print \$3 }' /proc/mounts)\" != tmpfs || exit 0"  'exec > /dev/ttyS0 2>&1' 'rm -f /etc/local.d/vm-bake-firstboot.start' 'install -d -m 755 /etc/ssh/authorized_keys /etc/vm-bake /etc/profile.d /usr/local/libexec /media/vmbake'
	test -z "$pkgs" || printf '%s\n' "apk add --no-progress $(printf '%s\n' "$pkgs" | tr '\n' ' ')2>&1 | tee /dev/console"
	printf '%s\n' "apk info > /etc/vm-bake/packages"
	printf '%s\n' "missing="
	for p in $pkgs; do printf '%s\n' "grep -qx '$p' /etc/vm-bake/packages || missing=\"\$missing $p\""; done
	printf '%s\n' "EOF_FIRST"
	printf '%s\n' "printf '# image %s: vm-bake-firstboot.start begun -- %s packages, each checked\\n' $(sq "$1") '$(printf '%s\n' "$pkgs" | grep -c . || true)' >&2"
}

#@help _image_overlay_sshd_write1
# @command image overlay sshd write <image>
# @summary Act terminal: appended to the first boot's script -- sshd: the stock lines for Port, PermitRootLogin, PasswordAuthentication, KbdInteractiveAuthentication and AuthorizedKeysFile commented out, then VM_BAKE_SSH_PORT, no root, keys only under /etc/ssh/authorized_keys/<user>
# @group   image
# @internal
# @see     image overlay write
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_SSH_PORT  the port sshd listens on in every guest
#@end
_image_overlay_sshd_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "cat >> '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start' <<'EOF_FIRST'"
	printf '%s\n' "sed -i -E 's/^[[:space:]]*(Port|PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|AuthorizedKeysFile|X11Forwarding)[[:space:]]/#&/' /etc/ssh/sshd_config"
	printf '%s\n' "cat >> /etc/ssh/sshd_config <<'EOF_SSHD'" "Port $VM_BAKE_SSH_PORT" "PermitRootLogin no" "PasswordAuthentication no" "KbdInteractiveAuthentication no" "AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys" "EOF_SSHD"
	printf '%s\n' "EOF_FIRST"
	printf '%s\n' "printf '# image %s: the first boot -- sshd on %s, no root, keys only\\n' $(sq "$1") '$VM_BAKE_SSH_PORT' >&2"
}

#@help _image_overlay_user_write1
# @command image overlay user write <image>
# @summary Act terminal: the template's users (read at generation time) appended to the first boot's script -- adduser with the host's uid for 'host', in wheel, /bin/sh, no password (the shadow field set to * so that sshd takes the key: adduser -D writes !, which OpenSSH reads as locked), VM_BAKE_HOST_KEY as the key under /etc/ssh/authorized_keys/<user>; when the template's packages name doas (a package here, added by the first boot), /etc/doas.conf gets 'permit nopass keepenv <user> as root' for each. No users: a comment
# @group   image
# @internal
# @see     image overlay write
# @see     template user add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_HOST_KEY  the public key of the host, every user's authorized key
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_overlay_user_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 users="" key="$VM_BAKE_HOST_KEY" keytext="" line="" u="" s="" uid="" doas=no oifs="$IFS"
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	awk -v base="$VM_BAKE_BASE" -v family=package -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx doas && doas=yes
	test -n "$users" || { printf '%s\n' "# image $1: no users in $t -- the first boot makes none"; return 0; }
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	keytext=$(cat "$key" 2>/dev/null || true)
	printf '%s\n' "cat >> '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start' <<'EOF_FIRST'"
	IFS='
'; set -- $users; IFS=$oifs
	for line; do
		u=${line%% *}; s=${line#* }; uid=$s
		test "$s" != host || uid=$(id -u "$u" 2>/dev/null || true)
		printf '%s\n' "adduser -D${uid:+ -u $uid} -G wheel -s /bin/sh '$u'"
		printf '%s\n' "sed -i 's/^$u:!:/$u:*:/' /etc/shadow"
		printf '%s\n' "printf '%s\\n' '$keytext' > '/etc/ssh/authorized_keys/$u' && chmod 644 '/etc/ssh/authorized_keys/$u'"
	done
	if test "$doas" = yes; then
		printf '%s\n' "cat >> /etc/doas.conf <<'EOF_DOAS'"
		for line; do printf '%s\n' "permit nopass keepenv ${line%% *} as root"; done
		printf '%s\n' "EOF_DOAS" "chmod 600 /etc/doas.conf"
	fi
	printf '%s\n' "EOF_FIRST"
	printf '%s\n' "printf '# image %s: the first boot -- users %s, doas %s\\n' $(sq "$1") $(sq "$(printf '%s\n' "$users" | awk '{ print $1 }' | tr '\n' ' ' | sed 's/ $//')") '$doas' >&2"
}

#@help _image_overlay_env_write1
# @command image overlay env write <image>
# @summary Act terminal: the template's env lines (read at generation time) appended to the first boot's script as /etc/profile.d/vm-bake.sh, export lines, the sessions' environment. No env lines: a comment
# @group   image
# @internal
# @see     image overlay write
# @see     template env add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_overlay_env_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 envl=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	envl=$(awk -v base="$VM_BAKE_BASE" -v family=env -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | sed 's/^\([^=]*\)=\(.*\)$/export \1="\2"/')
	test -n "$envl" || { printf '%s\n' "# image $1: no env lines in $t -- no profile.d file"; return 0; }
	printf '%s\n' "cat >> '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start' <<'EOF_FIRST'"
	printf '%s\n' "cat > /etc/profile.d/vm-bake.sh <<'EOF_ENV'" "# written by vm-bake (template env) -- the sessions' environment"
	printf '%s\n' "$envl"
	printf '%s\n' "EOF_ENV" "EOF_FIRST"
	printf '%s\n' "printf '# image %s: the first boot -- %s env lines as /etc/profile.d/vm-bake.sh\\n' $(sq "$1") '$(printf '%s\n' "$envl" | grep -c .)' >&2"
}

#@help _image_overlay_file_write1
# @command image overlay file write <image>
# @summary Act terminal: the template's file lines (read at generation time) appended to the first boot's script -- each file installed from its staging under /etc/vm-bake/files (image overlay files place puts it there) at its path with the mode of the line, one line per file, then the staging removed. No file lines: a comment
# @group   image
# @internal
# @see     image overlay write
# @see     image overlay files place
# @see     template file add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_overlay_file_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 files="" line=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	files=$(awk -v base="$VM_BAKE_BASE" -v family=file -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -n "$files" || { printf '%s\n' "# image $1: no file lines in $t -- the first boot installs none"; return 0; }
	printf '%s\n' "cat >> '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start' <<'EOF_FIRST'"
	printf '%s\n' "$files" | while IFS= read -r line; do
		set -- $line
		printf '%s\n' "install -d -m 755 '$(dirname "$2")' && install -m $3 '/etc/vm-bake/files$2' '$2'"
	done
	printf '%s\n' "rm -rf /etc/vm-bake/files" "EOF_FIRST"
	printf '%s\n' "printf '# image %s: the first boot -- %s files from their staging\\n' $(sq "$1") '$(printf '%s\n' "$files" | grep -c .)' >&2"
}

#@help _image_overlay_view_write1
# @command image overlay view write <image>
# @summary Act terminal: appended to the first boot's script -- the modules sr_mod and isofs into /etc/modules (the seed CD), and when the template says 'service files view' (read at generation time) 9p and 9pnet_virtio too, /var/git made and given to the host-uid user, and the fstab lines of the view: the share home over 9p (trans=virtio, 9p2000.L) on that user's home and the bind of /var/git to VM_BAKE_REPO_LOCAL below it; a template without a view gets the CD modules alone
# @group   image
# @internal
# @see     image overlay write
# @see     image seed view write
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_REPO_LOCAL  the clones' directory under the guest's home
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_overlay_view_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 svc="" hostuser="" view=no
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	svc=$(awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	hostuser=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | awk '$2 == "host" { print $1; exit }')
	printf '%s\n' "$svc" | grep -qx 'files view' && view=yes
	printf '%s\n' "cat >> '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start' <<'EOF_FIRST'"
	printf '%s\n' "printf '%s\\n' sr_mod isofs >> /etc/modules"
	if test "$view" = yes; then
		printf '%s\n' "printf '%s\\n' 9p 9pnet_virtio >> /etc/modules" "install -d -m 755 /var/git '/home/$hostuser/$VM_BAKE_REPO_LOCAL' && chown '$hostuser:$hostuser' /var/git"
		printf '%s\n' "printf '%s\\n' 'home /home/$hostuser 9p trans=virtio,version=9p2000.L,rw,nofail 0 0' '/var/git /home/$hostuser/$VM_BAKE_REPO_LOCAL none bind,nofail 0 0' >> /etc/fstab"
	fi
	printf '%s\n' "EOF_FIRST"
	printf '%s\n' "printf '# image %s: the first boot -- CD modules, view %s\\n' $(sq "$1") '$view' >&2"
}

#@help _image_overlay_net_write1
# @command image overlay net write <image>
# @summary Act terminal: appended to the first boot's script -- root locked (passwd -l), the bake's address, netmask and gateway under /etc/vm-bake, the seed hook /usr/local/libexec/vm-bake-seed and /etc/network/interfaces with eth0 manual and the hook as its up command: at every boot the hook looks on sr0 and sr1 for a seed CD (guest seed write autoinstall -- the same CD an OpenBSD guest reads: the marker vm-bake-seed, address, netmask, myname, mygate, resolv.conf and the ssh host key), takes what it finds (the hostname is the first label of myname) and configures eth0 and the default route; without a seed the bake's address holds. The two CD devices are two calls of one function in the hook, no loop
# @group   image
# @internal
# @see     image overlay write
# @see     guest seed write autoinstall
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_FIRSTBOOT_ADDRESS  the bake's address, with prefix length
# @env     VM_BAKE_GUEST_GATEWAY  the bake's gateway
#@end
_image_overlay_net_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" mask=""
	mask=$(printf '%s\n' "${VM_BAKE_FIRSTBOOT_ADDRESS#*/}" | awk '{ m = $1 ? 4294967296 - 2 ^ (32 - $1) : 0; printf "%d.%d.%d.%d", int(m / 16777216) % 256, int(m / 65536) % 256, int(m / 256) % 256, m % 256 }')
	printf '%s\n' "cat >> '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start' <<'EOF_FIRST'"
	printf '%s\n' "passwd -l root"
	printf '%s\n' "printf '%s\\n' '${VM_BAKE_FIRSTBOOT_ADDRESS%/*}' > /etc/vm-bake/address" "printf '%s\\n' '$mask' > /etc/vm-bake/netmask" "printf '%s\\n' '$VM_BAKE_GUEST_GATEWAY' > /etc/vm-bake/gateway"
	printf '%s\n' "cat > /usr/local/libexec/vm-bake-seed <<'EOF_SEED'" '#!/bin/sh' "# written by vm-bake (image overlay net write) -- the up command of eth0: a seed CD (guest seed write autoinstall) names, addresses and keys this guest; without one, the address of the bake" 'a=$(cat /etc/vm-bake/address) m=$(cat /etc/vm-bake/netmask) g=$(cat /etc/vm-bake/gateway)' 'seed() {' '	mount -r -t iso9660 "$1" /media/vmbake 2>/dev/null || return 0' '	if test -f /media/vmbake/vm-bake-seed; then' '		a=$(cat /media/vmbake/address) m=$(cat /media/vmbake/netmask) g=$(cat /media/vmbake/mygate)' '		cut -d. -f1 /media/vmbake/myname > /etc/hostname' '		cp /media/vmbake/resolv.conf /etc/resolv.conf' '		install -m 600 /media/vmbake/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key' '		install -m 644 /media/vmbake/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub' '		hostname -F /etc/hostname' '	fi' '	umount /media/vmbake' '}' 'seed /dev/sr0' 'seed /dev/sr1' 'ifconfig eth0 "$a" netmask "$m" up' 'route add default gw "$g" 2>/dev/null || true' "EOF_SEED"
	printf '%s\n' "chmod 755 /usr/local/libexec/vm-bake-seed"
	printf '%s\n' "cat > /etc/network/interfaces <<'EOF_IF'" "auto lo" "iface lo inet loopback" "" "auto eth0" "iface eth0 inet manual" "    up /usr/local/libexec/vm-bake-seed" "EOF_IF"
	printf '%s\n' "EOF_FIRST"
	printf '%s\n' "printf '# image %s: the first boot -- root locked, %s netmask %s gateway %s as the bake address, the seed hook as the up command of eth0\\n' $(sq "$1") '${VM_BAKE_FIRSTBOOT_ADDRESS%/*}' '$mask' '$VM_BAKE_GUEST_GATEWAY' >&2"
}

#@help _image_overlay_report_write1
# @command image overlay report write <image>
# @summary Act terminal: the end of the first boot's script -- the report '# vm-bake firstboot: missing <packages>' (the variable missing of image overlay firstboot write) or '# vm-bake firstboot: packages complete' on the console and on ttyS0 (image console watch reads it), sync and power off; then both hooks of the overlay made executable
# @group   image
# @internal
# @see     image overlay write
# @see     image overlay firstboot write
# @see     image console watch
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_overlay_report_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "cat >> '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start' <<'EOF_FIRST'"
	printf '%s\n' "test -n \"\$missing\" && printf '# vm-bake firstboot: missing%s\\n' \"\$missing\" | tee /dev/console || printf '# vm-bake firstboot: packages complete\\n' | tee /dev/console"
	printf '%s\n' "sync; poweroff" "EOF_FIRST"
	printf '%s\n' "chmod 755 '$dir/overlay.d/etc/local.d/vm-bake-install.start' '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start'"
	printf '%s\n' "printf '# image %s: vm-bake-firstboot.start done -- the report line, power off; both hooks executable\\n' $(sq "$1") >&2"
}

#@help _image_overlay_files_place1
# @command image overlay files place <image>
# @summary Act terminal: the template's file lines (read at generation time) into the overlay of an Alpine image -- each dowry's object under VM_BAKE_IMAGE_DIR/<image>/overlay.d/etc/vm-bake/files at its path with the mode of the line, because only etc travels from the live system onto the disk; the first boot (image overlay write) installs each at its path and removes the staging directory. No file lines: a comment
# @group   image
# @internal
# @see     image install apkovl
# @see     image overlay write
# @see     image overlay pack
# @see     template file add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_overlay_files_place1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 files="" line=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	files=$(awk -v base="$VM_BAKE_BASE" -v family=file -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	if test -z "$files"; then
		printf '%s\n' "# image $1: no file lines in $t -- the overlay carries the answer file and the two hooks alone"
		return 0
	fi
	printf '%s\n' "$files" | while IFS= read -r line; do
		set -- $line
		printf '%s\n' "install -d -m 755 '$dir/overlay.d/etc/vm-bake/files$(dirname "$2")' && install -m $3 '$VM_BAKE_BASE/dowry/$1/object' '$dir/overlay.d/etc/vm-bake/files$2' || exit 1"
	done
	printf '%s\n' "printf '# image %s: %s files from dowries in the overlay\\n' $(sq "$1") '$(printf '%s\n' "$files" | grep -c .)' >&2"
}

#@help _image_overlay_pack1
# @command image overlay pack <image>
# @summary Act terminal: the files and links of overlay.d packed as VM_BAKE_IMAGE_DIR/<image>/overlay/vmbake.apkovl.tar.gz (bsdtar from a find list, owned by root:root; the files alone, no directory entry: the live system unpacks the overlay over its root), then the overlay directory becomes overlay.iso (makefs cd9660, rockridge, label vmbakeovl), the CD the throwaway guest carries besides the live ISO -- the live system's init mounts every block device that carries a filesystem and takes the first *.apkovl.tar.gz it finds in a root directory
# @group   image
# @internal
# @see     image install apkovl
# @see     image overlay write
# @see     image overlay files place
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_overlay_pack1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1"
	printf '%s\n' "install -d -m 700 '$dir/overlay' || exit 1"
	printf '%s\n' "(cd '$dir/overlay.d' && find . -type f -o -type l | sed 's|^\\./||' | bsdtar -czf '$dir/overlay/vmbake.apkovl.tar.gz' --uid 0 --gid 0 --uname root --gname root -n -T -) || exit 1"
	printf '%s\n' "rm -f '$dir/overlay.iso' && makefs -t cd9660 -o rockridge -o label=vmbakeovl '$dir/overlay.iso' '$dir/overlay' && chmod 600 '$dir/overlay.iso' || exit 1"
	printf '%s\n' "printf '# image %s: overlay.iso -- vmbake.apkovl.tar.gz with %s entries\\n' $(sq "$1") \"\$(cd '$dir/overlay.d' && find . -type f -o -type l | wc -l | tr -d ' ')\" >&2"
}

#@help __image_console_watch1
# @command image console watch <image>
# @summary The throwaway guest's serial console read while the live system installs and the first boot reports, by VM_BAKE_CONSOLE (the way vm-bhyve offers consoles): rewrite to 'image console watch tmux <image>' or 'image console watch nmdm <image>' -- nothing is typed, the overlay answers everything
# @group   image
# @internal
# @see     image install apkovl
# @see     image console drive
# @env     VM_BAKE_CONSOLE  tmux or nmdm, vm-bhyve's console= setting
#@end
__image_console_watch1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image console watch $(sq "$VM_BAKE_CONSOLE") $(sq "$1")"
}

#@help __image_console_watch2
# @internal dispatch fallback of 'image console watch <console> <image>' for a console that is neither tmux nor nmdm: an error line
#@end
__image_console_watch2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image console watch: VM_BAKE_CONSOLE is $1, which is no console of vm-bhyve (tmux | nmdm)")"
}

#@help _image_console_watch_tmux1
# @command image console watch tmux <image>
# @summary Act terminal (root): the installation of the throwaway guest watched over vm-bhyve's tmux session (capture-pane reads; nothing is typed): the live system's hook (image overlay write) reports '# vm-bake install: complete, powering off' or '# vm-bake install: failed' (the latter ends the wait at once); when the guest is down it is started again with 'vm start', from its disk (vm-bhyve keeps the live ISO first in the boot order through every restart of its run loop, so a reboot would run the live system and its installer once more) -- that is the first boot, and the watch stays on the console until the first boot's script reports: '# vm-bake firstboot: missing <packages>' ends the bake with an error naming them, '# vm-bake firstboot: packages complete' hands over to 'image firstboot gone'. Every wait has its seconds and ends in an error with the last screen and the guest powered off (vm poweroff -f): a guest whose install went wrong sits in vm-bhyve's restart loop otherwise, and the next 'guest install' would find it running
# @group   image
# @internal
# @see     image console watch
# @see     image overlay write
# @see     image console drive tmux
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, the tmux session
# @env     VM_BAKE_CONSOLE  tmux or nmdm, named in the error when the session or the device does not appear
#@end
_image_console_watch_tmux1() {
	printf '%s\n' "g=$(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' 'pane() { tmux capture-pane -p -t "$g" 2>/dev/null || true; }'
	printf '%s\n' 'n=0; until tmux has-session -t "$g" 2>/dev/null; do n=$((n + 1)); test "$n" -lt 60 || { printf "# Error: console %s: no tmux session within a minute (VM_BAKE_CONSOLE says tmux; vm-bhyve console= in system.conf?)\n" "$g" >&2; exit 1; }; sleep 1; done'
	cat <<'EOF_STEPS'
give_up() { printf '# Error: console %s: %s\n' "$g" "$1" >&2; pane | tail -15 >&2; vm poweroff -f "$g" >/dev/null 2>&1; printf '# console %s: powered off\n' "$g" >&2; exit 1; }
wait_for() { n=0; until pane | grep -- "$1" >/dev/null; do pane | grep "# vm-bake install: failed" >/dev/null && give_up "setup-alpine failed on the live system before $1"; n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 within $2 s"; sleep 1; done; }
wait_for '# vm-bake install: complete' 1800
n=0; until vm list | grep "^$g  *.*Stopped" >/dev/null; do n=$((n + 1)); test "$n" -le 60 || give_up "still running two minutes after the installer's power-off"; sleep 2; done
vm start "$g" >&2 || give_up "vm start failed after the install"
printf '# console %s: installed, powered off by the installer and started again from its disk for the first boot\n' "$g" >&2
wait_for '# vm-bake firstboot:' 1800
pane | grep -q '# vm-bake firstboot: missing' && give_up "the first boot left packages out: $(pane | grep '# vm-bake firstboot: missing' | tail -1 | tr -d '\r' | sed 's/.*missing //')"
printf '# console %s: the first boot reports its packages complete\n' "$g" >&2
EOF_STEPS
}

#@help _image_console_watch_nmdm1
# @command image console watch nmdm <image>
# @summary Act terminal (root): the same watch as 'image console watch tmux', over vm-bhyve's nmdm pair -- /dev/nmdm-<firstboot>.1B opened once on descriptor 3 in raw mode without echo (a freshly opened tty would send every byte the guest prints back into it as keystrokes), read into VM_BAKE_GUEST_DIR/<firstboot>/console.log by a cat in the background, the last forty lines standing for the screen
# @group   image
# @internal
# @see     image console watch
# @see     image console drive nmdm
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, in the device name
# @env     VM_BAKE_GUEST_DIR  the guests' directory, where the console log lies
# @env     VM_BAKE_CONSOLE  tmux or nmdm, named in the error when the session or the device does not appear
#@end
_image_console_watch_nmdm1() {
	printf '%s\n' "g=$(sq "$VM_BAKE_FIRSTBOOT") dev=$(sq "/dev/nmdm-$VM_BAKE_FIRSTBOOT.1B") log=$(sq "$VM_BAKE_GUEST_DIR/$VM_BAKE_FIRSTBOOT/console.log")"
	printf '%s\n' 'n=0; until test -c "$dev"; do n=$((n + 1)); test "$n" -lt 60 || { printf "# Error: console %s: no %s within a minute (VM_BAKE_CONSOLE says nmdm; vm-bhyve console= in system.conf?)\n" "$g" "$dev" >&2; exit 1; }; sleep 1; done'
	printf '%s\n' 'exec 3<> "$dev"; stty raw -echo <&3'
	printf '%s\n' ': > "$log"; cat <&3 >> "$log" & rd=$!' 'trap '"'"'kill "$rd" 2>/dev/null'"'"' EXIT'
	printf '%s\n' 'pane() { tail -n 40 "$log" 2>/dev/null | tr -d "\r" | cat -v; }'
	cat <<'EOF_STEPS'
give_up() { printf '# Error: console %s: %s\n' "$g" "$1" >&2; pane | tail -15 >&2; vm poweroff -f "$g" >/dev/null 2>&1; printf '# console %s: powered off\n' "$g" >&2; exit 1; }
wait_for() { n=0; until pane | grep -- "$1" >/dev/null; do pane | grep "# vm-bake install: failed" >/dev/null && give_up "setup-alpine failed on the live system before $1"; n=$((n + 1)); test "$n" -lt "$2" || give_up "no $1 within $2 s"; sleep 1; done; }
wait_for '# vm-bake install: complete' 1800
n=0; until vm list | grep "^$g  *.*Stopped" >/dev/null; do n=$((n + 1)); test "$n" -le 60 || give_up "still running two minutes after the installer's power-off"; sleep 2; done
vm start "$g" >&2 || give_up "vm start failed after the install"
printf '# console %s: installed, powered off by the installer and started again from its disk for the first boot\n' "$g" >&2
wait_for '# vm-bake firstboot:' 1800
pane | grep -q '# vm-bake firstboot: missing' && give_up "the first boot left packages out: $(pane | grep '# vm-bake firstboot: missing' | tail -1 | tr -d '\r' | sed 's/.*missing //')"
printf '# console %s: the first boot reports its packages complete\n' "$g" >&2
EOF_STEPS
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
# @summary The template of the image (read at generation time) can be rendered as a NoCloud seed: when it says 'service files view', exactly one of its users has uid host -- that user's home is the view; every file line names a dowry whose object is one file (the seed carries it as write_files content); a comment line, else an error line
# @group   image
# @internal
# @see     image seed write
# @see     template user add
# @see     template file add
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
__image_check_seed1() {
	local t="" cur="" chain="" p="" n=0 users="" svc="" seen=0 gone=""
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
	for p in $(awk -v base="$VM_BAKE_BASE" -v family=file -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | awk '{ print $1 }'); do test -f "$VM_BAKE_BASE/dowry/$p/object" || gone="$gone $p"; done
	if printf '%s\n' "$svc" | grep -qx 'files view' && test "$seen" -ne 1; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image seed write: the view is the home of the template's host-uid user, and $t has $seen of them (template user add <template> <name> host)")"
	elif test -n "$gone"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image seed write: the file lines of $t name dowries that are not one file in the database:$gone (dowry add <dowry> <file>, or template file drop)")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1: the template $t renders as a seed")"
	fi
}

#@help ___image_seed_write1
# @command image seed write <image>
# @summary The NoCloud seed of the bake, VM_BAKE_IMAGE_DIR/<image>/seed.iso: 'image check seed' (a view needs exactly one host-uid user, every file line a dowry that is one file), for each source line of the template its key fetched and verified (image key fetch, image key verify), then the acts -- 'image seed meta write' (meta-data: instance-id bake-<image>, hostname VM_BAKE_FIRSTBOOT), 'image seed net write' (network-config: VM_BAKE_FIRSTBOOT_ADDRESS static on the MAC derived from it, gateway and nameserver VM_BAKE_GUEST_GATEWAY), 'image seed user write' (user-data begins: packages and users of the template), 'image seed source write' (the apt sources with their keys), 'image seed sshd write' (write_files: sshd on VM_BAKE_SSH_PORT without root or passwords, the authorized key of every user, the env lines as /etc/profile.d/vm-bake.sh), 'image seed file write' (the file lines continue write_files), 'image seed check write' (the first boot's package check, its report on the console), 'image seed view write' (the 9p mounts when the template says 'service files view'), 'image seed pack' (power_state poweroff, makefs). The template's rc lines are FreeBSD's rc.conf and are noted, not written (read at generation time)
# @group   image
# @internal
# @see     image firstboot
# @see     image check seed
# @see     image seed pack
# @see     image view write
# @see     image seed source write
# @see     image seed file write
# @see     image seed check write
# @see     image seed daemon write
# @see     image check daemons
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
___image_seed_write1() {
	local t="" cur="" chain="" p="" n=0 rcl="" line=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	rcl=$(awk -v base="$VM_BAKE_BASE" -v family=rc -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check seed $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check daemons $(sq "$1")"
	test -z "$rcl" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image $1: rc lines are FreeBSD's rc.conf, a Linux image ignores them: $(printf '%s' "$rcl" | tr '\n' ' ')")"
	awk -v base="$VM_BAKE_BASE" -v family=source -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | while IFS= read -r line; do
		set -- $line
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image key fetch $(sq "$1") $(sq "$5")" "\"\$VM_BAKE_CONTEXT_SCRIPT\" image key verify $(sq "$1") $(sq "$6")"
	done
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed meta write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed net write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed user write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed source write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed sshd write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed file write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed check write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed daemon write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed view write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seed pack $(sq "$1")"
}

#@help _image_key_fetch2
# @command image key fetch <name> <url>
# @summary Act terminal: the signing key of a package source (template source add) fetched into VM_BAKE_IMAGE_CACHE as <name>.asc unless already there (fetch(1)); the base name of the url is no name -- every repository calls its key 'gpg'
# @group   image
# @internal
# @see     image seed write
# @see     image key verify
# @env     VM_BAKE_IMAGE_CACHE  the directory the keys are fetched into, beside the VM images
#@end
_image_key_fetch2() {
	local f="$VM_BAKE_IMAGE_CACHE/$1.asc"
	printf '%s\n' "test -f '$f' && printf '# image: key %s cached\\n' '$f' >&2 || fetch -q -o '$f' $(sq "$2") || exit 1"
}

#@help _image_key_verify2
# @command image key verify <name> <sha256>
# @summary Act terminal: the sha256 of the cached key <name>.asc equals the template's source line, else the file is removed and the bake fails -- a key that changed is a key to look at, not to trust
# @group   image
# @internal
# @see     image key fetch
# @env     VM_BAKE_IMAGE_CACHE  the directory the keys lie in
#@end
_image_key_verify2() {
	local f="$VM_BAKE_IMAGE_CACHE/$1.asc"
	printf '%s\n' "d=\$(sha256 -q '$f') || exit 1"
	printf '%s\n' "test \"\$d\" = $(sq "$2") || { printf '# Error: key %s: sha256 %s, the template says %s (file removed)\\n' '$f' \"\$d\" $(sq "$2") >&2; rm -f '$f'; exit 1; }"
	printf '%s\n' "printf '# image: key %s verified (%s)\\n' '$f' \"\$d\" >&2"
}

#@help _image_seed_source_write1
# @command image seed source write <image>
# @summary Act terminal: the apt sources of user-data from the template's source lines (read at generation time) -- apt.sources.<name> with 'deb [signed-by=$KEY_FILE] <url> <suite> <component>' and the key read from VM_BAKE_IMAGE_CACHE/<name>.asc when the act runs (image key fetch and image key verify went before); cloud-init writes the key beside the list and installs the template's packages from the source. No source lines: a comment
# @group   image
# @internal
# @see     image seed write
# @see     template source add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_IMAGE_CACHE  the directory the keys lie in
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_seed_source_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 srcs="" line=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	srcs=$(awk -v base="$VM_BAKE_BASE" -v family=source -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	if test -z "$srcs"; then
		printf '%s\n' "# image $1: no source lines in $t -- the distribution's own packages only"
		return 0
	fi
	printf '%s\n' "{ printf 'apt:\\n  sources:\\n'"
	printf '%s\n' "$srcs" | while IFS= read -r line; do
		set -- $line
		printf '%s\n' "  printf '    %s:\\n      source: \"deb [signed-by=\$KEY_FILE] %s %s %s\"\\n      key: |\\n' '$1' '$2' '$3' '$4'"
		printf '%s\n' "  sed 's/^/        /' '$VM_BAKE_IMAGE_CACHE/$1.asc'"
	done
	printf '%s\n' "} >> '$dir/seed/user-data'"
	printf '%s\n' "printf '# image %s: %s apt sources\\n' $(sq "$1") '$(printf '%s\n' "$srcs" | grep -c .)' >&2"
}

#@help _image_seed_file_write1
# @command image seed file write <image>
# @summary Act terminal: the template's file lines (read at generation time) continue the write_files of user-data (image seed sshd write opened the list) -- each dowry's object as base64 (uuencode -m), owner root, the mode of the line; the object is read at generation time, so the seed carries it. No file lines: a comment
# @group   image
# @internal
# @see     image seed write
# @see     template file add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_seed_file_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 files="" line=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	files=$(awk -v base="$VM_BAKE_BASE" -v family=file -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	if test -z "$files"; then
		printf '%s\n' "# image $1: no file lines in $t -- nothing beyond the seed's own files"
		return 0
	fi
	printf '%s\n' "cat >> '$dir/seed/user-data' <<'EOF_FILES'"
	printf '%s\n' "$files" | while IFS= read -r line; do
		set -- $line
		printf '%s\n' "  - path: $2" "    permissions: '$3'" "    owner: root:root" "    encoding: b64" "    content: |"
		uuencode -m -r x < "$VM_BAKE_BASE/dowry/$1/object" | sed 's/^/      /'
	done
	printf '%s\n' "EOF_FILES"
	printf '%s\n' "printf '# image %s: %s files from dowries\\n' $(sq "$1") '$(printf '%s\n' "$files" | grep -c .)' >&2"
}

#@help _image_seed_check_write1
# @command image seed check write <image>
# @summary Act terminal: the first boot's package check continues the write_files of user-data -- /var/lib/cloud/scripts/per-once/vm-bake-packages.sh, which cloud-init runs in its final stage after the packages are installed (runcmd runs before them on Debian): the installed packages into /etc/vm-bake/packages, every package of the template (read at generation time) asked of dpkg-query, the report line on the console that 'image firstboot report' waits for ('# vm-bake firstboot: missing <packages>' or '# vm-bake firstboot: packages complete'); then cloud-init powers the guest off. apt fails loudly where pkg_add -I was silent, but a bake that reads only the exit of the first boot sees neither
# @group   image
# @internal
# @see     image seed write
# @see     image firstboot report
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_seed_check_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 pkgs=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	pkgs=$(awk -v base="$VM_BAKE_BASE" -v family=package -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | tr '\n' ' ' | sed 's/ $//')
	printf '%s\n' "cat >> '$dir/seed/user-data' <<'EOF_CHECK'"
	printf '%s\n' "  - path: /var/lib/cloud/scripts/per-once/vm-bake-packages.sh" "    permissions: '0755'" "    content: |"
	printf '%s\n' "      #!/bin/sh" "      # written by vm-bake (image seed check write) -- the bake's first boot, after the packages: each checked against dpkg, the report line on the console"
	printf '%s\n' "      install -d -m 755 /etc/vm-bake" "      dpkg-query -W -f='\${binary:Package} \${Version}\\n' > /etc/vm-bake/packages" "      missing="
	for p in $pkgs; do printf '%s\n' "      dpkg-query -W -f='\${Status}' $p 2>/dev/null | grep -q 'install ok installed' || missing=\"\$missing $p\""; done
	printf '%s\n' "      test -n \"\$missing\" && printf '# vm-bake firstboot: missing%s\\n' \"\$missing\" > /dev/console || printf '# vm-bake firstboot: packages complete\\n' > /dev/console"
	printf '%s\n' "EOF_CHECK"
}

#@help __image_firstboot_report0
# @command image firstboot report
# @summary The first boot's package report read from the throwaway guest's serial console, by VM_BAKE_CONSOLE (the way vm-bhyve offers consoles): rewrite to 'image firstboot report tmux' or 'image firstboot report nmdm'
# @group   image
# @internal
# @see     image firstboot
# @see     image seed check write
# @env     VM_BAKE_CONSOLE  tmux or nmdm, vm-bhyve's console= setting
#@end
__image_firstboot_report0() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image firstboot report $(sq "$VM_BAKE_CONSOLE")"
}

#@help __image_firstboot_report1
# @internal dispatch fallback of 'image firstboot report <console>' for a console that is neither tmux nor nmdm: an error line
#@end
__image_firstboot_report1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image firstboot report: VM_BAKE_CONSOLE is $1, which is no console of vm-bhyve (tmux | nmdm)")"
}

#@help _image_firstboot_report_tmux0
# @command image firstboot report tmux
# @summary Act terminal (root): the report line of the first boot's package check waited for on vm-bhyve's tmux session of the throwaway guest (capture-pane with the whole history: the shutdown that follows the line scrolls it off the screen within seconds), up to an hour -- apt downloads the packages; '# vm-bake firstboot: missing <packages>' ends the bake with an error naming them and powers the guest off (vm poweroff -f), a session that ends without a report is the same error, '# vm-bake firstboot: packages complete' hands over to 'image firstboot gone'
# @group   image
# @internal
# @see     image firstboot report
# @see     image console drive tmux
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, the tmux session
# @env     VM_BAKE_CONSOLE  tmux or nmdm, named in the error when the session or the device does not appear
#@end
_image_firstboot_report_tmux0() {
	printf '%s\n' "g=$(sq "$VM_BAKE_FIRSTBOOT")"
	printf '%s\n' 'hist() { tmux capture-pane -p -S - -t "$g" 2>/dev/null || true; }'
	printf '%s\n' 'n=0; until tmux has-session -t "$g" 2>/dev/null; do n=$((n + 1)); test "$n" -lt 60 || { printf "# Error: firstboot %s: no tmux session within a minute (VM_BAKE_CONSOLE says tmux; vm-bhyve console= in system.conf?)\n" "$g" >&2; exit 1; }; sleep 1; done'
	cat <<'EOF_REPORT'
give_up() { printf '# Error: firstboot %s: %s\n' "$g" "$1" >&2; hist | tail -15 >&2; vm poweroff -f "$g" >/dev/null 2>&1; exit 1; }
n=0; until hist | grep -q '# vm-bake firstboot:'; do tmux has-session -t "$g" 2>/dev/null || give_up "the first boot ended without a package report"; n=$((n + 1)); test "$n" -lt 3600 || give_up "no package report within an hour"; sleep 1; done
hist | grep -q '# vm-bake firstboot: missing' && give_up "the first boot left packages out: $(hist | grep '# vm-bake firstboot: missing' | tail -1 | tr -d '\r' | sed 's/.*missing //')"
printf '# firstboot %s: the first boot reports its packages complete\n' "$g" >&2
EOF_REPORT
}

#@help _image_firstboot_report_nmdm0
# @command image firstboot report nmdm
# @summary Act terminal (root): the same wait as 'image firstboot report tmux', over vm-bhyve's nmdm pair -- /dev/nmdm-<firstboot>.1B opened once on descriptor 3 in raw mode without echo and read into VM_BAKE_GUEST_DIR/<firstboot>/console.log by a cat in the background (the whole log stands for the history), the device waited for a minute
# @group   image
# @internal
# @see     image firstboot report
# @see     image console drive nmdm
# @env     VM_BAKE_FIRSTBOOT  the throwaway guest's name, in the device name
# @env     VM_BAKE_GUEST_DIR  the guests' directory, where the console log lies
# @env     VM_BAKE_CONSOLE  tmux or nmdm, named in the error when the session or the device does not appear
#@end
_image_firstboot_report_nmdm0() {
	printf '%s\n' "g=$(sq "$VM_BAKE_FIRSTBOOT") dev=$(sq "/dev/nmdm-$VM_BAKE_FIRSTBOOT.1B") log=$(sq "$VM_BAKE_GUEST_DIR/$VM_BAKE_FIRSTBOOT/console.log") lock=$(sq "$VM_BAKE_GUEST_DIR/$VM_BAKE_FIRSTBOOT/run.lock")"
	printf '%s\n' 'n=0; until test -c "$dev"; do n=$((n + 1)); test "$n" -lt 60 || { printf "# Error: firstboot %s: no %s within a minute (VM_BAKE_CONSOLE says nmdm; vm-bhyve console= in system.conf?)\n" "$g" "$dev" >&2; exit 1; }; sleep 1; done'
	printf '%s\n' 'exec 3<> "$dev"; stty raw -echo <&3'
	printf '%s\n' ': > "$log"; cat <&3 >> "$log" & rd=$!' 'trap '"'"'kill "$rd" 2>/dev/null'"'"' EXIT'
	printf '%s\n' 'hist() { tr -d "\r" < "$log" 2>/dev/null | cat -v; }'
	cat <<'EOF_REPORT'
give_up() { printf '# Error: firstboot %s: %s\n' "$g" "$1" >&2; hist | tail -15 >&2; vm poweroff -f "$g" >/dev/null 2>&1; exit 1; }
n=0; until hist | grep -q '# vm-bake firstboot:'; do test -e "$lock" || pgrep -q -f "bhyve: $g\$" || give_up "the first boot ended without a package report"; n=$((n + 1)); test "$n" -lt 3600 || give_up "no package report within an hour"; sleep 1; done
hist | grep -q '# vm-bake firstboot: missing' && give_up "the first boot left packages out: $(hist | grep '# vm-bake firstboot: missing' | tail -1 | sed 's/.*missing //')"
printf '# firstboot %s: the first boot reports its packages complete\n' "$g" >&2
EOF_REPORT
}

#@help _image_file_write1
# @command image file write <image>
# @summary Act terminal (root, host or builder): the template's file lines (read at generation time) into the mounted disk of a FreeBSD image -- each dowry's object installed at its path with the mode of the line, owner root:wheel, the directory made; 'image burn' calls it only when there are lines
# @group   image
# @internal
# @see     image burn
# @see     template file add
# @env     VM_BAKE_IMAGE_DIR  the image's directory, the disk is mounted under <image>/mnt
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_file_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 files="" line=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	files=$(awk -v base="$VM_BAKE_BASE" -v family=file -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "$files" | while IFS= read -r line; do
		set -- $line
		printf '%s\n' "install -d -m 755 -o root -g wheel '$mnt$(dirname "$2")' && install -m $3 -o root -g wheel '$VM_BAKE_BASE/dowry/$1/object' '$mnt$2' || exit 1"
	done
	printf '%s\n' "printf '# image %s: %s files from dowries\\n' $(sq "$1") '$(printf '%s\n' "$files" | grep -c .)' >&2"
}

#@help _image_site_files_place1
# @command image site files place <image>
# @summary Act terminal: the template's file lines (read at generation time) into the site set of an OpenBSD image -- each dowry's object under VM_BAKE_IMAGE_DIR/<image>/site.d at its path with the mode of the line; 'image site pack' packs the whole directory owned by root, and the installer unpacks the set over the installed system. No file lines: a comment
# @group   image
# @internal
# @see     image install
# @see     image site pack
# @see     template file add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_site_files_place1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 files="" line=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	files=$(awk -v base="$VM_BAKE_BASE" -v family=file -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	if test -z "$files"; then
		printf '%s\n' "# image $1: no file lines in $t -- the site set carries install.site alone"
		return 0
	fi
	printf '%s\n' "$files" | while IFS= read -r line; do
		set -- $line
		printf '%s\n' "install -d -m 755 '$dir/site.d$(dirname "$2")' && install -m $3 '$VM_BAKE_BASE/dowry/$1/object' '$dir/site.d$2' || exit 1"
	done
	printf '%s\n' "printf '# image %s: %s files from dowries in the site set\\n' $(sq "$1") '$(printf '%s\n' "$files" | grep -c .)' >&2"
}

#@help __image_check_daemons1
# @command image check daemons <image>
# @summary The template's daemon lines (read at generation time) resolve: every user is root or a user of the template's user list, every name is listed once -- a comment line naming the daemons, else an error line
# @group   image
# @internal
# @see     image burn
# @see     image seed write
# @see     image install
# @see     image install apkovl
# @see     template daemon add
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
__image_check_daemons1() {
	local name="$1" t="" cur="" chain="" p="" n=0 lines="" users="" names="" bad="" dup=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=daemon -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | awk '{ print $1 }' | tr '\n' ' ')
	names=$(printf '%s\n' "$lines" | awk 'NF { print $1 }' | tr '\n' ' ' | sed 's/ $//')
	bad=$(printf '%s\n' "$lines" | awk -v u="root $users" 'NF && index(" " u " ", " " $2 " ") == 0 { printf " %s(%s)", $1, $2 }')
	dup=$(printf '%s\n' "$lines" | awk 'NF && seen[$1]++ == 1 { printf " %s", $1 }')
	if test -z "$bad" && test -z "$dup"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $name: daemons resolve (${names:-none})")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image $name: the daemon lines of $t do not resolve --${bad:+ users the template does not list:$bad}${dup:+ names listed twice:$dup} (template user add, template daemon drop)")"
	fi
}

#@help _image_daemon_write1
# @command image daemon write <image>
# @summary Act terminal (root, host or builder): the template's daemon lines (read at generation time) as rc.d scripts of the image -- /usr/local/etc/rc.d/<name> runs the program under daemon(8) as the user (-u sets HOME, USER and SHELL), supervised with a restart after 5 seconds (-R 5), the supervisor's pid in /var/run/<name>.pid (-P: stop ends the supervisor, which forwards the SIGTERM to the program), stdout and stderr appended to /var/log/<name>.log (-f -o), PATH widened by /usr/local so a bare program name is found; REQUIRE: LOGIN, KEYWORD: shutdown; <name>_enable="YES" appended to rc.conf after 'image rc write'. No daemon lines: a comment
# @group   image
# @internal
# @see     image burn
# @see     image rc write
# @see     template daemon add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_daemon_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" t="" cur="" chain="" p="" n=0 lines="" line="" name="" rest="" user="" prog=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=daemon -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -n "$lines" || { printf '%s\n' "# image $1: no daemon lines in $t -- no rc.d script of its own"; return 0; }
	printf '%s\n' "install -d -m 755 -o root -g wheel '$mnt/usr/local/etc/rc.d' || exit 1"
	printf '%s\n' "$lines" | while IFS= read -r line; do
		name=${line%% *}; rest=${line#* }; user=${rest%% *}; prog=${rest#* }
		printf '%s\n' "cat > '$mnt/usr/local/etc/rc.d/$name' <<'EOF_RCD'" '#!/bin/sh' "# written by vm-bake (image daemon write) -- the daemon $name of the template $t under daemon(8): as $user, restarted after 5 seconds, its output appended to /var/log/$name.log"
		printf '%s\n' "# PROVIDE: $name" "# REQUIRE: LOGIN" "# KEYWORD: shutdown" ". /etc/rc.subr" "name=\"$name\"" "rcvar=\"${name}_enable\"" "load_rc_config \"\$name\"" ": \${${name}_enable:=NO}"
		printf '%s\n' "export PATH=\"/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin\"" "pidfile=\"/var/run/$name.pid\"" "command=\"/usr/sbin/daemon\"" "command_args=\"-f -u $user -R 5 -P \${pidfile} -o /var/log/$name.log $prog\"" "run_rc_command \"\$1\"" "EOF_RCD"
		printf '%s\n' "chmod 555 '$mnt/usr/local/etc/rc.d/$name' && printf '%s\\n' '${name}_enable=\"YES\"' >> '$mnt/etc/rc.conf' || exit 1"
	done
	printf '%s\n' "printf '# image %s: %s daemons as rc.d scripts, enabled in rc.conf\\n' $(sq "$1") '$(printf '%s\n' "$lines" | grep -c .)' >&2"
}

#@help _image_site_daemon_write1
# @command image site daemon write <image>
# @summary Act terminal: the template's daemon lines (read at generation time) appended to install.site -- for each an rc.d script /etc/rc.d/<name> (daemon_user the user, daemon the program's path looked up at start with /usr/local in the path, daemon_flags its arguments, rc_bg=YES for a program that stays in the foreground, su -l gives it the user's login environment), and 'rcctl enable <name>' appended to rc.firsttime, where the first boot of the bake runs it before the packages 'image site firsttime write' adds -- the daemon first runs in a guest. No daemon lines: a comment
# @group   image
# @internal
# @see     image site write
# @see     image site firsttime write
# @see     template daemon add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_site_daemon_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 lines="" line="" name="" rest="" user="" prog="" args=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=daemon -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -n "$lines" || { printf '%s\n' "# image $1: no daemon lines in $t -- install.site writes no rc.d script"; return 0; }
	printf '%s\n' "cat >> '$dir/site.d/install.site' <<'EOF_SITE'"
	printf '%s\n' "$lines" | while IFS= read -r line; do
		name=${line%% *}; rest=${line#* }; user=${rest%% *}; prog=${rest#* }; args=""
		case "$prog" in *" "*) args=${prog#* } ;; esac
		printf '%s\n' "cat > '/etc/rc.d/$name' <<'EOF_RCD'" '#!/bin/ksh' "# written by vm-bake (image site daemon write) -- the daemon $name of the template $t: rc_bg keeps a program that stays in the foreground, su -l gives it the login environment of $user"
		printf '%s\n' "daemon_user=\"$user\"" "daemon=\"\$(PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin command -v ${prog%% *})\"" "daemon_flags=\"$args\"" ". /etc/rc.d/rc.subr" "rc_bg=YES" "rc_reload=NO" "rc_cmd \$1" "EOF_RCD"
		printf '%s\n' "chmod 555 '/etc/rc.d/$name'" "printf 'rcctl enable %s\\n' '$name' >> /etc/rc.firsttime"
	done
	printf '%s\n' "EOF_SITE"
	printf '%s\n' "printf '# image %s: install.site -- %s daemons as rc.d scripts, enabled at the first boot\\n' $(sq "$1") '$(printf '%s\n' "$lines" | grep -c .)' >&2"
}

#@help _image_overlay_daemon_write1
# @command image overlay daemon write <image>
# @summary Act terminal: the template's daemon lines (read at generation time) as OpenRC scripts in the overlay -- etc/init.d/<name> (command the program's path looked up at start with /usr/local in the path, command_args its arguments, command_user the user with HOME exported as the user's home, command_background with a pidfile under /run, output_log and error_log /var/log/<name>.log, need net), which setup-disk carries onto the disk with etc; 'rc-update add <name> default' appended to the first boot's script after the packages -- the daemon first runs in a guest. No daemon lines: a comment
# @group   image
# @internal
# @see     image overlay write
# @see     image overlay firstboot write
# @see     template daemon add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_overlay_daemon_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 lines="" line="" name="" rest="" user="" prog="" args="" home=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=daemon -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -n "$lines" || { printf '%s\n' "# image $1: no daemon lines in $t -- the overlay carries no init script"; return 0; }
	printf '%s\n' "install -d -m 755 '$dir/overlay.d/etc/init.d' || exit 1"
	printf '%s\n' "$lines" | while IFS= read -r line; do
		name=${line%% *}; rest=${line#* }; user=${rest%% *}; prog=${rest#* }; args=""; home="/home/$user"
		case "$prog" in *" "*) args=${prog#* } ;; esac
		test "$user" != root || home=/root
		printf '%s\n' "cat > '$dir/overlay.d/etc/init.d/$name' <<'EOF_INIT'" '#!/sbin/openrc-run' "# written by vm-bake (image overlay daemon write) -- the daemon $name of the template $t: in the background under start-stop-daemon as $user, its output in /var/log/$name.log"
		printf '%s\n' "description=\"$name, a daemon of the template $t\"" "export HOME=\"$home\"" "command=\"\$(PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin command -v ${prog%% *})\"" "command_args=\"$args\"" "command_user=\"$user\"" "command_background=yes"
		printf '%s\n' "pidfile=\"/run/$name.pid\"" "output_log=\"/var/log/$name.log\"" "error_log=\"/var/log/$name.log\"" "depend() {" "	need net" "	after firewall" "}" "EOF_INIT"
		printf '%s\n' "chmod 755 '$dir/overlay.d/etc/init.d/$name' || exit 1"
	done
	printf '%s\n' "cat >> '$dir/overlay.d/etc/local.d/vm-bake-firstboot.start' <<'EOF_FIRST'"
	printf '%s\n' "$lines" | awk 'NF { printf "rc-update add %s default\n", $1 }'
	printf '%s\n' "EOF_FIRST"
	printf '%s\n' "printf '# image %s: %s daemons as OpenRC scripts in the overlay, in the default runlevel from the first boot\\n' $(sq "$1") '$(printf '%s\n' "$lines" | grep -c .)' >&2"
}

#@help _image_seed_daemon_write1
# @command image seed daemon write <image>
# @summary Act terminal: the template's daemon lines (read at generation time) continue the write_files of user-data -- for each a unit /etc/systemd/system/<name>.service (User the user, so HOME is the user's home; ExecStart the program, a bare name resolved by systemd's own search path, /usr/local included; After and Wants network-online.target; Restart=always after 5 seconds), then the per-once script vm-bake-daemons.sh that enables them at the bake's first boot -- the daemon first runs in a guest. No daemon lines: a comment
# @group   image
# @internal
# @see     image seed write
# @see     image seed check write
# @see     template daemon add
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_image_seed_daemon_write1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" t="" cur="" chain="" p="" n=0 lines="" line="" name="" rest="" user="" prog=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$1/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=daemon -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -n "$lines" || { printf '%s\n' "# image $1: no daemon lines in $t -- no unit in the seed"; return 0; }
	printf '%s\n' "cat >> '$dir/seed/user-data' <<'EOF_DAEMONS'"
	printf '%s\n' "$lines" | while IFS= read -r line; do
		name=${line%% *}; rest=${line#* }; user=${rest%% *}; prog=${rest#* }
		printf '%s\n' "  - path: /etc/systemd/system/$name.service" "    permissions: '0644'" "    content: |" "      # written by vm-bake (image seed daemon write) -- the daemon $name of the template $t"
		printf '%s\n' "      [Unit]" "      Description=$name, a daemon of the template $t" "      After=network-online.target" "      Wants=network-online.target" "      [Service]" "      User=$user" "      ExecStart=$prog" "      Restart=always" "      RestartSec=5" "      [Install]" "      WantedBy=multi-user.target"
	done
	printf '%s\n' "  - path: /var/lib/cloud/scripts/per-once/vm-bake-daemons.sh" "    permissions: '0755'" "    content: |" "      #!/bin/sh" "      # written by vm-bake (image seed daemon write) -- the bake's first boot: the units of the template's daemons enabled, so every guest of the image starts them at boot"
	printf '%s\n' "$lines" | awk 'NF { printf "      systemctl enable %s.service\n", $1 }'
	printf '%s\n' "EOF_DAEMONS"
	printf '%s\n' "printf '# image %s: %s daemons as systemd units, enabled at the first boot\\n' $(sq "$1") '$(printf '%s\n' "$lines" | grep -c .)' >&2"
}
