#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# guest.sh - the guests of vm-bake: a guest is a clone of a sealed image's
# snapshot under VM_BAKE_GUEST_DIR/<guest> (vm-bhyve's vm_dir), with its
# configuration rendered from the image's template, its address written
# into the clone's rc.conf offline (no root in the guest), on the switch
# VM_BAKE_GUEST_SWITCH over the bridge VM_BAKE_GUEST_BRIDGE.

#@help
# @defgroup guest  Guests
# @order   70
#   A guest is a sealed image put to work: 'guest make <image> <guest>
#   <address>' clones the image's snapshot into VM_BAKE_GUEST_DIR/<guest>,
#   renders the vm-bhyve configuration (UEFI, cpu and memory from the
#   template, virtio disk and network on VM_BAKE_GUEST_SWITCH) and writes
#   hostname, address and resolver into the clone's rc.conf from the
#   host, because no one is root inside. The switch is created on the
#   bridge VM_BAKE_GUEST_BRIDGE when it is missing. 'guest start' and
#   'guest stop' wrap vm-bhyve; 'guest drop' destroys the clone.
#@end

#@help
# @defcompletion guest      guest
# @defcompletion address    none
#@end

#@help ___guest_make3
# @command guest make <image> <guest> <address>
# @summary Make a guest from a sealed image: the image has a record and a digest, the guest name is a record name and free; then the switch ensured, the record, the clone of @image, the configuration, the network written into the clone, the host's unbound told the name, the guest's old ssh host key forgotten
# @group   guest
# @example vm-bake guest make freebsd-builder-20261101 bake 172.16.100.250/24
# @see     guest start
# @see     guest list
# @see     image make freebsd
#@end
___guest_make3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image check closed $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest name valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check absent $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest address valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest switch ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest record write $(sq "$1") $(sq "$2") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest clone $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest conf write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest network write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dns write"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest knownhosts drop $(sq "$2")"
}

#@help ___guest_start1
# @command guest start <guest>
# @summary Start the guest: it has a record; then 'vm start'
# @group   guest
# @example vm-bake guest start bake
# @see     guest stop
# @see     guest make
#@end
___guest_start1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest run $(sq "$1")"
}

#@help ___guest_stop1
# @command guest stop <guest>
# @summary Stop the guest: it has a record; then 'vm stop' (ACPI shutdown)
# @group   guest
# @example vm-bake guest stop bake
# @see     guest start
#@end
___guest_stop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest halt $(sq "$1")"
}

#@help ___guest_drop1
# @command guest drop <guest>
# @summary Remove the guest: it has a record; its dataset destroyed (a running guest makes zfs refuse: guest stop first), the record removed, unbound told, its ssh host key forgotten
# @group   guest
# @example vm-bake guest drop bake
# @see     guest make
# @see     guest stop
#@end
___guest_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link drop $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dataset destroy $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest record remove $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dns write"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest knownhosts drop $(sq "$1")"
}

#@help __guest_name_valid1
# @command guest name valid <guest>
# @summary The guest name is a host name label ([a-z0-9][a-z0-9-]*, at most 30 characters; vm-bhyve and the hostname take it): a comment line, else an error line
# @group   guest
# @internal
# @see     guest make
#@end
__guest_name_valid1() {
	local ok=yes
	case "$1" in ""|[!a-z0-9]*|*[!a-z0-9-]*) ok=no ;; esac
	test ${#1} -le 30 || ok=no
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest name $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest make: invalid guest name $1 ([a-z0-9][a-z0-9-]*, at most 30 characters)")"
	fi
}

#@help __guest_address_valid1
# @command guest address valid <address>
# @summary The address is IPv4 with a prefix length (a.b.c.d/n): a comment line, else an error line
# @group   guest
# @internal
# @see     guest make
#@end
__guest_address_valid1() {
	local ok=no
	case "$1" in [0-9]*.[0-9]*.[0-9]*.[0-9]*/[0-9]*) ok=yes ;; esac
	case "$1" in *[!0-9./]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest address $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest make: invalid address $1 (a.b.c.d/n, e.g. 172.16.100.250/24)")"
	fi
}

#@help __guest_check_absent1
# @command guest check absent <guest>
# @summary No record and no directory of that name yet: a comment line, else an error line
# @group   guest
# @internal
# @see     guest make
# @env     VM_BAKE_GUEST_DIR  the guests' directory
#@end
__guest_check_absent1() {
	if test ! -e "$VM_BAKE_BASE/guest/$1" && test ! -e "$VM_BAKE_GUEST_DIR/$1"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1 is free")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest make: $1 exists (record guest/$1 or $VM_BAKE_GUEST_DIR/$1); guest drop removes it")"
	fi
}

