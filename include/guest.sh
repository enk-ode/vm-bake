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
#
#   A guest whose template says 'service files view' has a view: the ZFS
#   dataset VM_BAKE_VIEW_DIR/<guest> in the invoking user's home, which
#   the guest mounts over virtio-9p as its whole home. There is one home,
#   the host's; the guest writes its own things into its view, sees of the
#   rest what the template's home lines allow ('guest start' hangs them in
#   as nullfs overlays, ro or rw), and has its own clones of the host's
#   repositories ('guest repo add'), which the host fetches back. The view
#   survives the guest: 'guest drop' keeps it, 'guest view drop' removes it.
#@end

#@help
# @defcompletion guest      guest
# @defcompletion address    none
# @defcompletion repo       none
#@end

#@help ___guest_make3
# @command guest make <image> <guest> <address>
# @summary Make a guest from a sealed image: the image has a record and a digest, the guest name is a record name and free; then the switch ensured, the record, the view of the host's home when the template says so (kept across rebuilds), the clone of @image, the configuration, the network written into the clone, the template's home paths seeded into the users' homes (a guest with a view takes them as overlays at 'guest start' instead), the guest's own ssh host key (kept in its record across rebuilds) installed, the host's unbound told the name
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check homes $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest switch ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest record write $(sq "$1") $(sq "$2") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest hostkey ensure $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view ensure $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest clone $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest conf write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest network write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest home write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest hostkey write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dns write"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest knownhosts drop $(sq "$2")"
}

#@help ___guest_start1
# @command guest start <guest>
# @summary Start the guest: it has a record and every home path of its template is there; then the overlays of the template hung into its view (a guest without a view: a note), the report of what the records say about it written into that view, and 'vm start'
# @group   guest
# @example vm-bake guest start bake
# @see     guest stop
# @see     guest make
# @see     guest view mount
# @see     guest report
#@end
___guest_start1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check homes $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view mount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest report $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest run $(sq "$1")"
}

#@help ___guest_stop1
# @command guest stop <guest>
# @summary Stop the guest: it has a record; then 'vm stop' (ACPI shutdown), the wait until its bhyve process is gone, and the overlays of its view let go
# @group   guest
# @example vm-bake guest stop bake
# @see     guest start
# @see     guest view unmount
#@end
___guest_stop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest halt $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest gone $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view unmount $(sq "$1")"
}

#@help ___guest_drop1
# @command guest drop <guest>
# @summary Remove the guest: it has a record and is not running (vm-bhyve's run.lock); the overlays of its view let go, whatever still holds the clone on the host released (a stale md, a mount), its dataset destroyed (a running guest makes zfs refuse: guest stop first), the record removed, unbound told, its ssh host key forgotten. The view itself stays -- a new image replaces the guest, not what it wrote; 'guest view drop' removes that too
# @group   guest
# @example vm-bake guest drop bake
# @see     guest make
# @see     guest stop
# @see     guest view drop
#@end
___guest_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check stopped $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view unmount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link drop $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest disk release $(sq "$1")"
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

#@help __guest_check_stopped1
# @command guest check stopped <guest>
# @summary The guest is not running by vm-bhyve's own mark, no run.lock in its directory (readable without root, where the bhyve process is not): a comment line, else an error line -- guest stop first
# @group   guest
# @internal
# @see     guest drop
# @see     guest stop
# @env     VM_BAKE_GUEST_DIR  the guests' directory
#@end
__guest_check_stopped1() {
	if test ! -e "$VM_BAKE_GUEST_DIR/$1/run.lock"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1 is not running")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest $1 is running (run.lock in $VM_BAKE_GUEST_DIR/$1): guest stop $1 first, then wait for bhyve to leave")"
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
# @summary Act terminal (the invoking user: the clone is theirs): the vm-bhyve configuration VM_BAKE_GUEST_DIR/<guest>/<guest>.conf: UEFI, cpu and memory from the image's template (read at generation time), disk0.img as virtio-blk, one virtio-net on VM_BAKE_GUEST_SWITCH, and when the template says 'service files view' the share home on VM_BAKE_VIEW_SLOT as bhyve_options (vm-bhyve hands that option to bhyve raw), which the image mounts as its home
# @group   guest
# @internal
# @see     guest make
# @see     guest view ensure
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_GUEST_SWITCH  the switch the guest hangs on
# @env     VM_BAKE_VIEW_DIR  the views' directory, the share's path on the host
# @env     VM_BAKE_VIEW_SLOT  the PCI slot of the virtio-9p device
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_conf_write1() {
	local conf="$VM_BAKE_GUEST_DIR/$1/$1.conf" img="" t="" cur="" chain="" p="" n=0 a="" res="" dir="$VM_BAKE_VIEW_DIR" view=no
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r res < "$VM_BAKE_BASE/template/$a/resource"; done
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'files view' && view=yes
	set -- "$1" ${res:-1 1G 0}
	printf '%s\n' "cat > '$conf' <<'EOF_CONF'"
	printf '%s\n' 'loader="uefi"' "cpu=$2" "memory=$3" 'network0_type="virtio-net"' "network0_switch=\"$VM_BAKE_GUEST_SWITCH\"" 'disk0_type="virtio-blk"' 'disk0_name="disk0.img"'
	test "$view" = no || printf '%s\n' "bhyve_options=\"-s $VM_BAKE_VIEW_SLOT,virtio-9p,home=$dir/$1\""
	printf '%s\n' "EOF_CONF"
	printf '%s\n' "printf '# guest %s: %s (cpu %s, memory %s, view $view)\\n' '$1' '$conf' '$2' '$3' >&2"
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
	printf '%s\n' "printf 'nameserver %s\\n' '$VM_BAKE_GUEST_GATEWAY' > '$mnt/etc/resolv.conf' && chmod 644 '$mnt/etc/resolv.conf'"
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

#@help ___guest_tag_add3
# @command guest tag add <guest> <key> <text>
# @summary Add a tag to the guest's own list (what belongs to this guest, not its template: owner, note, ...): the guest has a record, the key is a word; then 'guest tag append'. 'guest tag show' lists own and inherited tags, 'guest find' searches both
# @group   guest
# @example vm-bake guest tag add caledonia owner JB
# @see     guest tag drop
# @see     guest tag show
# @see     guest find
#@end
___guest_tag_add3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" template word valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest tag append $(sq "$1") $(sq "$2 $3")"
}

