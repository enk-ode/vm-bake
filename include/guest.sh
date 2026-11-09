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
# @summary Make a guest from a sealed image: the image has a record and a digest, the guest name is a record name and free, the mirrors' directory VM_BAKE_REPO_VIEWS made under the invoking user's home when it is missing (guest repo tree ensure) and every home path of the template there; then the switch ensured, the record, the view of the host's home when the template says so (kept across rebuilds), the clone of @image, the configuration, the network written into the clone, the template's home paths seeded into the users' homes (a guest with a view takes them as overlays at 'guest start' instead), the ssh host key the guest carries installed (a resource of the database under a name of its own, made under the guest's name when the record binds none), the host's unbound told the name
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
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check homes $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" image tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest switch ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest log rotate ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest record write $(sq "$1") $(sq "$2") $(sq "$3")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest hostkey ensure $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view ensure $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest clone $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest conf write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest disk write $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dns write"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest knownhosts drop $(sq "$2")"
}

#@help ___guest_start1
# @command guest start <guest>
# @summary Start the guest: it has a record, it is not running already (vm-bhyve's run.lock -- the check stands first, so a running guest costs neither a mount nor the sudo behind it), the mirrors' directory VM_BAKE_REPO_VIEWS made under the invoking user's home when it is missing (guest repo tree ensure -- the one home path the tool owns, so no hand makes it) and every home path of its template is there; then the dowry of its template placed in its view, the overlays of the template hung in (a guest without a view: a note), the report of what the records say about it written into that view, the fetched mark dropped (it is about to commit again), 'vm start', and 'guest repo ensure' -- the clones its record lists made on its disk once it answers ssh
# @group   guest
# @example vm-bake guest start bake
# @see     guest stop
# @see     guest make
# @see     guest dowry place
# @see     guest view mount
# @see     guest report
#@end
___guest_start1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check stopped $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo tree ensure"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check homes $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dowry place $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view mount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest report $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest fetched drop $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest run $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo ensure $(sq "$1")"
}

#@help ___guest_stop1
# @command guest stop <guest>
# @summary Stop the guest: it has a record; then 'guest repo hold' (its commits fetched into the host's repositories and the fetched mark written, while it still answers), 'vm stop' (ACPI shutdown), the wait until its bhyve process is gone, the vm instance released if one is left behind, and the overlays of its view let go
# @group   guest
# @example vm-bake guest stop bake
# @see     guest start
# @see     guest vmm release
# @see     guest view unmount
#@end
___guest_stop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo hold $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest halt $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest gone $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest vmm release $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view unmount $(sq "$1")"
}

#@help ___guest_drop1
# @command guest drop <guest>
# @summary Remove the guest: it has a record, is not running (vm-bhyve's run.lock) and its repositories are fetched (the mark of 'guest stop'; 'guest drop unfetched' gives them up); the overlays of its view let go, whatever still holds the clone on the host released (a stale md, a mount), its dataset destroyed (a running guest makes zfs refuse: guest stop first), the record removed with its hostkey binding, unbound told, what the host remembered of its ssh host key forgotten. The ssh host key itself stays in the database and is free again, so the guest built anew under that name takes it back and answers with the same identity; the view stays too -- a new image replaces the guest, not what it wrote ('guest view drop' removes that, 'hostkey drop' the key)
# @group   guest
# @example vm-bake guest drop bake
# @see     guest make
# @see     guest stop
# @see     guest view drop
#@end
___guest_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check stopped $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check fetched $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest view unmount $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest link drop $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest disk release $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dataset destroy $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest record remove $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dns write"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest knownhosts drop $(sq "$1")"
}

#@help ___guest_drop_unfetched1
# @command guest drop unfetched <guest>
# @summary 'guest drop' without the fetched check: the guest's commits that the host never fetched are given up with its disk -- for a guest stopped by other means whose clones hold nothing worth a start and a stop
# @group   guest
# @example vm-bake guest drop unfetched bake
# @see     guest drop
# @see     guest check fetched
#@end
___guest_drop_unfetched1() {
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
# @summary Nothing of the guest is running any more -- neither vm-bhyve's own mark (run.lock in its directory, readable without root) nor the vm instance the kernel keeps for it (/dev/vmm/<guest>): a comment line, else an error line naming which of the two it is. A bhyve that died without taking its instance with it leaves the second one behind, and vm-bhyve then refuses to start the guest at all ('guest vmm release' clears it)
# @group   guest
# @internal
# @see     guest drop
# @see     guest stop
# @see     guest start
# @see     guest vmm release
# @env     VM_BAKE_GUEST_DIR  the guests' directory
#@end
__guest_check_stopped1() {
	local why=""
	test ! -e "$VM_BAKE_GUEST_DIR/$1/run.lock" || why="run.lock in $VM_BAKE_GUEST_DIR/$1 (guest stop $1 first, then wait for bhyve to leave)"
	test ! -e "/dev/vmm/$1" || why="${why:+$why; }the vm instance /dev/vmm/$1 (a stale one of a bhyve that died: guest vmm release $1)"
	if test -z "$why"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1 is not running")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest $1 is running: $why")"
	fi
}