#@help __guest_check_record1
# @command guest check record <guest>
# @summary The guest has a record (guest/<guest>/image): a comment line, else an error line
# @group   guest
# @internal
# @see     guest start
#@end
__guest_check_record1() {
	if test -f "$VM_BAKE_BASE/guest/$1/image"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1 has a record")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "unknown guest $1 (guest make <image> $1 <address>, or guest list)")"
	fi
}

#@help _guest_switch_ensure0
# @command guest switch ensure
# @summary Act terminal (root): the vm-bhyve switch VM_BAKE_GUEST_SWITCH exists, else created as a manual switch on the bridge VM_BAKE_GUEST_BRIDGE (the host's pf rules live on the bridge)
# @group   guest
# @internal
# @see     guest make
# @env     VM_BAKE_GUEST_SWITCH  the switch's name
# @env     VM_BAKE_GUEST_BRIDGE  the existing bridge it attaches to
#@end
_guest_switch_ensure0() {
	printf '%s\n' "vm switch list | awk 'NR > 1 && \$1 == \"$VM_BAKE_GUEST_SWITCH\"' | grep -q . || vm switch create -t manual -b '$VM_BAKE_GUEST_BRIDGE' '$VM_BAKE_GUEST_SWITCH' || exit 1"
	printf '%s\n' "printf '# switch %s on %s\\n' '$VM_BAKE_GUEST_SWITCH' '$VM_BAKE_GUEST_BRIDGE' >&2"
}

#@help _guest_record_write3
# @command guest record write <image> <guest> <address>
# @summary Act terminal: the record guest/<guest>/ with image, address and created (0600)
# @group   guest
# @internal
# @see     guest make
#@end
_guest_record_write3() {
	local rec="$VM_BAKE_BASE/guest/$2" stamp=""
	stamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
	printf '%s\n' "$MODIFY_DIR_CREATE '$rec' && $MODIFY_FILE_PERMS 0700 '$rec'"
	printf '%s\n' "printf '%s\\n' $(sq "$1") > '$rec/image'"
	printf '%s\n' "printf '%s\\n' $(sq "$3") > '$rec/address'"
	printf '%s\n' "printf '%s\\n' '$stamp' > '$rec/created'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$rec/image' '$rec/address' '$rec/created'"
	emit_note "guest $2: record (image $1, address $3)"
}

#@help _guest_record_remove1
# @command guest record remove <guest>
# @summary Act terminal: the record guest/<guest>/ removed
# @group   guest
# @internal
# @see     guest drop
#@end
_guest_record_remove1() {
	printf '%s\n' "rm -rf '$VM_BAKE_BASE/guest/$1'"
	emit_note "guest $1: record removed"
}

#@help _guest_clone1
# @command guest clone <guest>
# @summary Act terminal (the invoking user, delegated by zfs allow): the image's snapshot @image (the image from the guest record) cloned to the guests' dataset as <guest>, writable; it mounts at VM_BAKE_GUEST_DIR/<guest> with disk0.img inside
# @group   guest
# @internal
# @see     guest make
# @env     VM_BAKE_GUEST_DIR  the guests' directory (its dataset is the clone's parent)
# @env     VM_BAKE_IMAGE_DIR  the images' directory
#@end
_guest_clone1() {
	local img=""
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	printf '%s\n' "src=\$(zfs list -H -o name '$VM_BAKE_IMAGE_DIR/$img') || exit 1"
	printf '%s\n' "dst=\$(zfs list -H -o name '$VM_BAKE_GUEST_DIR') || exit 1"
	printf '%s\n' "zfs clone -o readonly=off \"\$src@image\" \"\$dst/$1\" || exit 1"
	printf '%s\n' "printf '# guest %s: clone of %s@image at %s\\n' '$1' \"\$src\" '$VM_BAKE_GUEST_DIR/$1' >&2"
}

