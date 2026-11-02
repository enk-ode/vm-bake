#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# session.sh - the sessions of vm-bake: 'session create <protocol> <guest>'
# prints the client script that opens a guest from the host -- ssh for a
# terminal, x for one application of the guest shown in a Xephyr
# compartment of the host's X server (ssh -X into the compartment's
# display). Nothing is recorded: the script is rendered from the guest
# record, the image's template and the host's variables, and the user keeps
# it wherever they like.

#@help
# @defgroup session  Sessions
# @order   80
#   A session is a client script, printed by 'session create', that the
#   user keeps and runs: 'ssh' opens a terminal in the guest (or runs one
#   command there), 'x' opens a Xephyr compartment on the host's display
#   and runs one program of the guest inside it over ssh -X, so the
#   program's windows never touch the host's own X server. The guest must
#   list the service 'display x' in its template, which gives it xauth and
#   X11Forwarding at bake time. The compartment takes VM_BAKE_XEPHYR_SCREEN
#   and VM_BAKE_XEPHYR_DPI; its display number is the first free one from
#   VM_BAKE_XEPHYR_FIRST, read at generation time.
#@end

#@help
# @defcompletion program    none
# @defcompletion display    none
#@end

#@help ___session_create_ssh1
# @command session create ssh <guest>
# @summary The terminal session: the guest has a record; then the script that opens ssh to <guest>.VM_BAKE_GUEST_DOMAIN on VM_BAKE_SSH_PORT with the host key's private counterpart (printed, not run: keep it where you like)
# @group   session
# @example vm-bake session create ssh dalmatia > ~/bin/dalmatia
# @see     session create x
# @see     guest make
#@end
___session_create_ssh1() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" session script ssh $(sq "$1")"
}

#@help ___session_create_ssh2
# @internal arity-2 sibling of 'session create ssh' (session create ssh <guest> <program>): the script runs that program in the guest instead of a shell
#@end
___session_create_ssh2() {
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" session script ssh $(sq "$1") $(sq "$2")"
}

#@help ___session_create_x2
# @command session create x <guest> <program>
# @summary The compartment session: the guest has a record and its template lists the service 'display x'; the first free display number from VM_BAKE_XEPHYR_FIRST is read at generation time; then the script that starts Xephyr on that display and runs the program in the guest over ssh -X into it (printed, not run)
# @group   session
# @example vm-bake session create x dalmatia idea > ~/bin/dalmatia-idea
# @see     session create ssh
# @see     template service add
# @env     VM_BAKE_XEPHYR_FIRST  the lowest display number a compartment may take
#@end
___session_create_x2() {
	local n="$VM_BAKE_XEPHYR_FIRST"
	while test -e "/tmp/.X11-unix/X$n" && test "$n" -lt 99; do n=$((n + 1)); done
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" guest check record $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" session check display $(sq "$1")"
	printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" session script x $(sq "$1") $(sq "$2") $(sq "$n")"
}

