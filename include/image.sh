#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# image.sh - the images of vm-bake: a template baked onto a sparse UFS disk
# under VM_BAKE_IMAGE_DIR/<image> (a ZFS dataset of its own), from the pkgbase
# repository of the template's release, sealed by the snapshot @image. The
# bake is five commands (create, base, burn, close, seal), 'image make
# freebsd' the chain over them; every act that needs root is a terminal of
# its own pinned to 'sudo sh', so each can be inspected with cat first.

#@help
# @defgroup image  Images
# @order   60
#   An image is a baked disk: the decisions of a template applied to a
#   FreeBSD release from the pkgbase repository, on a sparse UFS disk
#   (GPT, an EFI system partition and the root) under
#   VM_BAKE_IMAGE_DIR/<image>, sealed by the ZFS snapshot @image and
#   readonly. 'image make freebsd <template>' names the image
#   <template>-<yyyymmdd> and runs create, base, burn, close and seal in
#   turn; each is a command of its own, so a bake can be walked step by
#   step. The acts that need root (zfs, md, gpart, newfs, mount, pkg, pw)
#   are pinned to 'sudo sh'; 'vm-bake setintp <terminal> cat' shows any of
#   them before it runs. One bake at a time: create takes a lock under
#   .tmp, seal drops it.
#@end

#@help
# @defcompletion image      image
# @defcompletion abi        none
# @defcompletion osversion  none
#@end

#@help ___image_make_freebsd1
# @command image make freebsd <template>
# @summary Bake a FreeBSD image from the template, named <template>-<yyyymmdd>: the template exists, its base is a release, its resource is set; then 'image create', 'image base', 'image burn', 'image close' and 'image seal' in turn
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check base release $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check resource $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image create $(sq "$1") $(sq "$name")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image base $(sq "$name")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image burn $(sq "$name")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image close $(sq "$name")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image seal $(sq "$name")"
}

#@help ___image_create2
# @command image create <template> <image>
# @summary Step 1, the empty disk: the template exists with a release base and a resource, the image name is free (no record, no directory); then the bake lock, the record, the dataset VM_BAKE_IMAGE_DIR/<image>, disk0.img sparse in the resource's disk size, attached as md, GPT with an EFI system partition and a UFS root, formatted and mounted at <image>/mnt
# @group   image
# @example vm-bake image create freebsd-dev freebsd-dev-20261031
# @see     image make freebsd
# @see     image base
# @env     VM_BAKE_IMAGE_DIR  where the image's dataset is created
#@end
___image_create2() {
	local cur="$1" chain="" p="" n=0 a="" size=""
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r size < "$VM_BAKE_BASE/template/$a/resource"; done
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template check template $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check base release $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check resource $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image name valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check absent $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image lock take $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image record write $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image dataset create $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk create $(sq "$2") $(sq "${size##* }")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk attach $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk partition $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk format $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk mount $(sq "$2")"
}

#@help ___image_base1
# @command image base <image>
# @summary Step 2, the operating system: the image has a record and is mounted; then 'pkg -r' installs FreeBSD-set-minimal, the GENERIC kernel and pkg from the repositories the host is configured for (ABI and OSVERSION from the template's release), the host's repository configuration is written into the image, the EFI loader into its system partition, loader.conf and fstab
# @group   image
# @example vm-bake image base freebsd-dev-20261031
# @see     image create
# @see     image burn
#@end
___image_base1() {
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check mounted $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image keys write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg base $(sq "$1") $(sq "$abi") $(sq "$osv")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image repo write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image boot write $(sq "$1")"
}

#@help ___image_burn1
# @command image burn <image>
# @summary Step 3, the template: the image has a record and is mounted, every user of the template resolves (a host uid exists, the key file VM_BAKE_HOST_KEY is readable); then the template's packages via 'pkg -r', its rc.conf lines, its users with the host key in authorized_keys, and sshd on VM_BAKE_SSH_PORT with keys only and no root
# @group   image
# @example vm-bake image burn freebsd-dev-20261031
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check mounted $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check users $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg install $(sq "$1") $(sq "$abi") $(sq "$osv")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image rc write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image user make $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image ssh write $(sq "$1")"
}