#@help _guest_conf_write1
# @command guest conf write <guest>
# @summary Act terminal (the invoking user: the clone is theirs): the vm-bhyve configuration VM_BAKE_GUEST_DIR/<guest>/<guest>.conf: UEFI, cpu and memory from the image's template (read at generation time), disk0.img as virtio-blk, one virtio-net on VM_BAKE_GUEST_SWITCH
# @group   guest
# @internal
# @see     guest make
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_GUEST_SWITCH  the switch the guest hangs on
#@end
_guest_conf_write1() {
	local conf="$VM_BAKE_GUEST_DIR/$1/$1.conf" img="" t="" cur="" chain="" p="" n=0 a="" res=""
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
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
	printf '%s\n' 'loader="uefi"' "cpu=$2" "memory=$3" 'network0_type="virtio-net"' "network0_switch=\"$VM_BAKE_GUEST_SWITCH\"" 'disk0_type="virtio-blk"' 'disk0_name="disk0.img"'
	printf '%s\n' "EOF_CONF"
	printf '%s\n' "printf '# guest %s: %s (cpu %s, memory %s)\\n' '$1' '$conf' '$2' '$3' >&2"
}

#@help _guest_network_write1
# @command guest network write <guest>
# @summary Act terminal (root): the clone's disk0.img attached as md, its root mounted by the image's label, hostname, the address on vtnet0 and the gateway VM_BAKE_GUEST_GATEWAY appended to rc.conf, resolv.conf pointing at the gateway, sshd bound to the address (ListenAddress), unmounted and detached -- the guest has no root, the host writes its network
# @group   guest
# @internal
# @see     guest make
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_GUEST_GATEWAY  the host's address on the bridge: gateway and resolver of the guests
#@end
_guest_network_write1() {
	local img="" addr="" disk="$VM_BAKE_GUEST_DIR/$1/disk0.img" mnt="$VM_BAKE_GUEST_DIR/$1/mnt"
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r addr 2>/dev/null < "$VM_BAKE_BASE/guest/$1/address" || addr=""
	printf '%s\n' "md=\$(mdconfig -a -t vnode -f '$disk') || exit 1"
	printf '%s\n' "mkdir -p '$mnt' && mount '/dev/gpt/$img-root' '$mnt' || { mdconfig -d -u \"\${md#md}\"; exit 1; }"
	printf '%s\n' "cat >> '$mnt/etc/rc.conf' <<'EOF_NET'"
	printf '%s\n' "hostname=\"$1\"" "ifconfig_vtnet0=\"inet $addr\"" "defaultrouter=\"$VM_BAKE_GUEST_GATEWAY\""
	printf '%s\n' "EOF_NET"
	printf '%s\n' "printf 'nameserver %s\\n' '$VM_BAKE_GUEST_GATEWAY' > '$mnt/etc/resolv.conf'"
	printf '%s\n' "test ! -f '$mnt/etc/ssh/sshd_config' || printf 'ListenAddress %s\\n' '${addr%/*}' >> '$mnt/etc/ssh/sshd_config'"
	printf '%s\n' "umount '$mnt' && rmdir '$mnt' && mdconfig -d -u \"\${md#md}\" || exit 1"
	printf '%s\n' "printf '# guest %s: %s on vtnet0, gateway %s\\n' '$1' '$addr' '$VM_BAKE_GUEST_GATEWAY' >&2"
}