#@help _guest_vmm_release1
# @command guest vmm release <guest>
# @summary Act terminal (root): the vm instance the kernel keeps for the guest (/dev/vmm/<guest>) destroyed with bhyvectl -- what a bhyve leaves behind when it dies, and what makes vm-bhyve say 'guest appears to be running already' even with no process and no run.lock; none there is a note
# @group   guest
# @internal
# @see     guest stop
# @see     guest check stopped
#@end
_guest_vmm_release1() {
	printf '%s\n' "test -e '/dev/vmm/$1' || { printf '# guest %s: no vm instance to release\\n' '$1' >&2; exit 0; }"
	printf '%s\n' "bhyvectl --destroy --vm=$(sq "$1") || exit 1"
	printf '%s\n' "printf '# guest %s: vm instance /dev/vmm/%s destroyed\\n' '$1' '$1' >&2"
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

#@help _guest_log_rotate_ensure0
# @command guest log rotate ensure
# @summary Act terminal (root): VM_BAKE_LOG_ROTATE_FILE written -- the newsyslog entries for the logs of EVERY guest, by shell pattern over VM_BAKE_GUEST_DIR (flag G), so a guest that comes later needs no entry of its own: <guest>/bhyve.log (what bhyve says, kept because every guest is configured with debug) and <guest>/vm-bhyve.log (what the runner says), root and the invoking user's group, 0640, VM_BAKE_LOG_ROTATE_KEEP generations of VM_BAKE_LOG_ROTATE_SIZE KB, gzipped, no process to signal. Written anew every time: the file belongs to vm-bake, its numbers come from the environment
# @group   guest
# @example vm-bake guest log rotate ensure
# @see     guest make
# @see     guest conf write
# @env     VM_BAKE_LOG_ROTATE_FILE  the newsyslog include file vm-bake owns
# @env     VM_BAKE_LOG_ROTATE_KEEP  how many rotated generations are kept
# @env     VM_BAKE_LOG_ROTATE_SIZE  the size in KB at which a log is rotated
# @env     VM_BAKE_GUEST_DIR  the guests' directory the patterns cover
#@end
_guest_log_rotate_ensure0() {
	local f="$VM_BAKE_LOG_ROTATE_FILE" g=""
	g=$(id -gn)
	printf '%s\n' "install -d -m 755 $(sq "$(dirname "$f")") || exit 1"
	printf '%s\n' "cat > '$f' <<'EOF_ROTATE'"
	printf '%s\n' "# written by vm-bake (guest log rotate ensure) -- do not edit"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$VM_BAKE_GUEST_DIR/*/bhyve.log" "root:$g" 640 "$VM_BAKE_LOG_ROTATE_KEEP" "$VM_BAKE_LOG_ROTATE_SIZE" '*' GNZ
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$VM_BAKE_GUEST_DIR/*/vm-bhyve.log" "root:$g" 640 "$VM_BAKE_LOG_ROTATE_KEEP" "$VM_BAKE_LOG_ROTATE_SIZE" '*' GNZ
	printf '%s\n' "EOF_ROTATE"
	printf '%s\n' "chmod 0644 '$f' || exit 1"
	printf '%s\n' "printf '# log rotation: %s (%s generations of %s KB, gzipped)\\n' '$f' '$VM_BAKE_LOG_ROTATE_KEEP' '$VM_BAKE_LOG_ROTATE_SIZE' >&2"
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
# @summary Act terminal (the invoking user: the clone is theirs): the vm-bhyve configuration VM_BAKE_GUEST_DIR/<guest>/<guest>.conf: UEFI, cpu and memory from the image's template (read at generation time), the cpu layout as cpu_sockets, cpu_cores and cpu_threads (the template's topology record, else 1 socket of <cpu> cores with 1 thread each -- without it bhyve invents two threads per core and the guest's scheduler believes in SMT that is not there; the product has to be the cpu count, else an error), disk0.img as virtio-blk, one virtio-net on VM_BAKE_GUEST_SWITCH, debug="yes" (vm-bhyve then keeps what bhyve says in <guest>/bhyve.log instead of throwing it away -- it costs nothing, bhyve writes only when it has something to report, and without it a bhyve that dies at startup leaves no reason behind), and when the template says 'service files view' the share home on VM_BAKE_VIEW_SLOT as bhyve_options (vm-bhyve hands that option to bhyve raw), which the image mounts as its home; an autoinstall guest (OpenBSD) gets -w among the bhyve_options -- bhyve then ignores the MSRs OpenBSD's kernel touches and bhyve does not implement, without it bhyve dies at the kernel's first instructions
# @group   guest
# @internal
# @see     guest make
# @see     template topology
# @see     guest view ensure
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_GUEST_SWITCH  the switch the guest hangs on
# @env     VM_BAKE_VIEW_DIR  the views' directory, the share's path on the host
# @env     VM_BAKE_VIEW_SLOT  the PCI slot of the virtio-9p device
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_conf_write1() {
	local conf="$VM_BAKE_GUEST_DIR/$1/$1.conf" img="" t="" cur="" chain="" p="" n=0 a="" res="" top="" dir="$VM_BAKE_VIEW_DIR" view=no bake="" addr="" mac="" opts=""
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
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/topology" && IFS= read -r top < "$VM_BAKE_BASE/template/$a/topology"; done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/bake" && IFS= read -r bake < "$VM_BAKE_BASE/template/$a/bake"; done
	IFS= read -r addr 2>/dev/null < "$VM_BAKE_BASE/guest/$1/address" || addr=""
	mac=$(printf '%s' "${addr%/*}" | awk -F. '{ printf "58:9c:fc:%02x:%02x:%02x", $2, $3, $4 }')
	awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -qx 'files view' && view=yes
	set -- "$1" ${res:-1 1G 0}
	top=${top:-1 $2 1}
	test "$(printf '%s' "$top" | awk '{ print $1 * $2 * $3 }')" = "$2" || { generate_error "guest conf write: the topology of $t is '$top', whose product is not the cpu count $2 of its resource record (template topology $t <sockets> <cores> <threads>, or template resource)"; return 0; }
	printf '%s\n' "cat > '$conf' <<'EOF_CONF'"
	printf '%s\n' 'loader="uefi"' "cpu=$2" "memory=$3" "cpu_sockets=$(printf '%s' "$top" | cut -d' ' -f1)" "cpu_cores=$(printf '%s' "$top" | cut -d' ' -f2)" "cpu_threads=$(printf '%s' "$top" | cut -d' ' -f3)" 'network0_type="virtio-net"' "network0_switch=\"$VM_BAKE_GUEST_SWITCH\"" 'disk0_type="virtio-blk"' 'disk0_name="disk0.img"' 'debug="yes"'
	test "$view" = no || opts="-s $VM_BAKE_VIEW_SLOT,virtio-9p,home=$dir/$1"
	test "$bake" != autoinstall || opts="${opts:+$opts }-w"
	test -z "$opts" || printf '%s\n' "bhyve_options=\"$opts\""
	case "$bake" in cloud-init|autoinstall) printf '%s\n' "network0_mac=\"$mac\"" 'disk1_type="ahci-cd"' "disk1_name=\"$VM_BAKE_GUEST_DIR/$1/seed.iso\"" 'disk1_dev="custom"' ;; esac
	printf '%s\n' "EOF_CONF"
	printf '%s\n' "printf '# guest %s: %s (cpu %s as %s, memory %s, view $view)\\n' '$1' '$conf' '$2' $(sq "$top") '$3' >&2"
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
	printf '%s\n' "mkdir -p '$mnt' && mount -t ufs '/dev/gpt/$img-root' '$mnt' || { mdconfig -d -u \"\${md#md}\"; exit 1; }"
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

#@help _guest_find1
# @command guest find <key>
# @summary Display terminal: every guest whose tags, own or inherited from its image's template, hold the key, whatever the text -- 'guest find <key> .'
# @group   guest
# @example vm-bake guest find purpose
# @see     guest tag add
# @see     template find
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_find1() {
	_guest_find2 "$1" .
}

#@help _guest_find2
# @command guest find <key> <pattern>
# @summary Display terminal: every guest whose tags, own or inherited from its image's template, hold the key with a text matching the pattern -- an extended regular expression, case-insensitive, searched in the text alone and not in the names around it ('.' for any text, '^8\.0$' for exactly that value): one line per hit, guest, image, origin, the tag -- answered from the records, no guest is started
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
		hit=$( { printf '%s\n' "$own"; awk -v base="$VM_BAKE_BASE" -v family=tag -v chain="empty${chain:+ $chain}" -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk"; } | VM_BAKE_PATTERN=$2 awk -v k="$1" 'BEGIN { p = tolower(ENVIRON["VM_BAKE_PATTERN"]) } $3 == k { t = $0; sub(/^#   [^ ]+ +[^ ]+ +/, "", t); if (tolower(t) ~ p) print }' || true)
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
	paths=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -v '^copy ' | cut -d' ' -f1)
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
	paths=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -v '^copy ' | cut -d' ' -f1)
	users=$(awk -v base="$VM_BAKE_BASE" -v family=user -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	test -n "$paths" && test -n "$users" || { emit_note "guest $1: no home paths or no users in the template, nothing seeded"; return 0; }
	printf '%s\n' "md=\$(mdconfig -a -t vnode -f '$disk') || exit 1"
	printf '%s\n' "mkdir -p '$mnt' && mount -t ufs '/dev/gpt/$img-root' '$mnt' || { mdconfig -d -u \"\${md#md}\"; exit 1; }"
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

#@help ___guest_dowry_place1
# @command guest dowry place <guest>
# @summary Put the dowry the image's template hands out into the guest's view, by its policy: 'guest dowry place idem' for the lines that only fill what is missing, then 'guest dowry place overwrite' for the lines that replace what is there. 'guest start' does it before it hangs the overlays in, so an overlay never hides a destination
# @group   guest
# @example vm-bake guest dowry place dalmatia
# @see     guest start
# @see     template home copy idem
#@end
___guest_dowry_place1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dowry place idem $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest dowry place overwrite $(sq "$1")"
}

#@help _guest_dowry_place_idem1
# @command guest dowry place idem <guest>
# @summary Act terminal (the invoking user, the view and the database are theirs): every 'copy idem' line of the image's template (read at generation time over the chain) placed in the view where its destination is MISSING -- what the guest made of it stays untouched; no such line is a note, a dowry the database does not keep an error
# @group   guest
# @internal
# @see     guest dowry place
# @env     VM_BAKE_VIEW_DIR  the views' directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_dowry_place_idem1() {
	local name="$1" dir="$VM_BAKE_VIEW_DIR" img="" t="" cur="" chain="" p="" n=0 lines="" l="" dw="" dest="" src=""
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep '^copy idem ')
	test -n "$lines" || { emit_note "guest $name: the template $t hands out no dowry to fill in"; return 0; }
	IFS='
'; set -- $lines; IFS='
'
	for l; do
		dw=$(printf '%s' "$l" | cut -d' ' -f3); dest=$(printf '%s' "$l" | cut -d' ' -f4)
		src="$VM_BAKE_BASE/dowry/$dw/object"
		test -e "$src" || { generate_error "guest dowry place idem: the template $t hands out the dowry $dw, which this database does not keep (dowry add $dw <source>, or template home unlink idem $t $dw $dest)"; return 0; }
		printf '%s\n' "test -e '$dir/$name/$dest' || { install -d \"\$(dirname '$dir/$name/$dest')\" && cp -Rp '$src' '$dir/$name/$dest' || exit 1; }"
		printf '%s\n' "printf '# guest %s: dowry %s at %s (idem)\\n' '$name' '$dw' '$dest' >&2"
	done
}