#@help ___guest_tag_drop3
# @command guest tag drop <guest> <key> <text>
# @summary Remove a tag from the guest's own list: the guest has a record, the line is listed; then 'guest tag remove'
# @group   guest
# @example vm-bake guest tag drop caledonia owner JB
# @see     guest tag add
#@end
___guest_tag_drop3() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest tag listed $(sq "$1") $(sq "$2 $3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest tag remove $(sq "$1") $(sq "$2 $3")"
}

#@help ___guest_tag_show1
# @command guest tag show <guest>
# @summary The guest's own tags and the tags inherited from its image's template, each with its origin: the guest has a record; then 'guest tag table'
# @group   guest
# @example vm-bake guest tag show caledonia
# @see     guest tag add
#@end
___guest_tag_show1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest tag table $(sq "$1")"
}

#@help __guest_tag_listed2
# @command guest tag listed <guest> <line>
# @summary The line is in the guest's own tag list: a comment line, else an error line (an inherited tag is the template's: template tag mask there)
# @group   guest
# @internal
# @see     guest tag drop
#@end
__guest_tag_listed2() {
	if grep -qxF "$2" "$VM_BAKE_BASE/guest/$1/tag" 2>/dev/null; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1: tag $2 listed")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest tag drop: $1 has no own tag '$2' (guest tag show $1; an inherited tag is masked in the template)")"
	fi
}

#@help _guest_tag_append2
# @command guest tag append <guest> <line>
# @summary Act terminal: the line appended to guest/<guest>/tag unless listed (0600)
# @group   guest
# @internal
# @see     guest tag add
#@end
_guest_tag_append2() {
	local f="$VM_BAKE_BASE/guest/$1/tag"
	printf '%s\n' "grep -qxF $(sq "$2") '$f' 2>/dev/null || printf '%s\\n' $(sq "$2") >> '$f'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$f'"
	printf '%s\n' "printf '# guest %s: tag + %s\\n' '$1' $(sq "$2") >&2"
}

#@help _guest_tag_remove2
# @command guest tag remove <guest> <line>
# @summary Act terminal: the line removed from guest/<guest>/tag
# @group   guest
# @internal
# @see     guest tag drop
#@end
_guest_tag_remove2() {
	local f="$VM_BAKE_BASE/guest/$1/tag"
	printf '%s\n' "{ grep -vxF $(sq "$2") '$f' > '$f.new' || true; } && mv -f '$f.new' '$f'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$f'"
	printf '%s\n' "printf '# guest %s: tag - %s\\n' '$1' $(sq "$2") >&2"
}

#@help _guest_tag_table1
# @command guest tag table <guest>
# @summary Display terminal: the guest's own tags (origin: the guest) and the resolved tags of its image's template (origin: the template they come from)
# @group   guest
# @internal
# @see     guest tag show
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_tag_table1() {
	local img="" t="" cur="" chain="" p="" n=0 line=""
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	printf '# tags of guest %s (origin  tag)\n' "$1"
	while IFS= read -r line; do test -z "$line" || printf '#   %-16s %s\n' "$1" "$line"; done < "$VM_BAKE_BASE/guest/$1/tag" 2>/dev/null
	awk -v base="$VM_BAKE_BASE" -v family=tag -v chain="empty${chain:+ $chain}" -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -v '(none)' || true
}

