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

#@help ___image_make_freebsd1
# @command image make freebsd <template>
# @summary Bake a FreeBSD image from the template, named <template>-<yyyymmdd>: 'image create', 'image base', 'image burn', 'image close' and 'image seal' in turn (each a command of its own; create decides by the template's base kind)
# @group   image
# @example vm-bake image make freebsd freebsd-dev
# @see     image create
# @see     image base
# @see     image burn
# @see     image close
# @see     image seal
# @see     image list
#@end
___image_make_freebsd1() {
	local name="$1-$(date -u '+%Y%m%d')"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" note $(sq "image make freebsd: template $1 -> image $name (create, base, burn, close, seal)")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image create $(sq "$1") $(sq "$name")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image base $(sq "$name")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image burn $(sq "$name")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image close $(sq "$name")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seal $(sq "$name")"
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
# @summary Step 3, the template: the image has a record, every user of the template resolves (a host uid exists, the key file VM_BAKE_HOST_KEY is readable); then the template's packages via 'pkg -r', its rc.conf lines, its users with the host key in authorized_keys, root locked (pkgbase ships root without a password), doas for them when the template lists doas, and sshd on VM_BAKE_SSH_PORT with keys only and no root -- where VM_BAKE_BAKE_IN says (the pins)
# @group   image
# @example vm-bake image burn freebsd-dev-20261101
# @see     image base
# @see     image close
#@end
___image_burn1() {
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check users $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg install $(sq "$1") $(sq "$abi") $(sq "$osv")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image rc write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image user make $(sq "$1")"
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
# @summary Bake in the builder guest from now on: VM_BAKE_BAKE_IN=builder, and the content terminals (disk mount, keys, pkg base, repo, boot, pkg install, rc, user, root lock, doas, ssh, pkg report, disk unmount) pinned to 'ssh -p VM_BAKE_SSH_PORT -i <key> VM_BAKE_BUILDER_USER@VM_BAKE_BUILDER_ADDRESS doas sh' -- one setintp line each, so the pins are seen
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
	for f in image_disk_mount image_keys_write image_pkg_base image_repo_write image_boot_write image_pkg_install image_rc_write image_user_make image_root_lock image_doas_write image_ssh_write image_pkg_report image_disk_unmount; do
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
	for f in image_disk_mount image_keys_write image_pkg_base image_repo_write image_boot_write image_pkg_install image_rc_write image_user_make image_root_lock image_doas_write image_ssh_write image_pkg_report image_disk_unmount; do
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" unsetintp $f"
	done
}

#@help ___image_builder_start1
# @command image builder start <image>
# @summary Start the builder guest with the image's disk as its second disk: the builder guest has a record (guest make); its configuration written with the disk, 'vm start', then wait until it answers ssh
# @group   image
# @example vm-bake image builder start freebsd-dev-20261101
# @see     image builder stop
# @see     guest make
# @env     VM_BAKE_BUILDER  the builder guest's name
#@end
___image_builder_start1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$VM_BAKE_BUILDER")"
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
# @summary The image name is a record name ([A-Za-z0-9_.-], not . or ..) of at most 30 characters (the GPT labels <image>-efi and <image>-root must fit 36): a comment line, else an error line
# @group   image
# @internal
# @see     image create
#@end
__image_name_valid1() {
	local ok=yes
	case "$1" in ""|.|..|*[!A-Za-z0-9_.-]*) ok=no ;; esac
	test ${#1} -le 30 || ok=no
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image name $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create: invalid image name $1 ([A-Za-z0-9_.-], at most 30 characters)")"
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
# @summary Act terminal (the invoking user, delegated by zfs allow): vm-bake's datasets exist -- image and guest under the dataset mounted at VM_BAKE_DIR, which root made once and delegated, and the cache directory beside them -- idempotent, the first act of image create and guest make
# @group   image
# @internal
# @see     image create
# @see     guest make
# @env     VM_BAKE_DIR  vm-bake's dataset: image/, guest/ (datasets) and cache/ (a directory) live in it
# @env     VM_BAKE_IMAGE_CACHE  the cache directory
#@end
_image_tree_ensure0() {
	printf '%s\n' "ds=\$(zfs list -H -o name '$VM_BAKE_DIR') || { printf '# Error: %s is no dataset (root makes it once and delegates it: help env VM_BAKE_DIR)\\n' '$VM_BAKE_DIR' >&2; exit 1; }"
	printf '%s\n' "zfs list -H -o name \"\$ds/image\" > /dev/null 2>&1 || zfs create \"\$ds/image\" || exit 1"
	printf '%s\n' "zfs list -H -o name \"\$ds/guest\" > /dev/null 2>&1 || zfs create \"\$ds/guest\" || exit 1"
	printf '%s\n' "install -d -m 755 '$VM_BAKE_IMAGE_CACHE' || exit 1"
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
	printf '%s\n' "mkdir -p '$mnt' && mount '/dev/gpt/$1-root' '$mnt' || exit 1"
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

#@help _image_user_make1
# @command image user make <image>
# @summary Act terminal (root, host or builder): every user of the template's resolved user list (read at generation time) created in the image with 'pw -R' -- uid 'host' is the uid of that user on this host -- without a password, with the public key VM_BAKE_HOST_KEY in authorized_keys
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
		printf '%s\n' "printf '# image %s: user %s (uid %s), key %s\\n' '$name' $(sq "$u") $(sq "$uid") $(sq "$key") >&2"
	done
	test -n "$lines" || emit_note "image $name: the template lists no users"
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
# @summary Act terminal (root, host or builder): sshd_config of the image gets Port VM_BAKE_SSH_PORT, PermitRootLogin no, PasswordAuthentication no, KbdInteractiveAuthentication no, and X11Forwarding yes when the template's resolved services (read at generation time) list 'display x' (appended once; the host's pf passes that port into the guest network)
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
	printf '%s\n' "grep -q '^Port $VM_BAKE_SSH_PORT$' '$mnt/etc/ssh/sshd_config' || cat >> '$mnt/etc/ssh/sshd_config' <<'EOF_SSHD'"
	printf '%s\n' "" "Port $VM_BAKE_SSH_PORT" "PermitRootLogin no" "PasswordAuthentication no" "KbdInteractiveAuthentication no"
	test "$x11" = no || printf '%s\n' "X11Forwarding yes"
	printf '%s\n' "EOF_SSHD"
	printf '%s\n' "printf '# image %s: sshd on port %s, keys only, no root, X11 forwarding %s\\n' '$1' '$VM_BAKE_SSH_PORT' '$x11' >&2"
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