#@help _guest_dowry_place_overwrite1
# @command guest dowry place overwrite <guest>
# @summary Act terminal (the invoking user, the view and the database are theirs): every 'copy overwrite' line of the image's template (read at generation time over the chain) placed in the view, the destination removed first -- whatever the guest wrote there is gone; no such line is a note, a dowry the database does not keep an error
# @group   guest
# @internal
# @see     guest dowry place
# @env     VM_BAKE_VIEW_DIR  the views' directory
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_dowry_place_overwrite1() {
	local name="$1" dir="$VM_BAKE_VIEW_DIR" img="" t="" cur="" chain="" p="" n=0 lines="" l="" dw="" dest="" src=""
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep '^copy overwrite ')
	test -n "$lines" || { emit_note "guest $name: the template $t hands out no dowry to replace"; return 0; }
	IFS='
'; set -- $lines; IFS='
'
	for l; do
		dw=$(printf '%s' "$l" | cut -d' ' -f3); dest=$(printf '%s' "$l" | cut -d' ' -f4)
		src="$VM_BAKE_BASE/dowry/$dw/object"
		test -e "$src" || { generate_error "guest dowry place overwrite: the template $t hands out the dowry $dw, which this database does not keep (dowry add $dw <source>, or template home unlink overwrite $t $dw $dest)"; return 0; }
		printf '%s\n' "install -d \"\$(dirname '$dir/$name/$dest')\" && rm -rf '$dir/$name/$dest' && cp -Rp '$src' '$dir/$name/$dest' || exit 1"
		printf '%s\n' "printf '# guest %s: dowry %s at %s (overwrite)\\n' '$name' '$dw' '$dest' >&2"
	done
}