#@help _guest_find2
# @command guest find <key> <pattern>
# @summary Display terminal: every guest whose tags, own or inherited from its image's template, hold the key with a text matching the pattern (case-insensitive grep pattern; '.' for any): one line per hit, guest, image, origin, the tag -- answered from the records, no guest is started
# @group   guest
# @example vm-bake guest find can intellij
# @example vm-bake guest find purpose .
# @see     guest tag add
# @see     template find
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_find2() {
	local d="" g="" img="" t="" cur="" chain="" p="" n=0 own="" hit="" found=0
	printf '# guests with tag %s ~ %s (guest  image  origin  tag)\n' "$1" "$2"
	for d in "$VM_BAKE_BASE"/guest/*/; do
		g=$(basename "$d"); test -f "$d/image" || continue
		IFS= read -r img < "$d/image"
		IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
		cur=$t; chain=""; n=0
		while test "$cur" != empty && test "$n" -lt 32; do
			chain="$cur${chain:+ $chain}"
			IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
			cur=$p; n=$((n + 1))
		done
		own=$(awk -v g="$g" '{ printf "#   %-16s %s\n", g, $0 }' "$d/tag" 2>/dev/null || true)
		hit=$( { printf '%s\n' "$own"; awk -v base="$VM_BAKE_BASE" -v family=tag -v chain="empty${chain:+ $chain}" -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk"; } | awk -v k="$1" '$3 == k' | grep -i -- "$2" || true)
		test -z "$hit" || { printf '%s\n' "$hit" | sed "s/^#   /#   $(printf '%-12s %-26s' "$g" "$img") /"; found=$((found + 1)); }
	done
	test "$found" -gt 0 || printf '%s\n' "#   (none)"
}

#@help __guest_check_homes1
# @command guest check homes <guest>
# @summary Every home path of the image's template (read at generation time over the chain) exists under the invoking user's home: a comment line, else an error line naming the missing one
# @group   guest
# @internal
# @see     guest make
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
__guest_check_homes1() {
	local img="" t="" cur="" chain="" p="" n=0 h="" paths="" missing="" home=""
	eval "home=~$(id -un)"
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	paths=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | cut -d' ' -f1)
	for h in $paths; do test -e "$home/$h" || missing="$missing $h"; done
	if test -z "$missing"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1: home paths present ($(printf '%s' "$paths" | tr '\n' ' '))")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest make: home path missing under $home:$missing")"
	fi
}

#@help _guest_home_write1
# @command guest home write <guest>
# @summary Act terminal (root): the clone's disk0.img attached as md, its root mounted by the image's label, then every home path of the template (read at generation time) copied from the invoking user's home into the home of every user of the template, owned by that user (uid from the template, host uid for 'host', gid from the image's group file), unmounted and detached -- the guest has no root, the host seeds its homes. A guest with a view ('service files view') is seeded with nothing: its home is the host's, and the paths are hung in at 'guest start'
# @group   guest
# @internal
# @see     guest make
# @see     guest view mount
# @see     template home add
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_home_write1() {
	local name="$1" img="" t="" cur="" chain="" p="" n=0 paths="" users="" disk="$VM_BAKE_GUEST_DIR/$1/disk0.img" mnt="$VM_BAKE_GUEST_DIR/$1/mnt" h="" line="" u="" s="" uid="" home=""
	eval "home=~$(id -un)"
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'files view' && { emit_note "guest $1: its home comes from the host through its view, the paths are hung in at guest start, nothing seeded"; return 0; }
	paths=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | cut -d' ' -f1)
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -n "$paths" && test -n "$users" || { emit_note "guest $1: no home paths or no users in the template, nothing seeded"; return 0; }
	printf '%s\n' "md=\$(mdconfig -a -t vnode -f '$disk') || exit 1"
	printf '%s\n' "mkdir -p '$mnt' && mount '/dev/gpt/$img-root' '$mnt' || { mdconfig -d -u \"\${md#md}\"; exit 1; }"
	IFS='
'; set -- $users; IFS='
'
	for line; do
		u=${line%% *}; s=${line#* }; uid=$s
		test "$s" != host || uid=$(id -u "$u" 2>/dev/null || true)
		printf '%s\n' "g=\$(awk -F: -v u=$(sq "$u") '\$1 == u { print \$3 }' '$mnt/etc/group'); test -n \"\$g\" || { printf '# Error: no group %s in the image\\n' $(sq "$u") >&2; exit 1; }"
		for h in $paths; do
			printf '%s\n' "mkdir -p \"\$(dirname '$mnt/home/$u/$h')\" && cp -R '$home/$h' '$mnt/home/$u/$h' && chown -R $(sq "$uid"):\"\$g\" '$mnt/home/$u/${h%%/*}' || exit 1"
			printf '%s\n' "printf '# guest %s: %s -> home of %s\\n' '$name' '$h' $(sq "$u") >&2"
		done
	done
	printf '%s\n' "umount '$mnt' && rmdir '$mnt' && mdconfig -d -u \"\${md#md}\" || exit 1"
}

#@help __guest_check_view1
# @command guest check view <guest>
# @summary The guest has a view: its image's template says 'service files view' (read at generation time over the chain) and the view directory VM_BAKE_VIEW_DIR/<guest> is there: a comment line, else an error line
# @group   guest
# @internal
# @see     guest repo add
# @see     guest view ensure
# @env     VM_BAKE_VIEW_DIR  the views' directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
__guest_check_view1() {
	local dir="$VM_BAKE_VIEW_DIR" img="" t="" cur="" chain="" p="" n=0 ok=no
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'files view' && test -d "$dir/$1" && ok=yes
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1 has the view $dir/$1")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest $1 has no view (its template needs 'service files view', then guest make or guest view ensure $1)")"
	fi
}

#@help _guest_view_tree_ensure0
# @command guest view tree ensure
# @summary Act terminal (root, once per host): the datasets that carry the views -- beside the dataset that carries the invoking user's home, under its parent, the path of VM_BAKE_VIEW_DIR below that home as a dataset path (slash for slash, so the hierarchy reads like the path: <parent>/vm-bake/guest for ~/vm-bake/guest); the head of that path gets the mount point, everything below inherits it, and both are handed to the invoking user (the head 0755, the views' directory 0700). Every view 'guest view ensure' makes below it inherits the mount point too and needs no further right. An existing one is a note
# @group   guest
# @example vm-bake guest view tree ensure
# @see     guest view ensure
# @see     guest make
# @env     VM_BAKE_VIEW_DIR  the views' directory, the mount point this dataset path carries
#@end
_guest_view_tree_ensure0() {
	local dir="$VM_BAKE_VIEW_DIR" home="" u="" g="" rel="" carrier="" parent="" head=""
	eval "home=~$(id -un)"
	case "$dir" in "~/"*) dir="$home${dir#\~}" ;; esac
	u=$(id -un); g=$(id -gn)
	case "$dir" in "$home/"*) rel=${dir#"$home/"} ;; *) rel="" ;; esac
	test -n "$rel" || { generate_error "guest view tree ensure: VM_BAKE_VIEW_DIR ($dir) lies outside the home of $u ($home), and a view is a part of that home"; return 0; }
	carrier=$(df "$home" 2>/dev/null | awk 'NR == 2 { print $1 }')
	case "$carrier" in */?*) parent=${carrier%/*} ;; *) parent="" ;; esac
	test -n "$parent" || { generate_error "guest view tree ensure: no ZFS dataset below a parent carries $home (df says ${carrier:-nothing}), and the views live beside that dataset"; return 0; }
	head=${rel%%/*}
	printf '%s\n' "zfs list -H -o name '$dir' > /dev/null 2>&1 && { printf '# the views already live in %s\\n' '$dir' >&2; exit 0; }"
	printf '%s\n' "zfs list -H -o name '$parent/$head' > /dev/null 2>&1 || zfs create -o mountpoint='$home/$head' '$parent/$head' || exit 1"
	printf '%s\n' "zfs list -H -o name '$parent/$rel' > /dev/null 2>&1 || zfs create -p '$parent/$rel' || exit 1"
	printf '%s\n' "chown $(sq "$u"):$(sq "$g") '$home/$head' && chmod 0755 '$home/$head' || exit 1"
	printf '%s\n' "chown $(sq "$u"):$(sq "$g") '$dir' && chmod 0700 '$dir' || exit 1"
	printf '%s\n' "printf '# %s: the datasets of the views, mounted on %s\\n' '$parent/$rel' '$dir' >&2"
}

#@help _guest_view_ensure1
# @command guest view ensure <guest>
# @summary Act terminal (root): when the image's template says 'service files view' (read at generation time), the guest's view exists -- the ZFS dataset VM_BAKE_VIEW_DIR/<guest> under the view directory's own dataset ('guest view tree ensure' makes that one once), made once and owned by the invoking user, 0700; it is the whole home the guest sees and it survives every rebuild of the guest, so what the guest wrote is still there. No view in the template is a note
# @group   guest
# @internal
# @see     guest make
# @see     guest view tree ensure
# @see     guest view drop
# @see     image view write
# @env     VM_BAKE_VIEW_DIR  the views' directory, its dataset the parent of each view
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_view_ensure1() {
	local dir="$VM_BAKE_VIEW_DIR" img="" t="" cur="" chain="" p="" n=0 u="" g=""
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	u=$(id -un); g=$(id -gn)
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'files view' || { emit_note "guest $1: no view in the template $t, its home stays on its disk"; return 0; }
	printf '%s\n' "parent=\$(zfs list -H -o name '$dir') || { printf '# Error: %s is no dataset (vm-bake guest view tree ensure makes it once)\\n' '$dir' >&2; exit 1; }"
	printf '%s\n' "zfs list -H -o name '$dir/$1' > /dev/null 2>&1 || zfs create \"\$parent/$1\" || exit 1"
	printf '%s\n' "chown $(sq "$u"):$(sq "$g") '$dir/$1' && chmod 0700 '$dir/$1' || exit 1"
	printf '%s\n' "printf '# guest %s: view %s\\n' '$1' '$dir/$1' >&2"
}

#@help _guest_view_mount1
# @command guest view mount <guest>
# @summary Act terminal (root): the view is there and every home line of the image's template (read at generation time over the chain, '<path> <mode>') is hung into it as a nullfs overlay, ro or rw as the line says, the directory in the view made first; a line already hung in stays, a line from before the modes (a bare path) counts as ro. No view in the template is a note, a path that is no directory on the host an error -- an overlay is a directory
# @group   guest
# @internal
# @see     guest start
# @see     guest view unmount
# @see     template home add
# @env     VM_BAKE_VIEW_DIR  the views' directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_view_mount1() {
	local name="$1" dir="$VM_BAKE_VIEW_DIR" home="" img="" t="" cur="" chain="" p="" n=0 lines="" l="" path="" mode="" u="" g=""
	eval "home=~$(id -un)"
	case "$dir" in "~/"*) dir="$home${dir#\~}" ;; esac
	u=$(id -un); g=$(id -gn)
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'files view' || { emit_note "guest $1: no view in the template $t, nothing to hang in"; return 0; }
	test -d "$dir/$1" || { generate_error "guest view mount: $dir/$1 is not there -- the view is the home of this guest (guest view ensure $1)"; return 0; }
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | sort)
	test -n "$lines" || { emit_note "guest $1: the template $t hangs nothing into the view"; return 0; }
	IFS='
'; set -- $lines; IFS='
'
	for l; do
		path=${l%% *}; mode=ro
		case "$l" in *" "*) mode=${l##* } ;; esac
		test -d "$home/$path" || { generate_error "guest view mount: $home/$path is no directory, and an overlay of a view is one"; return 0; }
		printf '%s\n' "install -d -o $(sq "$u") -g $(sq "$g") -m 755 '$dir/$name/$path' || exit 1"
		printf '%s\n' "mount | grep -q \" on $dir/$name/$path (\" || mount -t nullfs -o $mode '$home/$path' '$dir/$name/$path' || exit 1"
		printf '%s\n' "printf '# guest %s: %s %s in its view\\n' '$name' '$path' '$mode' >&2"
	done
}

#@help _guest_view_unmount1
# @command guest view unmount <guest>
# @summary Act terminal (root): every mount under the guest's view (the mount table read at generation time, deepest first) let go, so the view holds only what the guest itself wrote; nothing hung in is a note
# @group   guest
# @internal
# @see     guest stop
# @see     guest view mount
# @env     VM_BAKE_VIEW_DIR  the views' directory
#@end
_guest_view_unmount1() {
	local dir="$VM_BAKE_VIEW_DIR" m="" mounts=""
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	mounts=$(mount | awk -v p="$dir/$1/" 'index($3, p) == 1 { print $3 }' | sort -r)
	test -n "$mounts" || { emit_note "guest $1: nothing hung into its view"; return 0; }
	for m in $mounts; do
		printf '%s\n' "umount '$m' || exit 1"
		printf '%s\n' "printf '# guest %s: %s let go\\n' '$1' '$m' >&2"
	done
}

#@help _guest_view_destroy1
# @command guest view destroy <guest>
# @summary Act terminal (root): the guest's view dataset destroyed -- everything the guest wrote in its home goes with it; no view is a note
# @group   guest
# @internal
# @see     guest view drop
# @env     VM_BAKE_VIEW_DIR  the views' directory
#@end
_guest_view_destroy1() {
	local dir="$VM_BAKE_VIEW_DIR"
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	printf '%s\n' "ds=\$(zfs list -H -o name '$dir/$1' 2>/dev/null) || { printf '# guest %s: no view\\n' '$1' >&2; exit 0; }"
	printf '%s\n' "zfs destroy -r \"\$ds\" || exit 1"
	printf '%s\n' "printf '# guest %s: view %s destroyed\\n' '$1' \"\$ds\" >&2"
}

#@help ___guest_view_drop1
# @command guest view drop <guest>
# @summary Throw the guest's view away: the guest is not running (vm-bhyve's run.lock); then whatever is hung into the view let go and its dataset destroyed. 'guest drop' keeps the view, this removes it -- the dotfiles, the state of the guest's tools and its clones are gone
# @group   guest
# @example vm-bake guest view drop dalmatia
# @see     guest view ensure
# @see     guest drop
#@end
___guest_view_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check stopped $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view unmount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view destroy $(sq "$1")"
}

#@help _guest_gone1
# @command guest gone <guest>
# @summary Act terminal: wait until the guest's bhyve process is gone (up to two minutes, then an error) -- 'vm stop' only sends the ACPI signal, and the view may be let go only after the last process of the guest has left it
# @group   guest
# @internal
# @see     guest stop
#@end
_guest_gone1() {
	printf '%s\n' "n=0; while pgrep -q -f 'bhyve: $1\$'; do n=\$((n + 1)); test \"\$n\" -lt 120 || { printf '# Error: guest %s still runs\\n' '$1' >&2; exit 1; }; sleep 1; done"
	printf '%s\n' "printf '# guest %s is down\\n' '$1' >&2"
}

#@help __guest_repo_valid1
# @command guest repo valid <repo>
# @summary The repository is a plain path relative to the invoking user's home (e.g. git/Infrastruktur), no '..': a comment line, else an error line
# @group   guest
# @internal
# @see     guest repo add
#@end
__guest_repo_valid1() {
	local ok=yes
	case "$1" in ""|/*|*/|..|../*|*/..|*/../*|*[!A-Za-z0-9_.+/-]*) ok=no ;; esac
	if test "$ok" = yes; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "repository $1 valid")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest repo: invalid repository $1 (a plain path relative to the home, e.g. git/Infrastruktur, no ..)")"
	fi
}

#@help ___guest_repo_add2
# @command guest repo add <guest> <repo>
# @summary Give the guest its own clone of one of the invoking user's repositories: the guest has a record and a view, the path is plain and relative to the home; then the clone written into the view at the same path, so the guest finds it where the host has it. A repository of the host is never hung into a view: git runs what .git/config and the hooks say, and a guest that fell would own the host
# @group   guest
# @example vm-bake guest repo add dalmatia git/Infrastruktur
# @see     guest repo fetch
# @see     guest repo show
# @see     guest repo drop
#@end
___guest_repo_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check view $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo clone $(sq "$1") $(sq "$2")"
}

#@help ___guest_repo_fetch2
# @command guest repo fetch <guest> <repo>
# @summary Fetch what the guest committed into the invoking user's own repository: the guest has a record and a view, the path is plain; then its branches fetched into refs/remotes/<guest>/* of the host's repository, where 'git log <guest>/main' reads them and 'git merge --ff-only <guest>/main' takes them over -- the host signs, the guest never does
# @group   guest
# @example vm-bake guest repo fetch dalmatia git/Infrastruktur
# @see     guest repo add
# @see     guest repo show
#@end
___guest_repo_fetch2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check view $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo refs $(sq "$1") $(sq "$2")"
}

#@help ___guest_repo_drop2
# @command guest repo drop <guest> <repo>
# @summary Remove the guest's clone from its view: the guest has a view, the path is plain; then the clone removed -- what the guest committed and the host has not fetched is gone with it
# @group   guest
# @example vm-bake guest repo drop dalmatia git/Infrastruktur
# @see     guest repo add
# @see     guest repo fetch
#@end
___guest_repo_drop2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check view $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo remove $(sq "$1") $(sq "$2")"
}

#@help _guest_repo_clone2
# @command guest repo clone <guest> <repo>
# @summary Act terminal (the invoking user, their own repository and their own view): the repository cloned into the view at the same path, without hardlinks (a hardlink would let the guest reach into the objects of the host's repository) and without a remote (the guest has no path to the host; 'guest repo fetch' is the way back)
# @group   guest
# @internal
# @see     guest repo add
# @env     VM_BAKE_VIEW_DIR  the views' directory
#@end
_guest_repo_clone2() {
	local dir="$VM_BAKE_VIEW_DIR" home=""
	eval "home=~$(id -un)"
	case "$dir" in "~/"*) dir="$home${dir#\~}" ;; esac
	printf '%s\n' "test -d '$home/$2/.git' || { printf '# Error: %s is no repository of the host\\n' '$home/$2' >&2; exit 1; }"
	printf '%s\n' "test ! -e '$dir/$1/$2' || { printf '# Error: %s exists in the view of %s\\n' '$2' '$1' >&2; exit 1; }"
	printf '%s\n' "install -d -m 755 \"\$(dirname '$dir/$1/$2')\" || exit 1"
	printf '%s\n' "git clone --no-hardlinks '$home/$2' '$dir/$1/$2' || exit 1"
	printf '%s\n' "git -C '$dir/$1/$2' remote remove origin || exit 1"
	printf '%s\n' "printf '# guest %s: clone of %s in its view\\n' '$1' '$2' >&2"
}

#@help _guest_repo_refs2
# @command guest repo refs <guest> <repo>
# @summary Act terminal (the invoking user, in their OWN repository): 'git fetch' from the guest's clone into refs/remotes/<guest>/*, no tags -- the host reads the guest's commits without ever running git inside the guest's clone, whose configuration and hooks belong to the guest
# @group   guest
# @internal
# @see     guest repo fetch
# @env     VM_BAKE_VIEW_DIR  the views' directory
#@end
_guest_repo_refs2() {
	local dir="$VM_BAKE_VIEW_DIR" home=""
	eval "home=~$(id -un)"
	case "$dir" in "~/"*) dir="$home${dir#\~}" ;; esac
	printf '%s\n' "test -d '$dir/$1/$2/.git' || { printf '# Error: no clone %s in the view of %s (guest repo add)\\n' '$2' '$1' >&2; exit 1; }"
	printf '%s\n' "git -C '$home/$2' fetch --no-tags --prune '$dir/$1/$2' \"+refs/heads/*:refs/remotes/$1/*\" || exit 1"
	printf '%s\n' "printf '# guest %s: its branches are %s/* in %s now\\n' '$1' '$1' '$home/$2' >&2"
}

#@help _guest_repo_remove2
# @command guest repo remove <guest> <repo>
# @summary Act terminal (the invoking user, their own view): the clone removed from the view
# @group   guest
# @internal
# @see     guest repo drop
# @env     VM_BAKE_VIEW_DIR  the views' directory
#@end
_guest_repo_remove2() {
	local dir="$VM_BAKE_VIEW_DIR"
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	printf '%s\n' "test -d '$dir/$1/$2/.git' || { printf '# Error: no clone %s in the view of %s\\n' '$2' '$1' >&2; exit 1; }"
	printf '%s\n' "rm -rf '$dir/$1/$2' || exit 1"
	printf '%s\n' "printf '# guest %s: clone %s removed from its view\\n' '$1' '$2' >&2"
}

#@help _guest_repo_show1
# @command guest repo show <guest>
# @summary The clones in the guest's view, one line each: the path as the guest sees it under its home and the branch its HEAD names (the file read, no git run in the guest's clone)
# @group   guest
# @example vm-bake guest repo show dalmatia
# @see     guest repo add
# @see     guest repo fetch
# @env     VM_BAKE_VIEW_DIR  the views' directory
#@end
_guest_repo_show1() {
	local dir="$VM_BAKE_VIEW_DIR" g="" d="" b="" n=0
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	printf '%s\n' "# clones in the view of $1 (path  branch)"
	for g in $(find "$dir/$1" -maxdepth 5 -type d -name .git 2>/dev/null | sort); do
		d=${g%/.git}
		IFS= read -r b 2>/dev/null < "$g/HEAD" || b="-"
		printf '#   %-40s %s\n' "${d#$dir/$1/}" "${b#ref: refs/heads/}"
		n=$((n + 1))
	done
	test "$n" -gt 0 || printf '%s\n' "#   (none)"
}

#@help _guest_hostkey_ensure1
# @command guest hostkey ensure <guest>
# @summary Act terminal: the guest's ssh host key lives in its record (guest/<guest>/ssh_host_ed25519_key, made once with ssh-keygen, 0600) and survives every rebuild of the guest, so the host's known_hosts stays right; an existing key is kept
# @group   guest
# @internal
# @see     guest make
# @see     guest hostkey write
#@end
_guest_hostkey_ensure1() {
	local k="$VM_BAKE_BASE/guest/$1/ssh_host_ed25519_key"
	printf '%s\n' "test -f '$k' || ssh-keygen -q -t ed25519 -N '' -C 'vm-bake guest $1' -f '$k' || exit 1"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$k' '$k.pub'"
	printf '%s\n' "printf '# guest %s: host key %s\\n' '$1' \"\$(ssh-keygen -l -f '$k.pub' | cut -d' ' -f2)\" >&2"
}

#@help _guest_hostkey_write1
# @command guest hostkey write <guest>
# @summary Act terminal (root): the clone's disk0.img attached as md, its root mounted by the image's label, the guest's host key from the record written to /etc/ssh/ssh_host_ed25519_key (root, 0600; the public half 0644), unmounted and detached -- sshd in the guest uses it from the first boot, the other key types it makes itself
# @group   guest
# @internal
# @see     guest make
# @see     guest hostkey ensure
# @env     VM_BAKE_GUEST_DIR  the guests' directory
#@end
_guest_hostkey_write1() {
	local img="" k="$VM_BAKE_BASE/guest/$1/ssh_host_ed25519_key" disk="$VM_BAKE_GUEST_DIR/$1/disk0.img" mnt="$VM_BAKE_GUEST_DIR/$1/mnt"
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	printf '%s\n' "md=\$(mdconfig -a -t vnode -f '$disk') || exit 1"
	printf '%s\n' "mkdir -p '$mnt' && mount '/dev/gpt/$img-root' '$mnt' || { mdconfig -d -u \"\${md#md}\"; exit 1; }"
	printf '%s\n' "install -m 600 -o root -g wheel '$k' '$mnt/etc/ssh/ssh_host_ed25519_key' && install -m 644 -o root -g wheel '$k.pub' '$mnt/etc/ssh/ssh_host_ed25519_key.pub' || { umount '$mnt'; mdconfig -d -u \"\${md#md}\"; exit 1; }"
	printf '%s\n' "umount '$mnt' && rmdir '$mnt' && mdconfig -d -u \"\${md#md}\" || exit 1"
	printf '%s\n' "printf '# guest %s: host key installed\\n' '$1' >&2"
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

#@help _guest_disk_release1
# @command guest disk release <guest>
# @summary Act terminal (root): whatever still holds the clone on this host let go -- its root unmounted from <guest>/mnt if mounted, an md attached to its disk0.img detached (a network or home write that died mid-way leaves both), nothing to do is a note
# @group   guest
# @internal
# @see     guest drop
# @env     VM_BAKE_GUEST_DIR  the guests' directory
#@end
_guest_disk_release1() {
	local dir="$VM_BAKE_GUEST_DIR/$1" disk="$VM_BAKE_GUEST_DIR/$1/disk0.img"
	printf '%s\n' "umount '$dir/mnt' 2>/dev/null; rmdir '$dir/mnt' 2>/dev/null; true"
	printf '%s\n' "md=\$(mdconfig -lv | awk -v f='$disk' '\$4 == f { print \$1; exit }'); test -z \"\$md\" || mdconfig -d -u \"\${md#md}\" || exit 1"
	printf '%s\n' "printf '# guest %s: released on the host%s\\n' '$1' \"\${md:+ (\$md detached)}\" >&2"
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

#@help _guest_show1
# @command guest show <guest>
# @summary Everything the records say about one guest, as comment lines: its own record (image, address, created, the fingerprint of its ssh host key), the template behind its image with the resolved chain and resources, whether it has a view and where, and every list family resolved over the chain with its origin -- the SOLL of this guest, against which it can be checked from inside. 'guest report' is the same text, written into the guest's view
# @group   guest
# @example vm-bake guest show dalmatia
# @see     guest list
# @see     guest report
# @see     template show
# @env     VM_BAKE_VIEW_DIR  the views' directory
# @env     VM_BAKE_VIEW_SLOT  the PCI slot of the 9p device the share rides on
# @env     VM_BAKE_SSH_PORT  the port sshd listens on in the guest
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest's name lives in
# @env     VM_BAKE_GUEST_GATEWAY  gateway and resolver of the guests
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_show1() {
	local d="$VM_BAKE_BASE/guest/$1" img="" t="" cur="" chain="" p="" n=0 a="" res="" f="" dir="$VM_BAKE_VIEW_DIR" view=no addr=- created=- key=-
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	IFS= read -r img 2>/dev/null < "$d/image" || img=-
	IFS= read -r addr 2>/dev/null < "$d/address" || addr=-
	IFS= read -r created 2>/dev/null < "$d/created" || created=-
	test ! -f "$d/ssh_host_ed25519_key.pub" || key=$(ssh-keygen -l -f "$d/ssh_host_ed25519_key.pub" 2>/dev/null | cut -d' ' -f2)
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/resource" && IFS= read -r res < "$VM_BAKE_BASE/template/$a/resource"; done
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'files view' && view=yes
	printf '# guest %s (the records of %s, read %s)\n' "$1" "$(hostname)" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	printf '#   image     %s\n#   template  %s\n#   chain     %s\n' "$img" "$t" "empty > $(printf '%s' "$chain" | tr ' ' '>' | sed 's/>/ > /g')"
	printf '#   address   %s (gateway and resolver %s, name %s.%s)\n' "$addr" "$VM_BAKE_GUEST_GATEWAY" "$1" "$VM_BAKE_GUEST_DOMAIN"
	printf '#   resource  %s (cpu memory disk)\n#   sshd      port %s, keys only, /etc/ssh/authorized_keys/<user>\n' "${res:--}" "$VM_BAKE_SSH_PORT"
	printf '#   hostkey   %s\n#   created   %s\n' "$key" "$created"
	printf '#   view      %s\n' "$(test "$view" = no && printf 'none (the home lies on the disk of the guest)' || printf '%s on the host, mounted as the home over p9fs (slot %s, share home)' "$dir/$1" "$VM_BAKE_VIEW_SLOT")"
	for f in $TEMPLATE_FAMILIES; do
		printf '# %s (origin  entry)\n' "$f"
		awk -v base="$VM_BAKE_BASE" -v family="$f" -v chain="empty${chain:+ $chain}" -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk"
	done
}

#@help ___guest_report1
# @command guest report <guest>
# @summary Write what 'guest show' says into the guest's own view, as GUEST.txt beside its home, so the guest can hold its SOLL against what it finds: the guest has a record; then the text rendered into GUEST.txt.new and put in place. A guest without a view has nowhere to put it and gets a comment
# @group   guest
# @example vm-bake guest report dalmatia
# @see     guest show
# @see     guest start
# @env     VM_BAKE_VIEW_DIR  the views' directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
___guest_report1() {
	local img="" t="" cur="" chain="" p="" n=0 dir="$VM_BAKE_VIEW_DIR" view=no
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'files view' && view=yes
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	test "$view" = no || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest show $(sq "$1") > $(sq "$dir/$1/GUEST.txt.new")" "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest report place $(sq "$1")"
	test "$view" = yes || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1: no view in the template $t, nowhere to put a report")"
}

#@help _guest_report_place1
# @command guest report place <guest>
# @summary Act terminal (the invoking user, the view is theirs): GUEST.txt.new moved into place as GUEST.txt (0644) and the lines counted; nothing rendered is an error
# @group   guest
# @internal
# @see     guest report
# @env     VM_BAKE_VIEW_DIR  the views' directory
#@end
_guest_report_place1() {
	local dir="$VM_BAKE_VIEW_DIR" f=""
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	f="$dir/$1/GUEST.txt"
	printf '%s\n' "test -s '$f.new' || { printf '# Error: no report rendered (%s)\\n' '$f.new' >&2; exit 1; }"
	printf '%s\n' "chmod 0644 '$f.new' && mv -f '$f.new' '$f' || exit 1"
	printf '%s\n' "printf '# guest %s: %s lines in %s\\n' '$1' \"\$(grep -c . '$f')\" '$f' >&2"
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

#@help ___guest_dump_all0
# @command guest dump all
# @summary Every guest record as replay lines, one 'guest dump record' per record, no records a comment -- the dump's witness of the guests (image, address, created, own tags); the clone never travels, 'guest make' makes it anew, the host key comes with the bundle
# @group   guest
# @see     dump all
# @see     guest dump record
#@end
___guest_dump_all0() {
	local d="" n=0
	for d in "$VM_BAKE_BASE"/guest/*/; do
		test -f "$d/image" || continue
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dump record $(sq "$(basename "$d")")"
		n=$((n + 1))
	done
	test "$n" -gt 0 || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment 'no guest records to dump'"
}