#@help _guest_dns_write0
# @command guest dns write
# @summary Act terminal (root): VM_BAKE_DNS_FILE rendered from every guest record (read at generation time) -- for each guest 'local-data' <guest>.VM_BAKE_GUEST_DOMAIN A <address> and its 'local-data-ptr' -- then local_unbound reloaded; the host and every guest (their resolver is the host) know the names
# @group   guest
# @internal
# @see     guest make
# @see     guest drop
# @env     VM_BAKE_DNS_FILE  the unbound include file vm-bake owns
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest names live in
#@end
_guest_dns_write0() {
	local d="" a="" n=0
	printf '%s\n' "cat > '$VM_BAKE_DNS_FILE' <<'EOF_DNS'"
	printf '%s\n' "# written by vm-bake (guest make, guest drop) from its guest records -- do not edit" "server:"
	for d in "$VM_BAKE_BASE"/guest/*/; do
		test -f "$d/address" || continue
		IFS= read -r a < "$d/address"
		printf '\tlocal-data:     "%s.%s. A %s"\n' "$(basename "$d")" "$VM_BAKE_GUEST_DOMAIN" "${a%/*}"
		printf '\tlocal-data-ptr: "%s %s.%s"\n' "${a%/*}" "$(basename "$d")" "$VM_BAKE_GUEST_DOMAIN"
		n=$((n + 1))
	done
	printf '%s\n' "EOF_DNS"
	printf '%s\n' "chmod 0644 '$VM_BAKE_DNS_FILE' && service local_unbound reload > /dev/null || exit 1"
	printf '%s\n' "printf '# dns: %s guests in %s, unbound reloaded\\n' '$n' '$VM_BAKE_DNS_FILE' >&2"
}

#@help _guest_link_write1
# @command guest link write <guest>
# @summary Act terminal (root): the link VM_BAKE_VM_DIR/<guest> -> VM_BAKE_GUEST_DIR/<guest>, so vm-bhyve finds the guest in its vm_dir and the listing there shows which guests vm-bake manages
# @group   guest
# @internal
# @see     guest make
# @env     VM_BAKE_VM_DIR  vm-bhyve's vm_dir
# @env     VM_BAKE_GUEST_DIR  the guests' dataset
#@end
_guest_link_write1() {
	printf '%s\n' "ln -sfn '$VM_BAKE_GUEST_DIR/$1' '$VM_BAKE_VM_DIR/$1' || exit 1"
	printf '%s\n' "printf '# guest %s: %s -> %s\\n' '$1' '$VM_BAKE_VM_DIR/$1' '$VM_BAKE_GUEST_DIR/$1' >&2"
}

#@help _guest_link_drop1
# @command guest link drop <guest>
# @summary Act terminal (root): the link in VM_BAKE_VM_DIR removed
# @group   guest
# @internal
# @see     guest drop
# @env     VM_BAKE_VM_DIR  vm-bhyve's vm_dir
#@end
_guest_link_drop1() {
	printf '%s\n' "rm -f '$VM_BAKE_VM_DIR/$1'"
	printf '%s\n' "printf '# guest %s: link in %s removed\\n' '$1' '$VM_BAKE_VM_DIR' >&2"
}

#@help _guest_knownhosts_drop1
# @command guest knownhosts drop <guest>
# @summary Act terminal: the ssh host key remembered for the guest (.tmp/known_hosts.<guest>) forgotten -- a new clone has a new key
# @group   guest
# @internal
# @see     guest make
#@end
_guest_knownhosts_drop1() {
	printf '%s\n' "test -f '$VM_BAKE_BASE/.tmp/known_hosts.$1' && rm -f '$VM_BAKE_BASE/.tmp/known_hosts.$1' && printf '# guest %s: ssh host key forgotten\n' '$1' >&2 || printf '# guest %s: no ssh host key remembered yet\n' '$1' >&2"
}

#@help _guest_run1
# @command guest run <guest>
# @summary Act terminal (root): vm start <guest>
# @group   guest
# @internal
# @see     guest start
#@end
_guest_run1() {
	printf '%s\n' "vm start $(sq "$1") || exit 1"
	printf '%s\n' "printf '# guest %s started\\n' $(sq "$1") >&2"
}

#@help _guest_halt1
# @command guest halt <guest>
# @summary Act terminal (root): vm stop <guest> (ACPI shutdown; the guest decides how fast)
# @group   guest
# @internal
# @see     guest stop
#@end
_guest_halt1() {
	printf '%s\n' "vm stop $(sq "$1") || exit 1"
	printf '%s\n' "printf '# guest %s: shutdown sent\\n' $(sq "$1") >&2"
}

#@help _guest_dataset_destroy1
# @command guest dataset destroy <guest>
# @summary Act terminal (the invoking user, delegated by zfs allow): the guest's dataset (the clone) destroyed; none is a note
# @group   guest
# @internal
# @see     guest drop
# @env     VM_BAKE_GUEST_DIR  the guests' directory
#@end
_guest_dataset_destroy1() {
	printf '%s\n' "ds=\$(zfs list -H -o name '$VM_BAKE_GUEST_DIR/$1' 2>/dev/null) || { printf '# guest %s: no dataset\\n' '$1' >&2; exit 0; }"
	printf '%s\n' "zfs destroy -r \"\$ds\" || exit 1"
	printf '%s\n' "printf '# guest %s: %s destroyed\\n' '$1' \"\$ds\" >&2"
}

#@help _guest_list0
# @command guest list
# @summary List the guest records (one line each): name, image, address, created
# @group   guest
# @example vm-bake guest list
# @see     guest make
#@end
_guest_list0() {
	local d="" i="" a="" c="" n=0
	printf '%s\n' "# guests (name  image  address  created)"
	for d in "$VM_BAKE_BASE"/guest/*/; do
		test -f "$d/image" || continue
		IFS= read -r i < "$d/image"
		IFS= read -r a 2>/dev/null < "$d/address" || a=-
		IFS= read -r c 2>/dev/null < "$d/created" || c=-
		printf '#   %-16s %-28s %-20s %s\n' "$(basename "$d")" "$i" "$a" "$c"
		n=$((n + 1))
	done
	test "$n" -gt 0 || printf '%s\n' "#   (none)"
}