#@help _guest_view_mount1
# @command guest view mount <guest>
# @summary Act terminal (root): the view is there and every home line of the image's template (read at generation time over the chain, '<path> <mode>') is hung into it as a nullfs overlay, ro or rw as the line says, the directory in the view made first and its parents with it, all owned by the user -- the guest writes beside the overlay, not into it; before the overlays the mount point VM_BAKE_REPO_LOCAL, where the guest hangs the directory of its own disk in; a line already hung in stays, a line from before the modes (a bare path) counts as ro. No view in the template is a note, a path that is no directory on the host an error -- an overlay is a directory
# @group   guest
# @internal
# @see     guest start
# @see     guest view unmount
# @see     template home add
# @env     VM_BAKE_VIEW_DIR  the views' directory
# @env     VM_BAKE_REPO_LOCAL  the clones' directory under the guest's home, its mount point made here
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_guest_view_mount1() {
	local name="$1" dir="$VM_BAKE_VIEW_DIR" home="" img="" t="" cur="" chain="" p="" n=0 lines="" l="" path="" mode="" u="" g="" parents=""
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
	parents=""; p=$VM_BAKE_REPO_LOCAL
	while case "$p" in */*) ;; *) false ;; esac; do p=${p%/*}; parents="'$dir/$name/$p' $parents"; done
	printf '%s\n' "install -d -o $(sq "$u") -g $(sq "$g") -m 755 $parents'$dir/$name/$VM_BAKE_REPO_LOCAL' || exit 1"
	printf '%s\n' "printf '# guest %s: %s in its view, the mount point of its disk\\n' '$name' '$VM_BAKE_REPO_LOCAL' >&2"
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=home -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | grep -v '^copy ' | sort)
	test -n "$lines" || { emit_note "guest $1: the template $t hangs nothing into the view"; return 0; }
	IFS='
'; set -- $lines; IFS='
'
	for l; do
		path=${l%% *}; mode=ro
		case "$l" in *" "*) mode=${l##* } ;; esac
		test -d "$home/$path" || { generate_error "guest view mount: $home/$path is no directory, and an overlay of a view is one"; return 0; }
		parents=""; p=$path
		while case "$p" in */*) ;; *) false ;; esac; do p=${p%/*}; parents="'$dir/$name/$p' $parents"; done
		printf '%s\n' "install -d -o $(sq "$u") -g $(sq "$g") -m 755 $parents'$dir/$name/$path' || exit 1"
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

#@help __guest_check_running1
# @command guest check running <guest>
# @summary The guest is running (vm-bhyve's run.lock is there): a comment line, else an error line -- what reaches into the guest over ssh needs it up
# @group   guest
# @internal
# @see     guest repo add
# @see     guest check stopped
# @env     VM_BAKE_GUEST_DIR  vm-bhyve's vm_dir, where run.lock lies
#@end
__guest_check_running1() {
	if test -e "$VM_BAKE_GUEST_DIR/$1/run.lock"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1 is running")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest $1 is not running (guest start $1 -- it clones what its record lists on its own)")"
	fi
}

#@help __guest_check_fetched1
# @command guest check fetched <guest>
# @summary The guest's clones were fetched after its last start (guest/<guest>/fetched, which 'guest stop' writes once every recorded repository is in the host's refs), or its record lists no repository: a comment line, else an error line -- a guest with commits the host has not taken is not thrown away
# @group   guest
# @internal
# @see     guest drop
# @see     guest repo hold
#@end
__guest_check_fetched1() {
	local d="$VM_BAKE_BASE/guest/$1"
	if test -e "$d/fetched" || ! grep -q . "$d/repo" 2>/dev/null; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1: its repositories are fetched, or none recorded")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest $1: its repositories were not fetched after its last start (guest stop $1 fetches them; a guest stopped by other means: guest start, then guest stop -- or guest drop unfetched $1 to give its commits up)")"
	fi
}

#@help ___guest_repo_add2
# @command guest repo add <guest> <repo>
# @summary Give the guest a clone of one of the invoking user's repositories to commit in: the guest has a record and a view and is running, the path is plain and relative to the home; then the host's bare mirror of it under VM_BAKE_REPO_VIEWS made or refreshed (the template's home line hangs that directory read-only into every view, so the guest pulls from the mirror and can touch nothing of it), the clone made over ssh under VM_BAKE_REPO_LOCAL on the guest's own disk, where git can write its objects -- the view cannot take them, p9fs refuses to create a read-only file for writing -- and only then the repository recorded for the guest: a clone that fails (the view shows no mirror, no home line git/views) leaves no record behind, which 'guest stop' would otherwise try to hold. A second add of the same repository refreshes the mirror and leaves the clone alone
# @group   guest
# @example vm-bake guest repo add dalmatia git/Infrastruktur
# @see     guest repo fetch
# @see     guest repo show
# @see     guest repo drop
# @see     guest repo ensure
#@end
___guest_repo_add2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check view $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check running $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo mirror $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo clone $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo record $(sq "$1") $(sq "$2")"
}

#@help ___guest_repo_fetch2
# @command guest repo fetch <guest> <repo>
# @summary Fetch what the guest committed into the invoking user's own repository: the guest has a record and is running, the path is plain; then its branches fetched over ssh from the clone on the guest's disk into refs/remotes/<guest>/* of the host's repository, where 'git log <guest>/<branch>' reads them and 'git merge --ff-only <guest>/<branch>' takes them over -- the host signs, the guest never does; the batch ends in a comment that names both commands for the branch the host's repository has checked out (read at generation time), the continuation at hand
# @group   guest
# @example vm-bake guest repo fetch dalmatia git/Infrastruktur
# @see     guest repo add
# @see     guest repo hold
# @see     guest repo show
#@end
___guest_repo_fetch2() {
	local home="" branch=""
	eval "home=~$(id -un)"
	branch=$(HOME=$home git -C "$home/$2" symbolic-ref --short HEAD 2>/dev/null || printf main)
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check running $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo refs $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "repository $2: to take the guest's commits over, in your repository: git -C $home/$2 log --oneline $branch..$1/$branch && git -C $home/$2 merge --ff-only $1/$branch")"
}

#@help ___guest_repo_pull2
# @command guest repo pull <guest> <repo>
# @summary Fetch and take over in one go: the fetch of 'guest repo fetch', then 'guest repo merge' fast-forwards the branch your repository has checked out onto the guest's -- what the fetch's closing comment asks you to paste, done by the tool
# @group   guest
# @example vm-bake guest repo pull dalmatia git/Infrastruktur
# @see     guest repo fetch
# @see     guest repo merge
# @see     guest repo hold
#@end
___guest_repo_pull2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check running $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo refs $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo merge $(sq "$1") $(sq "$2")"
}

#@help ___guest_repo_drop2
# @command guest repo drop <guest> <repo>
# @summary Take the repository from the guest: it has a record and is running, the path is plain; then the clone removed from the guest's disk over ssh and the line taken from its record -- what the guest committed and the host has not fetched is gone with it. The mirror under VM_BAKE_REPO_VIEWS stays, the other guests read it
# @group   guest
# @example vm-bake guest repo drop dalmatia git/Infrastruktur
# @see     guest repo add
# @see     guest repo fetch
#@end
___guest_repo_drop2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check running $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo valid $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo remove $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo unrecord $(sq "$1") $(sq "$2")"
}

#@help ___guest_repo_ensure1
# @command guest repo ensure <guest>
# @summary Every repository recorded for the guest has its clone on the guest's disk: the guest has a record; then, when the record lists any (read at generation time), 'guest repo wait' for its sshd and 'guest repo clone' for each -- a clone already there is left alone. 'guest start' ends with it, so a guest on a fresh image gets its clones back; a record without repositories is a comment
# @group   guest
# @example vm-bake guest repo ensure dalmatia
# @see     guest start
# @see     guest repo add
#@end
___guest_repo_ensure1() {
	local f="$VM_BAKE_BASE/guest/$1/repo" l=""
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	grep -q . "$f" 2>/dev/null || { printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1: no repositories recorded (guest repo add)")"; return 0; }
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo wait $(sq "$1")"
	while IFS= read -r l; do
		test -n "$l" || continue
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo clone $(sq "$1") $(sq "$l")"
	done < "$f"
}

#@help ___guest_repo_hold1
# @command guest repo hold <guest>
# @summary Hold what the guest committed before it goes: the guest has a record; then, when it is running (vm-bhyve's run.lock, read at generation time), 'guest repo refs' for every recorded repository and 'guest fetched write' once all are in. 'guest stop' does it first, so 'guest drop' can trust the mark; a guest that is not running cannot be read and gets a comment, no mark
# @group   guest
# @example vm-bake guest repo hold dalmatia
# @see     guest stop
# @see     guest check fetched
# @env     VM_BAKE_GUEST_DIR  vm-bhyve's vm_dir, where run.lock lies
#@end
___guest_repo_hold1() {
	local f="$VM_BAKE_BASE/guest/$1/repo" l=""
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	test -e "$VM_BAKE_GUEST_DIR/$1/run.lock" || { printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1 is not running, nothing to hold (its clones are unread until the next guest start and guest stop)")"; return 0; }
	test -f "$f" && while IFS= read -r l; do
		test -n "$l" || continue
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo refs $(sq "$1") $(sq "$l")"
	done < "$f"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest fetched write $(sq "$1")"
}

#@help _guest_repo_tree_ensure0
# @command guest repo tree ensure
# @summary Act terminal (the invoking user, in their own home): the mirrors' directory VM_BAKE_REPO_VIEWS made when it is missing, mode 755 -- the one home path of a template that the tool owns, so 'guest check homes' finds it without a hand making it; a step of 'guest make' and of 'guest start', before that check
# @group   guest
# @internal
# @example vm-bake guest repo tree ensure
# @see     guest make
# @see     guest start
# @see     guest check homes
# @see     guest repo mirror
# @env     VM_BAKE_REPO_VIEWS  the mirrors' directory under the home, the same path on the host and in the view
#@end
_guest_repo_tree_ensure0() {
	local home="" views="$VM_BAKE_REPO_VIEWS"
	eval "home=~$(id -un)"
	printf '%s\n' "test -d '$home/$views' || install -d -m 755 '$home/$views' || exit 1"
	printf '%s\n' "printf '# mirrors: %s\\n' '$home/$views' >&2"
}

#@help _guest_repo_mirror1
# @command guest repo mirror <repo>
# @summary Act terminal (the invoking user, in their own home): the bare mirror VM_BAKE_REPO_VIEWS/<name> of the repository (<name> its last path element) -- cloned with --mirror and without hardlinks when it is not there, its refs fetched with --prune when it is; a mirror of that name made from another repository is an error. VM_BAKE_REPO_VIEWS is there already ('guest repo tree ensure', a step of every 'guest make' and 'guest start'); the template's home line for it hangs the directory read-only into the views, so a guest reads the mirrors and writes none of them
# @group   guest
# @internal
# @see     guest repo add
# @env     VM_BAKE_REPO_VIEWS  the mirrors' directory under the home, the same path on the host and in the view
#@end
_guest_repo_mirror1() {
	local home="" name="${1##*/}" views="$VM_BAKE_REPO_VIEWS"
	eval "home=~$(id -un)"
	printf '%s\n' "test -d '$home/$1/.git' || { printf '# Error: %s is no repository of the host\\n' '$home/$1' >&2; exit 1; }"
	printf '%s\n' "if test -d '$home/$views/$name'; then test \"\$(git -C '$home/$views/$name' config --get remote.origin.url)\" = '$home/$1' || { printf '# Error: the mirror %s is of %s, not of %s\\n' '$home/$views/$name' \"\$(git -C '$home/$views/$name' config --get remote.origin.url)\" '$home/$1' >&2; exit 1; }; git -C '$home/$views/$name' fetch --prune origin || exit 1; else git clone --mirror --no-hardlinks '$home/$1' '$home/$views/$name' || exit 1; fi"
	printf '%s\n' "printf '# repository %s: mirror %s\\n' '$1' '$home/$views/$name' >&2"
}

#@help _guest_repo_record2
# @command guest repo record <guest> <repo>
# @summary Act terminal: the repository's path appended to guest/<guest>/repo unless listed (0600) -- what 'guest repo ensure' clones and 'guest repo hold' fetches; the dump replays it
# @group   guest
# @internal
# @see     guest repo add
# @see     guest dump record
#@end
_guest_repo_record2() {
	local f="$VM_BAKE_BASE/guest/$1/repo"
	printf '%s\n' "grep -qxF $(sq "$2") '$f' 2>/dev/null || printf '%s\\n' $(sq "$2") >> '$f'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$f'"
	printf '%s\n' "printf '# guest %s: repo + %s\\n' '$1' $(sq "$2") >&2"
}

#@help _guest_repo_unrecord2
# @command guest repo unrecord <guest> <repo>
# @summary Act terminal: the repository's path removed from guest/<guest>/repo
# @group   guest
# @internal
# @see     guest repo drop
#@end
_guest_repo_unrecord2() {
	local f="$VM_BAKE_BASE/guest/$1/repo"
	printf '%s\n' "{ grep -vxF $(sq "$2") '$f' > '$f.new' || true; } && mv -f '$f.new' '$f'"
	printf '%s\n' "$MODIFY_FILE_PERMS 0600 '$f'"
	printf '%s\n' "printf '# guest %s: repo - %s\\n' '$1' $(sq "$2") >&2"
}