#@help ___guest_dump_record1
# @command guest dump record <guest>
# @summary The replay lines of one guest record, a batch pinned to cat so it is shown rather than run: 'guest record restore <guest> <image> <address> <created>', then 'guest tag add' for every own tag
# @group   guest
# @internal
# @see     guest dump all
# @see     guest record restore
#@end
___guest_dump_record1() {
	local d="$VM_BAKE_BASE/guest/$1" i="" a="" c="" l=""
	IFS= read -r i 2>/dev/null < "$d/image" || i=-
	IFS= read -r a 2>/dev/null < "$d/address" || a=-
	IFS= read -r c 2>/dev/null < "$d/created" || c=-
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest record restore $(sq "$1") $(sq "$i") $(sq "$a") $(sq "$c")"
	test -f "$d/tag" && while IFS= read -r l; do
		test -n "$l" || continue
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest tag add $(sq "$1") $(sq "${l%% *}") $(sq "${l#* }")"
	done < "$d/tag"
	return 0
}

#@help ___guest_record_restore4
# @command guest record restore <guest> <image> <address> <created>
# @summary A record from a dump, the witness of a guest made elsewhere or before: the name and the address valid; then 'guest record compare' -- no record of that name here: placed; the same record: a comment; one that differs: an error. The record stands for a clone that is NOT here: 'guest drop <guest>' lets it go, 'guest make <image> <guest> <address>' makes it anew; a host key placed by import keeps its identity
# @group   guest
# @example vm-bake guest record restore caledonia freebsd-x-20261102 172.16.100.102/24 2026-11-02T15:56:46Z
# @see     guest dump all
# @see     guest record compare
# @see     guest make
#@end
___guest_record_restore4() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest name valid $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest address valid $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest record compare $(sq "$1") $(sq "$2") $(sq "$3") $(sq "$4")"
}