#@help ___image_close1
# @command image close <image>
# @summary Step 4, the disk closed: the image has a record and is mounted; then the package list and the audit of the image beside it (packages.txt, audit.txt), the root and the system partition unmounted, the md detached, the sha256 of disk0.img written beside it and into the record
# @group   image
# @example vm-bake image close freebsd-dev-20261031
# @see     image burn
# @see     image seal
#@end
___image_close1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check mounted $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image pkg report $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk unmount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image disk detach $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image digest write $(sq "$1")"
}

#@help ___image_seal1
# @command image seal <image>
# @summary Step 5, the seal: the image has a record and a digest, the bake lock is this image's; then the snapshot @image, the dataset readonly, the lock dropped
# @group   image
# @example vm-bake image seal freebsd-dev-20261031
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

#@help __image_check_base_release1
# @command image check base release <template>
# @summary The template's resolved base is a release (the word release before arch and version): a comment line, else an error line (a stage base is not baked yet, the other kinds are not FreeBSD)
# @group   image
# @internal
# @see     image make freebsd
#@end
__image_check_base_release1() {
	local cur="$1" chain="" p="" n=0 a="" base="" ok=no
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/base" && IFS= read -r base < "$VM_BAKE_BASE/template/$a/base"; done
	case "${base%% *}" in release) ok=yes ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image: base of $1 is $base")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image make freebsd: template $1 has no release base (${base:-none}; a stage base is not baked yet)")"
	fi
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
# @summary The image name is a record name ([A-Za-z0-9_.-], not . or ..): a comment line, else an error line
# @group   image
# @internal
# @see     image create
#@end
__image_name_valid1() {
	local ok=yes
	case "$1" in ""|.|..|*[!A-Za-z0-9_.-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image name $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create: invalid image name $1 ([A-Za-z0-9_.-])")"
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
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image create: $1 exists (record image/$1 or $VM_BAKE_IMAGE_DIR/$1); a new bake takes a new name")"
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
# @summary The image's root is mounted at VM_BAKE_IMAGE_DIR/<image>/mnt (read from mount at generation time): a comment line, else an error line
# @group   image
# @internal
# @see     image base
# @env     VM_BAKE_IMAGE_DIR  where the image's mount point is
#@end
__image_check_mounted1() {
	if mount -p 2>/dev/null | awk -v m="$VM_BAKE_IMAGE_DIR/$1/mnt" '$2 == m { f = 1 } END { exit !f }'; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "image $1 is mounted at $VM_BAKE_IMAGE_DIR/$1/mnt")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "image $1 is not mounted at $VM_BAKE_IMAGE_DIR/$1/mnt (image create first; a closed image is not reopened)")"
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

#@help _image_dataset_create1
# @command image dataset create <image>
# @summary Act terminal (root): the dataset of the image under the dataset mounted at the parent of VM_BAKE_IMAGE_DIR (zfs create -p, mountpoint inherited), its directory owned by the invoking user so the digest and the reports can be written without root
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  the images' directory; its parent names the dataset to create under
#@end
_image_dataset_create1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" parent="${VM_BAKE_IMAGE_DIR%/*}" sub="${VM_BAKE_IMAGE_DIR##*/}" uid="" gid=""
	uid=$(id -u); gid=$(id -g)
	printf '%s\n' "ds=\$(zfs list -H -o name '$parent') || exit 1"
	printf '%s\n' "zfs create -p \"\$ds/$sub/$1\" || exit 1"
	printf '%s\n' "chown $uid:$gid '$dir' || exit 1"
	printf '%s\n' "printf '# image %s: dataset %s at %s\\n' '$1' \"\$ds/$sub/$1\" '$dir' >&2"
}

#@help _image_disk_create2
# @command image disk create <image> <size>
# @summary Act terminal: disk0.img as a sparse file of the given size (truncate) in the image's directory; an existing file is an error
# @group   image
# @internal
# @see     image create
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
# @summary Act terminal (root): disk0.img attached as a vnode md
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_attach1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "md=\$(mdconfig -a -t vnode -f '$img') || exit 1"
	printf '%s\n' "printf '# image %s: %s attached to %s\\n' '$1' '$img' \"\$md\" >&2"
}