#@help _guest_repo_wait1
# @command guest repo wait <guest>
# @summary Act terminal: wait until the guest answers ssh (BatchMode, ConnectTimeout 3, two seconds between tries, 90 tries; the host key accepted into .tmp/known_hosts.<guest>) -- 'guest repo ensure' runs right after vm start
# @group   guest
# @internal
# @see     guest repo ensure
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the guest's sshd port
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest's name lives in
#@end
_guest_repo_wait1() {
	local key="$VM_BAKE_HOST_KEY"
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	printf '%s\n' "n=0; until ssh -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$1' -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 -o BatchMode=yes '$(id -un)@$1.$VM_BAKE_GUEST_DOMAIN' true 2>/dev/null; do n=\$((n + 1)); test \"\$n\" -lt 90 || { printf '# Error: guest %s does not answer ssh\\n' '$1' >&2; exit 1; }; sleep 2; done"
	printf '%s\n' "printf '# guest %s answers ssh after %s tries\\n' '$1' \"\$n\" >&2"
}

#@help _guest_repo_clone2
# @command guest repo clone <guest> <repo>
# @summary Act terminal (the invoking user, over ssh into the guest): the clone VM_BAKE_REPO_LOCAL/<name> made on the guest's disk from the mirror VM_BAKE_REPO_VIEWS/<name> the view shows, with the host's git identity as it holds in the host's repository (user.name, user.email -- read there at generation time with the home set, since the tool runs without one; global or of that repository, when the host has them) so the guest commits in the host's name, unsigned; the identity is set on a clone that is there already there is left alone
# @group   guest
# @internal
# @see     guest repo add
# @see     guest repo ensure
# @env     VM_BAKE_REPO_VIEWS  the mirrors' directory under the home
# @env     VM_BAKE_REPO_LOCAL  the clones' directory under the guest's home, on its disk
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the guest's sshd port
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest's name lives in
#@end
_guest_repo_clone2() {
	local key="$VM_BAKE_HOST_KEY" name="${2##*/}" views="$VM_BAKE_REPO_VIEWS" loc="$VM_BAKE_REPO_LOCAL" home="" uname="" uemail="" cfg="" remote=""
	eval "home=~$(id -un)"
	case "$key" in "~/"*) key="$home${key#\~}" ;; esac
	uname=$(HOME=$home git -C "$home/$2" config --get user.name 2>/dev/null || true)
	uemail=$(HOME=$home git -C "$home/$2" config --get user.email 2>/dev/null || true)
	test -z "$uname" || cfg="git -C '$loc/$name' config user.name $(sq "$uname") && "
	test -z "$uemail" || cfg="${cfg}git -C '$loc/$name' config user.email $(sq "$uemail") && "
	test -z "$cfg" || cfg="; ${cfg}printf '# guest %s: %s commits as %s\\n' '$1' '$loc/$name' $(sq "${uname:-?} <${uemail:-?}>") >&2 || exit 1"
	remote="if test -e '$loc/$name'; then printf '# guest %s: %s is there already\\n' '$1' '$loc/$name' >&2; else git clone \"\$HOME/$views/$name\" '$loc/$name' && printf '# guest %s: clone of %s at %s\\n' '$1' '$2' '$loc/$name' >&2 || exit 1; fi$cfg"
	printf '%s\n' "ssh -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$1' -o StrictHostKeyChecking=accept-new -o BatchMode=yes '$(id -un)@$1.$VM_BAKE_GUEST_DOMAIN' $(sq "$remote") || exit 1"
}

#@help _guest_repo_refs2
# @command guest repo refs <guest> <repo>
# @summary Act terminal (the invoking user, in their OWN repository): 'git fetch' over ssh from the clone on the guest's disk into refs/remotes/<guest>/*, no tags -- the host reads the guest's commits without ever running git inside the guest's clone, whose configuration and hooks belong to the guest
# @group   guest
# @internal
# @see     guest repo fetch
# @see     guest repo hold
# @env     VM_BAKE_REPO_LOCAL  the clones' directory under the guest's home
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the guest's sshd port
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest's name lives in
#@end
_guest_repo_refs2() {
	local key="$VM_BAKE_HOST_KEY" home="" name="${2##*/}" loc="$VM_BAKE_REPO_LOCAL"
	eval "home=~$(id -un)"
	case "$key" in "~/"*) key="$home${key#\~}" ;; esac
	printf '%s\n' "test -d '$home/$2/.git' || { printf '# Error: %s is no repository of the host\\n' '$home/$2' >&2; exit 1; }"
	printf '%s\n' "git -C '$home/$2' -c core.sshCommand=$(sq "ssh -i ${key%.pub} -o UserKnownHostsFile=$VM_BAKE_BASE/.tmp/known_hosts.$1 -o StrictHostKeyChecking=accept-new -o BatchMode=yes") fetch --no-tags --prune 'ssh://$(id -un)@$1.$VM_BAKE_GUEST_DOMAIN:$VM_BAKE_SSH_PORT/~/$loc/$name' '+refs/heads/*:refs/remotes/$1/*' || exit 1"
	printf '%s\n' "printf '# guest %s: its branches are %s/* in %s now\\n' '$1' '$1' '$home/$2' >&2"
}

#@help _guest_repo_merge2
# @command guest repo merge <guest> <repo>
# @summary Act terminal (the invoking user, in their OWN repository): the branch checked out there fast-forwarded onto the guest's fetched branch refs/remotes/<guest>/<branch>, the commits listed first -- no merge commit, no signature asked for; a branch that diverged stops with an error and leaves the repository as it was
# @group   guest
# @internal
# @see     guest repo pull
# @see     guest repo fetch
# @see     guest repo refs
#@end
_guest_repo_merge2() {
	local home="" branch=""
	eval "home=~$(id -un)"
	branch=$(HOME=$home git -C "$home/$2" symbolic-ref --short HEAD 2>/dev/null || printf main)
	printf '%s\n' "test -d '$home/$2/.git' || { printf '# Error: %s is no repository of the host\\n' '$home/$2' >&2; exit 1; }"
	printf '%s\n' "git -C '$home/$2' rev-parse --verify -q '$1/$branch' >/dev/null || { printf '# Error: %s has no branch %s of guest %s (guest repo fetch first)\\n' '$home/$2' '$branch' '$1' >&2; exit 1; }"
	printf '%s\n' "git -C '$home/$2' log --oneline '$branch..$1/$branch' | sed 's/^/# /' >&2"
	printf '%s\n' "git -C '$home/$2' merge --ff-only '$1/$branch' >&2 || { printf '# Error: %s: %s does not fast-forward onto %s/%s (the host has commits of its own there; merge by hand)\\n' '$home/$2' '$branch' '$1' '$branch' >&2; exit 1; }"
	printf '%s\n' "printf '# guest %s: %s of %s is %s/%s now\\n' '$1' '$branch' '$home/$2' '$1' '$branch' >&2"
}

#@help _guest_repo_remove2
# @command guest repo remove <guest> <repo>
# @summary Act terminal (the invoking user, over ssh into the guest): the clone VM_BAKE_REPO_LOCAL/<name> removed from the guest's disk
# @group   guest
# @internal
# @see     guest repo drop
# @env     VM_BAKE_REPO_LOCAL  the clones' directory under the guest's home
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the guest's sshd port
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest's name lives in
#@end
_guest_repo_remove2() {
	local key="$VM_BAKE_HOST_KEY" name="${2##*/}" loc="$VM_BAKE_REPO_LOCAL" remote=""
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	remote="test -d '$loc/$name/.git' || { printf '# Error: no clone %s on the disk of %s\\n' '$loc/$name' '$1' >&2; exit 1; }; rm -rf '$loc/$name' && printf '# guest %s: clone %s removed from its disk\\n' '$1' '$loc/$name' >&2"
	printf '%s\n' "ssh -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$1' -o StrictHostKeyChecking=accept-new -o BatchMode=yes '$(id -un)@$1.$VM_BAKE_GUEST_DOMAIN' $(sq "$remote") || exit 1"
}