#@help __session_check_display1
# @command session check display <guest>
# @summary The template of the guest's image lists the service 'display x' (read at generation time over the chain): a comment line, else an error line
# @group   session
# @internal
# @see     session create x
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
__session_check_display1() {
	local img="" t="" cur="" chain="" p="" n=0 lines=""
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	lines=$(awk -v base="$VM_BAKE_BASE" -v family=service -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk")
	if printf '%s\n' "$lines" | grep -qx 'display x'; then
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" comment $(sq "guest $1: display x (template $t)")"
	else
		printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error $(sq "session create x: the template of $1 (${t}) lists no service 'display x' (template service add <template> display x, then bake again)")"
	fi
}

#@help _session_script_ssh1
# @command session script ssh <guest>
# @summary Display terminal: the ssh client script for the guest -- exec ssh on VM_BAKE_SSH_PORT with the host key's private counterpart, the guest's known_hosts file under .tmp, a shell or the arguments given to the script
# @group   session
# @internal
# @see     session create ssh
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the guest's sshd port
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest's name lives in
#@end
_session_script_ssh1() {
	local key="$VM_BAKE_HOST_KEY"
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	printf '%s\n' '#!/bin/sh' "# vm-bake session ssh: guest $1 (session create ssh $1)"
	printf '%s\n' "exec ssh -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$1' -o StrictHostKeyChecking=accept-new '$(id -un)@$1.$VM_BAKE_GUEST_DOMAIN' \"\$@\""
}

#@help _session_script_ssh2
# @internal arity-2 of 'session script ssh' (a program): the script runs the program in the guest
#@end
_session_script_ssh2() {
	local key="$VM_BAKE_HOST_KEY"
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	printf '%s\n' '#!/bin/sh' "# vm-bake session ssh: guest $1, program $2 (session create ssh $1 $2)"
	printf '%s\n' "exec ssh -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$1' -o StrictHostKeyChecking=accept-new '$(id -un)@$1.$VM_BAKE_GUEST_DOMAIN' $(sq "$2") \"\$@\""
}

#@help _session_script_x3
# @command session script x <guest> <program> <display>
# @summary Display terminal: the compartment script -- Xephyr on :<display> with VM_BAKE_XEPHYR_SCREEN and VM_BAKE_XEPHYR_DPI and the cursor theme VM_BAKE_XCURSOR_THEME, titled after guest and program, resizeable, never resetting when its last client leaves (xrdb loads and disconnects: without -noreset the server would drop the resources again), without grabbing mouse and keyboard (the pointer leaves the compartment freely, keys reach it while the pointer is inside); the resources Xcursor.theme, Xcursor.size (VM_BAKE_XCURSOR_SIZE) and Xft.dpi loaded into it with xrdb, which is where GTK and Electron programs read cursor and scale; the window manager VM_BAKE_XEPHYR_WM inside it (every window full size; none: no manager); then, once the server answers (xrdb -query), ssh -X -C into the guest with DISPLAY set to the compartment, running the program under the template's env variables (read at generation time) and staying while a process matching the program's name runs in the guest (up to 30 s for it to appear: launchers like code-oss return at once and spawn the program); then the compartment closes with it. Everything the script and its children say goes to .log/session-<guest>-<program>.log of the database
# @group   session
# @internal
# @see     session create x
# @see     template env add
# @env     VM_BAKE_HOST_KEY  its private counterpart is the ssh identity
# @env     VM_BAKE_SSH_PORT  the guest's sshd port
# @env     VM_BAKE_GUEST_DOMAIN  the domain the guest's name lives in
# @env     VM_BAKE_XEPHYR_SCREEN  the compartment's size
# @env     VM_BAKE_XEPHYR_DPI  the compartment's dpi
# @env     VM_BAKE_XEPHYR_WM  the window manager started inside the compartment, or none
# @env     VM_BAKE_XCURSOR_THEME  the cursor theme the compartment's server draws and its resources name
# @env     VM_BAKE_XCURSOR_SIZE  the cursor size in the compartment's resources
# @env     VM_BAKE_TEMPLATE_DIR  the awk program template/awk/template-table.awk
#@end
_session_script_x3() {
	local key="$VM_BAKE_HOST_KEY" img="" t="" cur="" chain="" p="" n=0 envs="" prog=""
	case "$key" in "~/"*) eval "key=~$(id -un)${key#\~}" ;; esac
	IFS= read -r img 2>/dev/null < "$VM_BAKE_BASE/guest/$1/image" || img=""
	IFS= read -r t 2>/dev/null < "$VM_BAKE_BASE/image/$img/template" || t=empty
	cur=$t
	while test "$cur" != empty && test "$n" -lt 32; do
		chain="$cur${chain:+ $chain}"
		IFS= read -r p 2>/dev/null < "$VM_BAKE_BASE/template/$cur/parent" || p=empty
		cur=$p; n=$((n + 1))
	done
	envs=$(awk -v base="$VM_BAKE_BASE" -v family=env -v chain="empty${chain:+ $chain}" -v plain=1 -f "$VM_BAKE_TEMPLATE_DIR/awk/template-table.awk" | tr '\n' ' ')
	prog=${2%% *}; prog=${prog##*/}
	printf '%s\n' '#!/bin/sh' "# vm-bake session x: guest $1, program $2 in the Xephyr compartment :$3 (session create x $1 $2)"
	printf '%s\n' "log='$VM_BAKE_BASE/.log/session-$1-$prog.log'; exec > \"\$log\" 2>&1; printf '%s session x %s: %s on :%s\\n' \"\$(date '+%Y-%m-%d %H:%M:%S')\" $(sq "$1") $(sq "$2") '$3'"
	printf '%s\n' "XCURSOR_THEME=$(sq "$VM_BAKE_XCURSOR_THEME") Xephyr :$3 -screen '$VM_BAKE_XEPHYR_SCREEN' -dpi '$VM_BAKE_XEPHYR_DPI' -title $(sq "$1: $2") -resizeable -no-host-grab -noreset -nolisten tcp &"
	printf '%s\n' 'xephyr=$!'
	printf '%s\n' "n=0; until xrdb -display :$3 -query > /dev/null 2>&1 || test \"\$n\" -ge 100; do n=\$((n + 1)); sleep 0.1; done; printf 'Xephyr pid %s answers after %s tries\\n' \"\$xephyr\" \"\$n\""
	printf '%s\n' "printf 'Xcursor.theme: %s\\nXcursor.size: %s\\nXft.dpi: %s\\n' $(sq "$VM_BAKE_XCURSOR_THEME") $(sq "$VM_BAKE_XCURSOR_SIZE") $(sq "$VM_BAKE_XEPHYR_DPI") | xrdb -display :$3 - && xrdb -display :$3 -query"
	test "$VM_BAKE_XEPHYR_WM" = none || printf '%s\n' "DISPLAY=:$3 $VM_BAKE_XEPHYR_WM &" 'wm=$!' "printf 'window manager $VM_BAKE_XEPHYR_WM pid %s\\n' \"\$wm\""
	printf '%s\n' "DISPLAY=:$3 ssh -X -C -p $VM_BAKE_SSH_PORT -i '${key%.pub}' -o UserKnownHostsFile='$VM_BAKE_BASE/.tmp/known_hosts.$1' -o StrictHostKeyChecking=accept-new '$(id -un)@$1.$VM_BAKE_GUEST_DOMAIN' $(sq "${envs:+env $envs}$2") \"\$@\" $(sq "; rc=\$?; echo \"program exit \$rc\"; n=0; until pgrep -qf '$prog' || test \$n -ge 30; do n=\$((n + 1)); sleep 1; done; echo \"$prog seen after \$n s: \$(pgrep -f '$prog' | tr '\\n' ' ')\"; while pgrep -qf '$prog'; do sleep 2; done; echo 'no $prog process left'")"
	printf '%s\n' 'rc=$?' "printf '%s ssh exit %s, closing the compartment\\n' \"\$(date '+%H:%M:%S')\" \"\$rc\""
	test "$VM_BAKE_XEPHYR_WM" = none || printf '%s\n' 'kill "$wm" 2>/dev/null'
	printf '%s\n' 'kill "$xephyr" 2>/dev/null' 'wait "$xephyr" 2>/dev/null' 'exit "$rc"'
}