#@help _image_disk_partition1
# @command image disk partition <image>
# @summary Act terminal (root): the md of disk0.img found by its path (mdconfig -lv), GPT, an EFI system partition of 260M labelled vm-efi, the rest a freebsd-ufs partition labelled vm-root (the labels fstab and the loader use in every guest)
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_partition1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -n \"\$md\" || { printf '# Error: %s is not attached\\n' '$img' >&2; exit 1; }"
	printf '%s\n' "gpart create -s gpt \"\$md\" || exit 1"
	printf '%s\n' "gpart add -t efi -s 260M -a 1m -l vm-efi \"\$md\" || exit 1"
	printf '%s\n' "gpart add -t freebsd-ufs -a 1m -l vm-root \"\$md\" || exit 1"
	printf '%s\n' "printf '# image %s: GPT on %s, vm-efi and vm-root\\n' '$1' \"\$md\" >&2"
}

#@help _image_disk_format1
# @command image disk format <image>
# @summary Act terminal (root): FAT32 on the system partition, UFS with soft updates journaling (newfs -j, label vmroot) on the root
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_format1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -n \"\$md\" || { printf '# Error: %s is not attached\\n' '$img' >&2; exit 1; }"
	printf '%s\n' "newfs_msdos -F 32 -c 1 \"/dev/\${md}p1\" > /dev/null || exit 1"
	printf '%s\n' "newfs -j -L vmroot \"/dev/\${md}p2\" > /dev/null || exit 1"
	printf '%s\n' "printf '# image %s: %sp1 msdosfs, %sp2 ufs\\n' '$1' \"\$md\" \"\$md\" >&2"
}

#@help _image_disk_mount1
# @command image disk mount <image>
# @summary Act terminal (root): the root at <image>/mnt, the system partition at <image>/mnt/boot/efi
# @group   image
# @internal
# @see     image create
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_mount1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img" mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -n \"\$md\" || { printf '# Error: %s is not attached\\n' '$img' >&2; exit 1; }"
	printf '%s\n' "mkdir -p '$mnt' && mount \"/dev/\${md}p2\" '$mnt' || exit 1"
	printf '%s\n' "mkdir -p '$mnt/boot/efi' && mount -t msdosfs \"/dev/\${md}p1\" '$mnt/boot/efi' || exit 1"
	printf '%s\n' "printf '# image %s: mounted at %s\\n' '$1' '$mnt' >&2"
}

#@help _image_keys_write1
# @command image keys write <image>
# @summary Act terminal (root): the host's trusted package signing keys (/usr/share/keys/pkg, /usr/share/keys/pkgbase-<major>; whichever exist, read at generation time) copied into the image -- 'pkg -r' looks for the fingerprints below the root it installs into
# @group   image
# @internal
# @see     image base
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_keys_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" d="" dirs=""
	for d in /usr/share/keys/*/; do
		test -d "$d" && dirs="$dirs ${d%/}"
	done
	printf '%s\n' "mkdir -p '$mnt/usr/share/keys' || exit 1"
	printf '%s\n' "cp -R$dirs '$mnt/usr/share/keys/' || exit 1"
	printf '%s\n' "printf '# image %s: signing keys %s\\n' '$1' $(sq "${dirs# }") >&2"
}

#@help _image_pkg_base3
# @command image pkg base <image> <abi> <osversion>
# @summary Act terminal (root): 'pkg -r <mnt>' installs FreeBSD-set-minimal, FreeBSD-kernel-generic and pkg from the repositories the host is configured for, the ABI and OSVERSION pinned to the template's release (IGNORE_OSVERSION, ASSUME_ALWAYS_YES); the host's package cache serves the download
# @group   image
# @internal
# @see     image base
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_pkg_base3() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "pkg -r '$mnt' -o ABI=$(sq "$2") -o OSVERSION=$(sq "$3") -o IGNORE_OSVERSION=yes -o ASSUME_ALWAYS_YES=yes install FreeBSD-set-minimal FreeBSD-kernel-generic pkg || exit 1"
	printf '%s\n' "printf '# image %s: base installed (%s, %s)\\n' '$1' $(sq "$2") $(sq "$3") >&2"
}

#@help _image_repo_write1
# @command image repo write <image>
# @summary Act terminal (root): the host's repository overrides /usr/local/etc/pkg/repos/*.conf written into the image, read at generation time (the guest follows the host: the same branches, the same cache); pkgbase's own /etc/pkg/FreeBSD.conf is already in the image
# @group   image
# @internal
# @see     image base
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_repo_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt" f=""
	printf '%s\n' "mkdir -p '$mnt/usr/local/etc/pkg/repos' || exit 1"
	for f in /usr/local/etc/pkg/repos/*.conf; do
		test -f "$f" || continue
		printf '%s\n' "cat > '$mnt/usr/local/etc/pkg/repos/${f##*/}' <<'EOF_REPO'"
		cat "$f"
		printf '%s\n' "EOF_REPO"
	done
	printf '%s\n' "printf '# image %s: repository configuration of the host written\\n' '$1' >&2"
}