#@help _guest_repo_show1
# @command guest repo show <guest>
# @summary Act terminal (the invoking user, over ssh into the guest): the repositories recorded for the guest, one line each, then the clones on its disk under VM_BAKE_REPO_LOCAL with the branch their HEAD names (the file read, no git run in the guest's clone)
# @group   guest
# @example vm-bake guest repo show dalmatia
# @see     guest repo add
# @see     guest repo fetch
# @env     VM_BAKE_REPO_LOCAL  the clones' directory under the guest's home
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the guest's sshd port
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest's name lives in
#@end
_guest_repo_show1() {
	local key="$VM_BAKE_HOST_KEY" loc="$VM_BAKE_REPO_LOCAL" f="$VM_BAKE_BASE/guest/$1/repo" l="" n=0 remote=""
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	emit_note "repositories of $1 (record)"
	test -f "$f" && while IFS= read -r l; do
		test -n "$l" || continue
		emit_note "  $l"
		n=$((n + 1))
	done < "$f"
	test "$n" -gt 0 || emit_note "  (none)"
	emit_note "clones on the disk of $1 under $loc (name  branch)"
	remote='n=0; for h in '"$loc"'/*/.git/HEAD; do test -f "$h" || continue; d=${h%/.git/HEAD}; b=$(cat "$h"); printf "#   %-40s %s\n" "${d##*/}" "${b#ref: refs/heads/}" >&2; n=$((n + 1)); done; test "$n" -gt 0 || printf "#   (none)\n" >&2'
	printf '%s\n' "ssh -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$1' -o StrictHostKeyChecking=accept-new -o BatchMode=yes '$(id -un)@$1.$VM_BAKE_GUEST_DOMAIN' $(sq "$remote") || exit 1"
}

#@help _guest_fetched_write1
# @command guest fetched write <guest>
# @summary Act terminal: guest/<guest>/fetched written with the date (0600) -- the mark 'guest check fetched' reads; 'guest repo hold' writes it, 'guest start' drops it
# @group   guest
# @internal
# @see     guest repo hold
# @see     guest check fetched
#@end
_guest_fetched_write1() {
	local f="$VM_BAKE_BASE/guest/$1/fetched"
	printf '%s\n' "date -u '+%Y-%m-%dT%H:%M:%SZ' > '$f' && $MODIFY_FILE_PERMS 0600 '$f' || exit 1"
	printf '%s\n' "printf '# guest %s: repositories fetched, the mark written\\n' '$1' >&2"
}

#@help _guest_fetched_drop1
# @command guest fetched drop <guest>
# @summary Act terminal: guest/<guest>/fetched removed -- the guest is about to run and commit again
# @group   guest
# @internal
# @see     guest start
# @see     guest check fetched
#@end
_guest_fetched_drop1() {
	printf '%s\n' "rm -f '$VM_BAKE_BASE/guest/$1/fetched'"
	printf '%s\n' "printf '# guest %s: the fetched mark dropped\\n' '$1' >&2"
}

#@help ___guest_hostkey_ensure1
# @command guest hostkey ensure <guest>
# @summary The guest carries an ssh host key: its record names one that is kept -- a comment; it names one that is gone -- an error; it names none and a key of the guest's own name is kept -- that one taken; neither -- a key of the guest's name made and taken. The key is a resource of the database and outlives the guest, so the host's known_hosts stays right across every rebuild; another key is handed over with 'guest hostkey use'
# @group   guest
# @internal
# @see     guest make
# @see     guest hostkey use
# @see     hostkey create
#@end
___guest_hostkey_ensure1() {
	local k=""
	IFS= read -r k 2>/dev/null < "$VM_BAKE_BASE/guest/$1/hostkey" || k=""
	if test -n "$k" && test -e "$VM_BAKE_BASE/hostkey/$k/key"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1 carries the hostkey $k")"
		return 0
	fi
	if test -n "$k"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest $1: its record names the hostkey $k, which is not kept (hostkey list; hostkey add $k <path>, or guest hostkey use $1 <hostkey>)")"
		return 0
	fi
	test -e "$VM_BAKE_BASE/hostkey/$1/key" || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey create $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest hostkey use $(sq "$1") $(sq "$1")"
}

#@help ___guest_hostkey_use2
# @command guest hostkey use <guest> <hostkey>
# @summary Hand an ssh host key of the database to a guest: the guest has a record, the key is kept, and no other guest carries it (a key answers for one guest only); then the binding written into the guest record. The key reaches the guest's /etc/ssh at the next 'guest make' -- a guest that is already built has to be built again to answer with it
# @group   guest
# @example vm-bake guest hostkey use dalmatia dalmatia
# @see     guest hostkey drop
# @see     hostkey create
# @see     hostkey list
#@end
___guest_hostkey_use2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" hostkey check $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest hostkey unique $(sq "$1") $(sq "$2")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest hostkey bind $(sq "$1") $(sq "$2")"
}

#@help ___guest_hostkey_drop1
# @command guest hostkey drop <guest>
# @summary Let go of the ssh host key of a guest: it has a record; then the binding removed from it. The key itself stays in the database and is free for another guest -- 'hostkey drop' throws it out
# @group   guest
# @example vm-bake guest hostkey drop dalmatia
# @see     guest hostkey use
# @see     hostkey drop
#@end
___guest_hostkey_drop1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest hostkey unbind $(sq "$1")"
}