#@help __guest_record_compare4
# @command guest record compare <guest> <image> <address> <created>
# @summary The record here against the one from the dump, read at generation: none -> 'guest record place'; the same image, address and created -> a comment line; a record that differs -> an error line (guest drop <guest> first, or keep yours)
# @group   guest
# @internal
# @see     guest record restore
# @see     guest record place
#@end
__guest_record_compare4() {
	local d="$VM_BAKE_BASE/guest/$1" i="" a="" c=""
	IFS= read -r i 2>/dev/null < "$d/image" || i=""
	IFS= read -r a 2>/dev/null < "$d/address" || a=""
	IFS= read -r c 2>/dev/null < "$d/created" || c=""
	if test ! -f "$d/image"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest record place $(sq "$1") $(sq "$2") $(sq "$3") $(sq "$4")"
	elif test "$i" = "$2" && test "$a" = "$3" && test "$c" = "$4"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1: record identical, kept")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest record restore: $1 has a record here that differs (image $i, address $a, created $c) -- guest drop $1 first, or keep yours")"
	fi
}

#@help _guest_record_place4
# @command guest record place <guest> <image> <address> <created>
# @summary Act terminal: the record guest/<guest>/ written from a dump -- image, address and created as given; 0700 and 0600 (a host key import placed there before stays)
# @group   guest
# @internal
# @see     guest record compare
# @see     guest record write
#@end
_guest_record_place4() {
	local rec="$VM_BAKE_BASE/guest/$1"
	printf '%s\n' "$MODIFY_DIR_CREATE '$rec' && $MODIFY_FILE_PERMS 0700 '$rec'"
	printf '%s\n' "printf '%s\\n' $(sq "$2") > '$rec/image'"
	printf '%s\n' "printf '%s\\n' $(sq "$3") > '$rec/address'"
	printf '%s\n' "printf '%s\\n' $(sq "$4") > '$rec/created'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$rec/image' '$rec/address' '$rec/created'"
	emit_note "guest $1: record restored (image $2, address $3, created $4)"
}