#@help _image_boot_write1
# @command image boot write <image>
# @summary Act terminal (root): the image's own loader.efi into the system partition as EFI/BOOT/BOOTX64.efi and EFI/freebsd/loader.efi, loader.conf (serial console for the bhyve nmdm, root from gpt/vm-root) and fstab (root rw, the system partition noauto)
# @group   image
# @internal
# @see     image base
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_boot_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "mkdir -p '$mnt/boot/efi/EFI/BOOT' '$mnt/boot/efi/EFI/freebsd' || exit 1"
	printf '%s\n' "cp '$mnt/boot/loader.efi' '$mnt/boot/efi/EFI/BOOT/BOOTX64.efi' || exit 1"
	printf '%s\n' "cp '$mnt/boot/loader.efi' '$mnt/boot/efi/EFI/freebsd/loader.efi' || exit 1"
	printf '%s\n' "cat > '$mnt/boot/loader.conf' <<'EOF_LOADER'"
	printf '%s\n' 'autoboot_delay="2"' 'boot_serial="YES"' 'boot_multicons="YES"' 'console="comconsole,efi"' 'comconsole_speed="115200"' 'vfs.root.mountfrom="ufs:/dev/gpt/vm-root"'
	printf '%s\n' "EOF_LOADER"
	printf '%s\n' "cat > '$mnt/etc/fstab' <<'EOF_FSTAB'"
	printf '%s\n' '/dev/gpt/vm-root	/		ufs	rw		1 1' '/dev/gpt/vm-efi	/boot/efi	msdosfs	rw,noauto	0 0'
	printf '%s\n' "EOF_FSTAB"
	printf '%s\n' "printf '# image %s: loader in the system partition, loader.conf, fstab\\n' '$1' >&2"
}

#@help _image_pkg_install3
# @command image pkg install <image> <abi> <osversion>
# @summary Act terminal (root): the template's resolved package list (read at generation time) installed with 'pkg -r <mnt>' under the pinned ABI and OSVERSION; an empty list is a note
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
		printf '%s\n' "pkg -r '$mnt' -o ABI=$(sq "$2") -o OSVERSION=$(sq "$3") -o IGNORE_OSVERSION=yes -o ASSUME_ALWAYS_YES=yes install $pkgs|| exit 1"
		printf '%s\n' "printf '# image %s: packages %s\\n' '$1' $(sq "${pkgs% }") >&2"
	else
		emit_note "image $1: the template lists no packages"
	fi
}

#@help _image_rc_write1
# @command image rc write <image>
# @summary Act terminal (root): /etc/rc.conf of the image from the template's resolved rc lines (read at generation time); hostname and network come with the guest, not here
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
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=rc -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	printf '%s\n' "cat > '$mnt/etc/rc.conf' <<'EOF_RC'"
	printf '%s\n' "$lines"
	printf '%s\n' "EOF_RC"
	printf '%s\n' "printf '# image %s: rc.conf, %s lines\\n' '$1' '$(printf '%s\n' "$lines" | grep -c .)' >&2"
}