#@help __guest_hostkey_unique2
# @command guest hostkey unique <guest> <hostkey>
# @summary No guest other than this one carries that ssh host key (every guest record read at generation time): a comment line, else an error line naming the guest that has it -- two guests with one identity would make every known_hosts lie about one of them
# @group   guest
# @internal
# @see     guest hostkey use
#@end
__guest_hostkey_unique2() {
	local d="" k="" who="" g=""
	for d in "$VM_BAKE_BASE"/guest/*/; do
		g=$(basename "$d")
		test "$g" != "$1" || continue
		test -f "$d/hostkey" || continue
		IFS= read -r k < "$d/hostkey"
		test "$k" = "$2" || continue
		who="${who:+$who }$g"
	done
	if test -z "$who"; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "hostkey $2 is free for $1")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "hostkey $2 is carried by $who (guest hostkey drop $who, or hostkey create <name> for $1)")"
	fi
}

#@help _guest_hostkey_bind2
# @command guest hostkey bind <guest> <hostkey>
# @summary Act terminal: the name of the ssh host key written into the guest record (guest/<guest>/hostkey, 0600) -- the binding, which 'guest hostkey write' reads
# @group   guest
# @internal
# @see     guest hostkey use
#@end
_guest_hostkey_bind2() {
	local rec="$VM_BAKE_BASE/guest/$1"
	printf '%s\n' "printf '%s\\n' $(sq "$2") > '$rec/hostkey' && $MODIFY_FILE_PERMS 0600 '$rec/hostkey' || exit 1"
	printf '%s\n' "printf '# guest %s: carries the hostkey %s (%s)\\n' '$1' $(sq "$2") \"\$(ssh-keygen -l -f '$VM_BAKE_BASE/hostkey/$2/key.pub' | cut -d' ' -f2)\" >&2"
}

#@help _guest_hostkey_unbind1
# @command guest hostkey unbind <guest>
# @summary Act terminal: the binding removed from the guest record (guest/<guest>/hostkey); the key stays in the database
# @group   guest
# @internal
# @see     guest hostkey drop
#@end
_guest_hostkey_unbind1() {
	printf '%s\n' "$MODIFY_FILE_REMOVE '$VM_BAKE_BASE/guest/$1/hostkey'"
	emit_note "guest $1: the hostkey binding removed, the key stays in the database"
}

#@help _guest_hostkey_write1
# @command guest hostkey write <guest>
# @summary Act terminal (root): the clone's disk0.img attached as md, its root mounted by the image's label, the ssh host key the guest carries (the binding of its record, read at generation time) written to /etc/ssh/ssh_host_ed25519_key (root, 0600; the public half 0644), unmounted and detached -- sshd in the guest uses it from the first boot, the other key types it makes itself
# @group   guest
# @internal
# @see     guest make
# @see     guest hostkey ensure
# @env     VM_BAKE_GUEST_DIR  the guests' directory
#@end
_guest_hostkey_write1() {
	local img="" hk="" k="" disk="$VM_BAKE_GUEST_DIR/$1/disk0.img" mnt="$VM_BAKE_GUEST_DIR/$1/mnt"
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r hk 2>/dev/null < "$VM_BAKE_BASE/guest/$1/hostkey" || hk=""
	test -n "$hk" || { generate_error "guest hostkey write: the guest $1 carries no ssh host key (guest hostkey use $1 <hostkey>)"; return 0; }
	k="$VM_BAKE_BASE/hostkey/$hk/key"
	test -f "$k" || { generate_error "guest hostkey write: the guest $1 carries the hostkey $hk, which is not kept (hostkey list)"; return 0; }
	printf '%s\n' "md=\$(mdconfig -a -t vnode -f '$disk') || exit 1"
	printf '%s\n' "mkdir -p '$mnt' && mount -t ufs '/dev/gpt/$img-root' '$mnt' || { mdconfig -d -u \"\${md#md}\"; exit 1; }"
	printf '%s\n' "install -m 600 -o root -g wheel '$k' '$mnt/etc/ssh/ssh_host_ed25519_key' && install -m 644 -o root -g wheel '$k.pub' '$mnt/etc/ssh/ssh_host_ed25519_key.pub' || { umount '$mnt'; mdconfig -d -u \"\${md#md}\"; exit 1; }"
	printf '%s\n' "umount '$mnt' && rmdir '$mnt' && mdconfig -d -u \"\${md#md}\" || exit 1"
	printf '%s\n' "printf '# guest %s: the hostkey %s installed\\n' '$1' $(sq "$hk") >&2"
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

#@help _guest_install2
# @command guest install <guest> <iso>
# @summary Act terminal (root): vm install <guest> <iso> -- vm-bhyve runs the guest with the ISO as a CD for this one run; when the guest reboots, vm-bhyve starts it again without the ISO, and a UEFI guest comes up from its disk
# @group   guest
# @internal
# @completion iso files
# @see     image install
# @see     guest run
#@end
_guest_install2() {
	printf '%s\n' "vm install $(sq "$1") $(sq "$2") || exit 1"
	printf '%s\n' "printf '# guest %s started from %s\\n' $(sq "$1") $(sq "$2") >&2"
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
# @summary Everything the records say about one guest, as comment lines: its own record (image, address, created, the name and fingerprint of the ssh host key it carries), the template behind its image with the resolved chain and resources, whether it has a view and where, and every list family resolved over the chain with its origin -- the SOLL of this guest, against which it can be checked from inside. 'guest report' is the same text, written into the guest's view
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
	local d="$VM_BAKE_BASE/guest/$1" img="" t="" cur="" chain="" p="" n=0 a="" res="" f="" dir="$VM_BAKE_VIEW_DIR" view=no addr=- created=- key=- hk=-
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	IFS= read -r img 2>/dev/null < "$d/image" || img=-
	IFS= read -r addr 2>/dev/null < "$d/address" || addr=-
	IFS= read -r created 2>/dev/null < "$d/created" || created=-
	IFS= read -r hk 2>/dev/null < "$d/hostkey" || hk=-
	test ! -f "$VM_BAKE_BASE/hostkey/$hk/key.pub" || key=$(ssh-keygen -l -f "$VM_BAKE_BASE/hostkey/$hk/key.pub" 2>/dev/null | cut -d' ' -f2)
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
	printf '#   hostkey   %s (%s)\n#   created   %s\n' "$hk" "$key" "$created"
	printf '#   view      %s\n' "$(test "$view" = no && printf 'none (the home lies on the disk of the guest)' || printf '%s on the host, mounted as the home over p9fs (slot %s, share home)' "$dir/$1" "$VM_BAKE_VIEW_SLOT")"
	for f in $TEMPLATE_FAMILIES; do
		printf '# %s (origin  entry)\n' "$f"
		awk -v base="$VM_BAKE_BASE" -v family="$f" -v chain="empty${chain:+ $chain}" -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk"
	done
}

#@help ___guest_report1
# @command guest report <guest>
# @summary Write what 'guest show' says into the guest's own view, as .vm-bake/GUEST.txt beside the records it reads, so the guest can hold its SOLL against what it finds: the guest has a record; then the text rendered into .tmp/report.<guest> of the database and put in place by 'guest report place'. A guest without a view has nowhere to put it and gets a comment
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
	test "$view" = no || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest show $(sq "$1") > $(sq "$VM_BAKE_BASE/.tmp/report.$1")" "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest report place $(sq "$1")"
	test "$view" = yes || printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1: no view in the template $t, nowhere to put a report")"
}

#@help _guest_report_place1
# @command guest report place <guest>
# @summary Act terminal (the invoking user, the view is theirs): .vm-bake made in the view where it is missing, the rendered .tmp/report.<guest> moved there as GUEST.txt (0644) and the lines counted; nothing rendered is an error
# @group   guest
# @internal
# @see     guest report
# @env     VM_BAKE_VIEW_DIR  the views' directory
#@end
_guest_report_place1() {
	local dir="$VM_BAKE_VIEW_DIR" f=""
	case "$dir" in "~/"*) eval "dir=~$(id -un)${dir#\~}" ;; esac
	f="$dir/$1/.vm-bake/GUEST.txt" tmp="$VM_BAKE_BASE/.tmp/report.$1"
	printf '%s\n' "test -s '$tmp' || { printf '# Error: no report rendered (%s)\\n' '$tmp' >&2; exit 1; }"
	printf '%s\n' "test -d '${f%/*}' || install -d -m 755 '${f%/*}' || exit 1"
	printf '%s\n' "chmod 0644 '$tmp' && mv -f '$tmp' '$f' || exit 1"
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
	test -f "$d/repo" && while IFS= read -r l; do
		test -n "$l" || continue
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest repo record $(sq "$1") $(sq "$l")"
	done < "$d/repo"
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


#@help _guest_seed_write_cloud_init1
# @command guest seed write cloud-init <guest>
# @summary Act terminal: the guest's NoCloud seed VM_BAKE_GUEST_DIR/<guest>/seed.iso (makefs cd9660, label cidata) -- meta-data with instance-id and local-hostname <guest>; network-config (version 2) with the guest's address from its record on the interface of the MAC 'guest conf write' gives it (58:9c:fc and the last three octets of the address), gateway and resolver VM_BAKE_GUEST_GATEWAY; user-data with no users of its own (users: [] keeps cloud-init from creating the distribution's default user; the bake's users and keys are on the disk) and the ssh host key the guest carries (the binding of its record, read at generation time; the key file is read when the act runs, never emitted) -- a new instance-id makes cloud-init apply hostname, network and host key at the guest's first start. 'guest conf write' hangs the seed on the guest as disk1
# @group   guest
# @internal
# @see     guest disk write
# @see     guest conf write
# @see     guest hostkey write
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_GUEST_GATEWAY  the host's address on the bridge: gateway and resolver of the guests
#@end
_guest_seed_write_cloud_init1() {
	local dir="$VM_BAKE_GUEST_DIR/$1" addr="" mac="" hk="" k=""
	IFS= read -r addr 2>/dev/null < "$VM_BAKE_BASE/guest/$1/address" || addr=""
	IFS= read -r hk 2>/dev/null < "$VM_BAKE_BASE/guest/$1/hostkey" || hk=""
	test -n "$hk" || { generate_error "guest seed write: the guest $1 carries no ssh host key (guest hostkey use $1 <hostkey>)"; return 0; }
	k="$VM_BAKE_BASE/hostkey/$hk/key"
	test -f "$k" || { generate_error "guest seed write: the guest $1 carries the hostkey $hk, which is not kept (hostkey list)"; return 0; }
	mac=$(printf '%s' "${addr%/*}" | awk -F. '{ printf "58:9c:fc:%02x:%02x:%02x", $2, $3, $4 }')
	printf '%s\n' "install -d -m 700 '$dir/seed' || exit 1"
	printf '%s\n' "cat > '$dir/seed/meta-data' <<'EOF_META'"
	printf '%s\n' "instance-id: $1" "local-hostname: $1"
	printf '%s\n' "EOF_META"
	printf '%s\n' "cat > '$dir/seed/network-config' <<'EOF_NET'"
	printf '%s\n' "version: 2" "ethernets:" "  net0:" "    match:" "      macaddress: '$mac'" "    set-name: net0" "    dhcp4: false" "    addresses:" "      - $addr" "    routes:" "      - to: default" "        via: $VM_BAKE_GUEST_GATEWAY" "    nameservers:" "      addresses:" "        - $VM_BAKE_GUEST_GATEWAY"
	printf '%s\n' "EOF_NET"
	printf '%s\n' "cat > '$dir/seed/user-data' <<'EOF_USER'"
	printf '%s\n' "#cloud-config" "users: []" "ssh_keys:" "  ed25519_private: |"
	printf '%s\n' "EOF_USER"
	printf '%s\n' "{ sed 's/^/    /' '$k'; printf '  ed25519_public: '; cat '$k.pub'; } >> '$dir/seed/user-data' || exit 1"
	printf '%s\n' "chmod 600 '$dir/seed/user-data' && rm -f '$dir/seed.iso' && makefs -t cd9660 -o rockridge -o label=cidata '$dir/seed.iso' '$dir/seed' && chmod 600 '$dir/seed.iso' || exit 1"
	printf '%s\n' "printf '# guest %s: seed.iso -- %s on %s, gateway %s, hostkey %s\\n' '$1' '$addr' '$mac' '$VM_BAKE_GUEST_GATEWAY' $(sq "$hk") >&2"
}

#@help _guest_seed_write_autoinstall1
# @command guest seed write autoinstall <guest>
# @summary Act terminal: the guest's seed VM_BAKE_GUEST_DIR/<guest>/seed.iso for an OpenBSD image (makefs cd9660, label vmbakeseed) -- the marker vm-bake-seed, myname <guest>.VM_BAKE_GUEST_DOMAIN, address and netmask from the guest's record, mygate and resolv.conf from VM_BAKE_GUEST_GATEWAY, and the ssh host key the guest carries (the binding of its record, read at generation time; the key files are copied when the act runs, never emitted). The image's /etc/hostname.vio0 runs /usr/local/libexec/vm-bake-seed (image site write), which applies the seed at every boot before sshd starts. 'guest conf write' hangs the seed on the guest as disk1
# @group   guest
# @internal
# @see     guest disk write
# @see     guest conf write
# @see     image site write
# @env     VM_BAKE_GUEST_DIR  the guests' directory
# @env     VM_BAKE_GUEST_GATEWAY  the host's address on the bridge: gateway and resolver of the guests
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest names live in
#@end
_guest_seed_write_autoinstall1() {
	local dir="$VM_BAKE_GUEST_DIR/$1" addr="" mask="" hk="" k=""
	IFS= read -r addr 2>/dev/null < "$VM_BAKE_BASE/guest/$1/address" || addr=""
	IFS= read -r hk 2>/dev/null < "$VM_BAKE_BASE/guest/$1/hostkey" || hk=""
	test -n "$hk" || { generate_error "guest seed write: the guest $1 carries no ssh host key (guest hostkey use $1 <hostkey>)"; return 0; }
	k="$VM_BAKE_BASE/hostkey/$hk/key"
	test -f "$k" || { generate_error "guest seed write: the guest $1 carries the hostkey $hk, which is not kept (hostkey list)"; return 0; }
	mask=$(printf '%s\n' "${addr#*/}" | awk '{ m = $1 ? 4294967296 - 2 ^ (32 - $1) : 0; printf "%d.%d.%d.%d", int(m / 16777216) % 256, int(m / 65536) % 256, int(m / 256) % 256, m % 256 }')
	printf '%s\n' "install -d -m 700 '$dir/seed' && : > '$dir/seed/vm-bake-seed' || exit 1"
	printf '%s\n' "printf '%s\\n' '$1.$VM_BAKE_GUEST_DOMAIN' > '$dir/seed/myname'"
	printf '%s\n' "printf '%s\\n' '${addr%/*}' > '$dir/seed/address'"
	printf '%s\n' "printf '%s\\n' '$mask' > '$dir/seed/netmask'"
	printf '%s\n' "printf '%s\\n' '$VM_BAKE_GUEST_GATEWAY' > '$dir/seed/mygate'"
	printf '%s\n' "printf '%s\\n' 'search $VM_BAKE_GUEST_DOMAIN' 'nameserver $VM_BAKE_GUEST_GATEWAY' 'lookup file bind' > '$dir/seed/resolv.conf'"
	printf '%s\n' "cp '$k' '$dir/seed/ssh_host_ed25519_key' && cp '$k.pub' '$dir/seed/ssh_host_ed25519_key.pub' && chmod 600 '$dir/seed/ssh_host_ed25519_key' || exit 1"
	printf '%s\n' "rm -f '$dir/seed.iso' && makefs -t cd9660 -o rockridge -o label=vmbakeseed '$dir/seed.iso' '$dir/seed' && chmod 600 '$dir/seed.iso' || exit 1"
	printf '%s\n' "printf '# guest %s: seed.iso -- %s netmask %s, gateway %s, hostkey %s\\n' '$1' '${addr%/*}' '$mask' '$VM_BAKE_GUEST_GATEWAY' $(sq "$hk") >&2"
}

