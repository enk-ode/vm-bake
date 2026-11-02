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
# @summary Make a guest from a sealed image: the image has a record and a digest, the guest name is a record name and free; then the switch ensured, the record, the clone of @image, the configuration, the network written into the clone, the template's home paths seeded into the users' homes, the guest's own ssh host key (kept in its record across rebuilds) installed, the host's unbound told the name
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
# @summary Remove the guest: it has a record; whatever still holds the clone on the host released (a stale md, a mount), its dataset destroyed (a running guest makes zfs refuse: guest stop first), the record removed, unbound told, its ssh host key forgotten
# @group   guest
# @example vm-bake guest drop bake
# @see     guest make
# @see     guest stop
#@end
___guest_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
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
	paths=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	for h in $paths; do test -e "$home/$h" || missing="$missing $h"; done
	if test -z "$missing"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1: home paths present ($(printf '%s' "$paths" | tr '\n' ' '))")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest make: home path missing under $home:$missing")"
	fi
}

#@help _guest_home_write1
# @command guest home write <guest>
# @summary Act terminal (root): the clone's disk0.img attached as md, its root mounted by the image's label, then every home path of the template (read at generation time) copied from the invoking user's home into the home of every user of the template, owned by that user (uid from the template, host uid for 'host', gid from the image's group file), unmounted and detached -- the guest has no root, the host seeds its homes
# @group   guest
# @internal
# @see     guest make
# @see     template home add
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_home_write1() {
	local img="" t="" cur="" chain="" p="" n=0 paths="" users="" disk="$VM_BAKE_GUEST_DIR/$1/disk0.img" mnt="$VM_BAKE_GUEST_DIR/$1/mnt" h="" line="" u="" s="" uid="" home=""
	eval "home=~$(id -un)"
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	paths=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
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
			printf '%s\n' "printf '# guest %s: %s -> home of %s\\n' '$1' '$h' $(sq "$u") >&2"
		done
	done
	printf '%s\n' "umount '$mnt' && rmdir '$mnt' && mdconfig -d -u \"\${md#md}\" || exit 1"
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