#@help _image_user_make1
# @command image user make <image>
# @summary Act terminal (root): every user of the template's resolved user list (read at generation time) created in the image with 'pw -R' -- uid 'host' is the uid of that user on this host -- without a password, with the public key VM_BAKE_HOST_KEY in authorized_keys
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
		printf '%s\n' "pw -R '$mnt' useradd $(sq "$u") -u $(sq "$uid") -c $(sq "$u") -d '/home/$u' -s /bin/sh -w no || exit 1"
		printf '%s\n' "mkdir -p '$mnt/home/$u/.ssh' || exit 1"
		printf '%s\n' "printf '%s\\n' $(sq "$keytext") > '$mnt/home/$u/.ssh/authorized_keys' || exit 1"
		printf '%s\n' "chmod 700 '$mnt/home/$u/.ssh' && chmod 600 '$mnt/home/$u/.ssh/authorized_keys' && chown -R $(sq "$uid"):$(sq "$u") '$mnt/home/$u' || exit 1"
		printf '%s\n' "printf '# image %s: user %s (uid %s), key %s\\n' '$name' $(sq "$u") $(sq "$uid") $(sq "$key") >&2"
	done
	test -n "$lines" || emit_note "image $name: the template lists no users"
}

#@help _image_ssh_write1
# @command image ssh write <image>
# @summary Act terminal (root): sshd_config of the image gets Port VM_BAKE_SSH_PORT, PermitRootLogin no, PasswordAuthentication no, KbdInteractiveAuthentication no (appended; the host's pf passes that port into the guest network)
# @group   image
# @internal
# @see     image burn
# @env     VM_BAKE_IMAGE_DIR  the image's directory
# @env     VM_BAKE_SSH_PORT  the port sshd listens on in every guest of this image
#@end
_image_ssh_write1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "test -d '$mnt/etc/ssh' || { printf '# Error: no /etc/ssh in the image (image base first)\\n' >&2; exit 1; }"
	printf '%s\n' "cat >> '$mnt/etc/ssh/sshd_config' <<'EOF_SSHD'"
	printf '%s\n' "" "Port $VM_BAKE_SSH_PORT" "PermitRootLogin no" "PasswordAuthentication no" "KbdInteractiveAuthentication no"
	printf '%s\n' "EOF_SSHD"
	printf '%s\n' "printf '# image %s: sshd on port %s, keys only, no root\\n' '$1' '$VM_BAKE_SSH_PORT' >&2"
}

#@help _image_pkg_report1
# @command image pkg report <image>
# @summary Act terminal (root): the package list of the image (pkg -r info) into packages.txt and its audit (pkg -r audit -F, the vulnerability list fetched into the image) into audit.txt beside disk0.img; a vulnerable package is reported, not a failure
# @group   image
# @internal
# @see     image close
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_pkg_report1() {
	local dir="$VM_BAKE_IMAGE_DIR/$1" mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "pkg -r '$mnt' info > '$dir/packages.txt' || exit 1"
	printf '%s\n' "pkg -r '$mnt' audit -F > '$dir/audit.txt' 2>&1; printf '# image %s: %s packages, audit exit %s (%s)\\n' '$1' \"\$(grep -c . '$dir/packages.txt')\" \"\$?\" '$dir/audit.txt' >&2"
}

#@help _image_disk_unmount1
# @command image disk unmount <image>
# @summary Act terminal (root): the system partition and the root unmounted
# @group   image
# @internal
# @see     image close
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_unmount1() {
	local mnt="$VM_BAKE_IMAGE_DIR/$1/mnt"
	printf '%s\n' "umount '$mnt/boot/efi' || exit 1"
	printf '%s\n' "umount '$mnt' || exit 1"
	printf '%s\n' "printf '# image %s: unmounted\\n' '$1' >&2"
}

#@help _image_disk_detach1
# @command image disk detach <image>
# @summary Act terminal (root): the md of disk0.img, found by its path, detached
# @group   image
# @internal
# @see     image close
# @env     VM_BAKE_IMAGE_DIR  the image's directory
#@end
_image_disk_detach1() {
	local img="$VM_BAKE_IMAGE_DIR/$1/disk0.img"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$img' '\$4 == f { print \$1; exit }'); test -n \"\$md\" || { printf '# Error: %s is not attached\\n' '$img' >&2; exit 1; }"
	printf '%s\n' "mdconfig -d -u \"\${md#md}\" || exit 1"
	printf '%s\n' "printf '# image %s: %s detached\\n' '$1' \"\$md\" >&2"
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
# @summary Act terminal (root): the snapshot @image of the image's dataset (found by its mount point)
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
# @summary Act terminal (root): the image's dataset readonly -- the image is a product, guests are clones of its snapshot
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