#@help __guest_disk_write1
# @command guest disk write <guest>
# @summary What the host writes into a new guest before its first start, by the bake of its image's template (read at generation time; no bake record is chroot): rewrite to 'guest disk write chroot <guest>' (the FreeBSD disk mounted: network, home paths, host key), 'guest disk write cloud-init <guest>' or 'guest disk write autoinstall <guest>' (never mounted on the host: a seed of its own with network, hostname and host key; the home paths stay with the view)
# @group   guest
# @internal
# @see     guest make
# @see     guest disk write chroot
# @see     guest seed write cloud-init
# @see     guest seed write autoinstall
#@end
__guest_disk_write1() {
	local img="" t="" cur="" chain="" p="" n=0 a="" bake=""
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	for a in $chain; do test -f "$VM_BAKE_BASE/template/$a/bake" && IFS= read -r bake < "$VM_BAKE_BASE/template/$a/bake"; done
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest disk write $(sq "${bake:-chroot}") $(sq "$1")"
}

#@help ___guest_disk_write_chroot1
# @command guest disk write chroot <guest>
# @summary The chroot case of 'guest disk write': the clone is mounted and gets its network (rc.conf), the home paths of the template and its ssh host key -- 'guest network write', 'guest home write', 'guest hostkey write'
# @group   guest
# @internal
# @see     guest disk write
# @see     guest network write
# @see     guest home write
# @see     guest hostkey write
#@end
___guest_disk_write_chroot1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest network write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest home write $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest hostkey write $(sq "$1")"
}

#@help __guest_disk_write_cloud_init1
# @internal the cloud-init case of 'guest disk write <guest>' (guest disk write cloud-init <guest>): rewrite to 'guest seed write cloud-init <guest>'
#@end
__guest_disk_write_cloud_init1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest seed write cloud-init $(sq "$1")"
}

#@help __guest_disk_write_autoinstall1
# @internal the autoinstall case of 'guest disk write <guest>' (guest disk write autoinstall <guest>): rewrite to 'guest seed write autoinstall <guest>'
#@end
__guest_disk_write_autoinstall1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest seed write autoinstall $(sq "$1")"
}

#@help __guest_disk_write2
# @internal dispatch fallback of 'guest disk write <bake> <guest>' for a bake that is neither chroot, cloud-init nor autoinstall: an error line
#@end
__guest_disk_write2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "guest disk write: the image of $2 was baked by $1, which has no disk write (chroot | cloud-init | autoinstall)")"
}
