#!/bin/sh
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# vm-bake-unit-test.sh - unit tests for the vm-bake commands
#
# The framework of the engine's unit suite: every test gets its own bootstrapped
# sandbox database; assertions inspect EMISSIONS and sandbox files only.
# Nothing touches vm-bhyve, zfs or the network.
#
# Usage:
#   ./vm-bake-unit-test.sh [--maxprocs N] [profile] [keep] [test names...]
#
set -u

TEST_BASE_DIR="${TMPDIR:-/tmp}/vm-bake-unit-test.$$"
TEST_SCRIPT="./vm-bake.sh"

MAXPROCS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1)
while [ $# -gt 0 ]; do
  case "$1" in
    --maxprocs)   MAXPROCS="${2:?--maxprocs needs a value}"; shift 2 ;;
    --maxprocs=*) MAXPROCS="${1#--maxprocs=}"; shift ;;
    *) break ;;
  esac
done

case "${1:-}" in
  -*) echo "unknown option: $1" >&2
      echo "usage: $0 [--maxprocs N] [<profile>] [keep] [<test names...>]" >&2
      exit 2 ;;
esac
TEST_PROFILE="${1:-minimal}"
if [ ! -f "$(dirname "$0")/template/environment/VM_BAKE_PROFILE_$(echo "$TEST_PROFILE" | tr '[:lower:]' '[:upper:]')" ]; then
  echo "unknown profile: $TEST_PROFILE" >&2
  exit 2
fi
KEEP_DATABASES="${2:-false}"
[ $# -ge 1 ] && shift
[ $# -ge 1 ] && shift
ALL_TESTS=$(grep -o '^test_[a-z_0-9]*()' "$0" | sed 's/()$//' | tr '\n' ' ')
TEST_FILTER="$*"
[ -z "$TEST_FILTER" ] && TEST_FILTER="$ALL_TESTS"

should_run_test() {
  local test_name="$1"
  for filter_test in $TEST_FILTER; do
    [ "$filter_test" = "$test_name" ] && { "$test_name"; return 0; }
  done
  return 0
}

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

if [ -t 1 ] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
  COLOR_GREEN=$(tput setaf 2); COLOR_RED=$(tput setaf 1)
  COLOR_BLUE=$(tput setaf 4); COLOR_RESET=$(tput sgr0)
else
  COLOR_GREEN=""; COLOR_RED=""; COLOR_BLUE=""; COLOR_RESET=""
fi

TEST_DIR=""

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo "${COLOR_GREEN}✓${COLOR_RESET} $*"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); echo "${COLOR_RED}✗${COLOR_RESET} $*"; }

test_header() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo ""
  echo "${COLOR_BLUE}TEST ${TESTS_RUN}:${COLOR_RESET} $* [db: ${TEST_DIR:-}]"
}

# test_setup - fresh sandbox DB per test. The terminal interpreter is pinned
# to sh (emissions ACT); the cat-pinned display terminals keep their pins.
test_setup() {
  TEST_DIR="$TEST_BASE_DIR/test-$TESTS_RUN"
  mkdir -p "$TEST_DIR"
  local bootstrap_log="$TEST_DIR/bootstrap.log"
  if ! VM_BAKE_ROOT="$TEST_BASE_DIR" VM_BAKE_BASE="$TEST_DIR" "$TEST_SCRIPT" bootstrap "test-$TESTS_RUN" "$TEST_PROFILE" > "$bootstrap_log" 2>&1; then
    echo "${COLOR_RED}ERROR:${COLOR_RESET} Database bootstrap failed"
    sed 's/^/  /' "$bootstrap_log"
    exit 1
  fi
  VM_BAKE_BASE="$TEST_DIR" "$TEST_SCRIPT" setenv VM_BAKE_TERMINAL_INTERPRETER sh > /dev/null 2>&1
}

# The output is captured before it is printed: a consumer that closes early
# (grep -q) must never reach the running batch.
run_vmbake() { local out rc; out=$(VM_BAKE_BASE="$TEST_DIR" "$TEST_SCRIPT" "$@" 2>&1); rc=$?; printf '%s\n' "$out"; return $rc; }

# record_of <name> -- the record directory behind template/<name>
record_of() { printf '%s\n' "$TEST_DIR/.templates/$(basename "$(readlink "$TEST_DIR/template/$1")")"; }

test_summary() {
  local total=$((TESTS_PASSED + TESTS_FAILED))
  echo ""
  echo "========================================"
  echo "Unit Test Summary"
  echo "========================================"
  echo "Test Functions:     $TESTS_RUN"
  echo "Total Assertions:   $total"
  echo "${COLOR_GREEN}Passed Assertions:  $TESTS_PASSED${COLOR_RESET}"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    echo "${COLOR_RED}Failed Assertions:  $TESTS_FAILED${COLOR_RESET}"
    echo ""
    echo "${COLOR_RED}SOME TESTS FAILED${COLOR_RESET}"
    echo "Test artifacts preserved in: $TEST_BASE_DIR"
    return 1
  fi
  echo "Failed Assertions:  $TESTS_FAILED"
  echo ""
  echo "${COLOR_GREEN}ALL TESTS PASSED${COLOR_RESET}"
  if [ "$KEEP_DATABASES" = "true" ] || [ "$KEEP_DATABASES" = "keep" ]; then
    echo "Test databases preserved in: $TEST_BASE_DIR"
  else
    rm -rf "$TEST_BASE_DIR"
  fi
  return 0
}

# ============================================================================

test_bootstrap_layout() {
  test_header "bootstrap: the layout of a vm-bake database, the root empty"
  test_setup
  if [ -d "$TEST_DIR/template" ] && [ -d "$TEST_DIR/.templates" ] && [ -d "$TEST_DIR/.env/local" ]; then
    pass "template/, .templates/ and .env/ exist"
  else
    fail "layout incomplete: $(ls -a "$TEST_DIR")"
  fi
  if [ ! -d "$TEST_DIR/stage" ] && [ ! -d "$TEST_DIR/pem" ]; then
    pass "no stage or key directories of the engine"
  else
    fail "directories of the engine leaked into the layout"
  fi
  if run_vmbake template list | grep -q "^#   empty .* root"; then
    pass "template list shows the root empty"
  else
    fail "root missing: $(run_vmbake template list)"
  fi
  if run_vmbake template check template empty > /dev/null && ! run_vmbake template check template nosuch > /dev/null; then
    pass "the root exists without a record, an unknown name does not"
  else
    fail "check template empty: $(run_vmbake template check template empty)"
  fi
  if run_vmbake help | grep -q "^  vm-bake template add"; then
    pass "help lists the template commands under the harness name"
  else
    fail "help: $(run_vmbake help | head -5)"
  fi
  if run_vmbake help | grep -q "stage add"; then
    fail "help leaks the stage vocabulary"
  else
    pass "help shows no stage vocabulary"
  fi
}

test_template_add_chain() {
  test_header "template add: parent default, chain, idempotence, name and parent guards"
  test_setup
  run_vmbake template add freebsd > /dev/null
  run_vmbake template add freebsd-15.1 freebsd > /dev/null
  run_vmbake template add freebsd-dev freebsd-15.1 > /dev/null
  if [ "$(cat "$(record_of freebsd)/parent")" = "empty" ]; then
    pass "add without parent records empty"
  else
    fail "parent of freebsd: $(cat "$(record_of freebsd)/parent")"
  fi
  if [ "$(cat "$(record_of freebsd-dev)/parent")" = "freebsd-15.1" ]; then
    pass "add with parent records it"
  else
    fail "parent of freebsd-dev wrong"
  fi
  if grep -q '^name=freebsd-dev$' "$(record_of freebsd-dev)/metadata" && grep -q '^created=' "$(record_of freebsd-dev)/metadata"; then
    pass "metadata carries name and created"
  else
    fail "metadata: $(cat "$(record_of freebsd-dev)/metadata")"
  fi
  local id; id=$(basename "$(readlink "$TEST_DIR/template/freebsd")")
  if run_vmbake template add freebsd | grep -q "already exists" && [ "$(basename "$(readlink "$TEST_DIR/template/freebsd")")" = "$id" ]; then
    pass "re-add is idempotent, the id stays"
  else
    fail "re-add minted or failed"
  fi
  if run_vmbake template add x nosuch | grep -q "unknown template nosuch"; then
    pass "unknown parent is refused"
  else
    fail "unknown parent accepted"
  fi
  if run_vmbake template add 'bad name' | grep -q "invalid template name" && run_vmbake template add empty | grep -q "invalid template name" && run_vmbake template add all | grep -q "invalid template name"; then
    pass "invalid and reserved names are refused"
  else
    fail "name guard: $(run_vmbake template add empty)"
  fi
  if run_vmbake template show freebsd-dev | grep -q "chain    : empty > freebsd > freebsd-15.1 > freebsd-dev"; then
    pass "show resolves the chain root to leaf"
  else
    fail "chain: $(run_vmbake template show freebsd-dev | grep chain)"
  fi
  if run_vmbake template list | grep -q "^#   freebsd-dev .*freebsd-15.1"; then
    pass "list shows the parent"
  else
    fail "list: $(run_vmbake template list)"
  fi
}

test_template_scalars() {
  test_header "template scalars: base variants, bake and firmware words, resource, immutability, drop"
  test_setup
  run_vmbake template add freebsd > /dev/null
  run_vmbake template add freebsd-15.1 freebsd > /dev/null
  run_vmbake template base release freebsd-15.1 amd64 15.1-RELEASE > /dev/null
  if [ "$(cat "$(record_of freebsd-15.1)/base")" = "release amd64 15.1-RELEASE" ]; then
    pass "base release stores 'release <arch> <version>'"
  else
    fail "base record: $(cat "$(record_of freebsd-15.1)/base" 2>&1)"
  fi
  if run_vmbake template base release freebsd-15.1 amd64 15.1-RELEASE | grep -q "unchanged"; then
    pass "identical re-add is a note"
  else
    fail "identical re-add not idempotent"
  fi
  if run_vmbake template base release freebsd-15.1 amd64 15.2-RELEASE | grep -q "immutable"; then
    pass "differing re-add is refused"
  else
    fail "differing re-add accepted"
  fi
  if run_vmbake template base release freebsd-15.1 amd64 15.1 | grep -q "invalid version" && run_vmbake template base release freebsd-15.1 i386 15.1-RELEASE | grep -q "unknown architecture"; then
    pass "version and arch are validated"
  else
    fail "version/arch guard"
  fi
  run_vmbake template base drop freebsd-15.1 > /dev/null
  if [ ! -f "$(record_of freebsd-15.1)/base" ] && run_vmbake template base release freebsd-15.1 amd64 15.2-RELEASE | grep -q "base = release amd64 15.2-RELEASE"; then
    pass "base drop, then a new base"
  else
    fail "drop/re-add of base"
  fi
  if run_vmbake template base drop freebsd | grep -q "no own base"; then
    pass "base drop without own base is refused"
  else
    fail "base drop on unset base"
  fi
  run_vmbake template base stage freebsd amd64 daily-v1 > /dev/null
  run_vmbake template add debian > /dev/null
  run_vmbake template base image debian amd64 13 https://cloud.debian.org/x.qcow2 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef > /dev/null
  run_vmbake template add windows > /dev/null
  run_vmbake template base iso windows amd64 /data/iso/win.iso 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef > /dev/null
  if [ "$(cat "$(record_of freebsd)/base")" = "stage amd64 daily-v1" ] && grep -q '^image amd64 13 https://cloud.debian.org/x.qcow2 0123' "$(record_of debian)/base" && grep -q '^iso amd64 /data/iso/win.iso 0123' "$(record_of windows)/base"; then
    pass "base stage, image and iso record their variant"
  else
    fail "base variants: $(cat "$(record_of freebsd)/base" "$(record_of debian)/base" "$(record_of windows)/base" 2>&1)"
  fi
  if run_vmbake template base image debian amd64 13 ftp://x 0123 | grep -q "invalid url" && run_vmbake template base iso windows amd64 relative/win.iso 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef | grep -q "invalid path"; then
    pass "url and path are validated"
  else
    fail "url/path guard"
  fi
  run_vmbake template bake chroot freebsd > /dev/null
  run_vmbake template firmware uefi freebsd > /dev/null
  if [ "$(cat "$(record_of freebsd)/bake")" = "chroot" ] && [ "$(cat "$(record_of freebsd)/firmware")" = "uefi" ]; then
    pass "bake and firmware take the word before the template"
  else
    fail "bake/firmware records"
  fi
  if run_vmbake template bake foo freebsd | grep -q "unknown way foo" && run_vmbake template firmware efi freebsd | grep -q "unknown firmware efi"; then
    pass "unknown bake and firmware words fall to the error line"
  else
    fail "enum fallback: $(run_vmbake template bake foo freebsd)"
  fi
  run_vmbake template bake cloud-init debian > /dev/null
  if [ "$(cat "$(record_of debian)/bake")" = "cloud-init" ]; then
    pass "the hyphenated word cloud-init dispatches"
  else
    fail "cloud-init: $(run_vmbake template bake cloud-init debian)"
  fi
  run_vmbake template resource freebsd-15.1 8 32G 64G > /dev/null
  if [ "$(cat "$(record_of freebsd-15.1)/resource")" = "8 32G 64G" ]; then
    pass "resource stores '<cpu> <memory> <disk>'"
  else
    fail "resource record"
  fi
  if run_vmbake template resource freebsd-15.1 0 32G 64G | grep -q "cpu count" && run_vmbake template resource freebsd 8 32GB 64G | grep -q "a size is"; then
    pass "count and size are validated"
  else
    fail "resource guards"
  fi
  if run_vmbake template show freebsd-15.1 | grep -q "bake     : chroot .*(freebsd)" && run_vmbake template show freebsd-15.1 | grep -q "resource : 8 32G 64G .*(freebsd-15.1)"; then
    pass "show names the origin of inherited and own scalars"
  else
    fail "show scalars: $(run_vmbake template show freebsd-15.1 | grep 'bake\|resource')"
  fi
}

test_template_lists() {
  test_header "template lists: add, stdin, drop, mask, show with origin, every family"
  test_setup
  run_vmbake template add freebsd > /dev/null
  run_vmbake template add freebsd-dev freebsd > /dev/null
  run_vmbake template package add freebsd emacs > /dev/null
  printf 'vscode\nclaude-code\n' | run_vmbake template package add freebsd-dev - > /dev/null
  if [ "$(grep -c . "$(record_of freebsd-dev)/package")" = "2" ]; then
    pass "add - reads names from stdin"
  else
    fail "stdin add: $(cat "$(record_of freebsd-dev)/package" 2>&1)"
  fi
  run_vmbake template package add freebsd-dev vscode > /dev/null
  if [ "$(grep -c . "$(record_of freebsd-dev)/package")" = "2" ]; then
    pass "re-add of a line is idempotent"
  else
    fail "duplicate line appended"
  fi
  if run_vmbake template package show freebsd-dev | grep -q "^#   freebsd  *emacs" && run_vmbake template package show freebsd-dev | grep -q "^#   freebsd-dev  *vscode"; then
    pass "show lists inherited and own lines with their origin"
  else
    fail "package show: $(run_vmbake template package show freebsd-dev)"
  fi
  if run_vmbake template package drop freebsd-dev emacs | grep -q "no own package entry"; then
    pass "an inherited line cannot be dropped in the child"
  else
    fail "drop of inherited line accepted"
  fi
  run_vmbake template package mask freebsd-dev emacs > /dev/null
  if ! run_vmbake template package show freebsd-dev | grep -q emacs && run_vmbake template package show freebsd | grep -q emacs; then
    pass "mask hides the inherited line below, not at its origin"
  else
    fail "mask: $(run_vmbake template package show freebsd-dev)"
  fi
  run_vmbake template package drop freebsd-dev claude-code > /dev/null
  if ! grep -q claude-code "$(record_of freebsd-dev)/package" && grep -q vscode "$(record_of freebsd-dev)/package"; then
    pass "drop removes exactly the own line"
  else
    fail "drop: $(cat "$(record_of freebsd-dev)/package")"
  fi
  if run_vmbake template package add freebsd-dev 'bad name' | grep -q "invalid package name"; then
    pass "package names are validated"
  else
    fail "package name guard"
  fi
  run_vmbake template rc add freebsd-dev linux_enable YES > /dev/null
  run_vmbake template user add freebsd-dev brj host > /dev/null
  run_vmbake template service add freebsd-dev display x > /dev/null
  run_vmbake template forbid add freebsd-dev usb > /dev/null
  run_vmbake template forbid add freebsd-dev net 192.168.1.0/24 > /dev/null
  run_vmbake template data add freebsd-dev home 64G proton > /dev/null
  run_vmbake template session add freebsd-dev ssh > /dev/null
  local d; d=$(record_of freebsd-dev)
  if [ "$(cat "$d/rc")" = "linux_enable=YES" ] && [ "$(cat "$d/user")" = "brj host" ] && [ "$(cat "$d/service")" = "display x" ] && [ "$(cat "$d/data")" = "home 64G proton" ] && [ "$(cat "$d/session")" = "ssh" ] && grep -qx usb "$d/forbid" && grep -qx "net 192.168.1.0/24" "$d/forbid"; then
    pass "rc, user, service, forbid (with and without argument), data, session record their lines"
  else
    fail "family records: $(cd "$d" && grep . rc user service forbid data session)"
  fi
  if run_vmbake template rc add freebsd-dev 1bad YES | grep -q "invalid variable" && run_vmbake template user add freebsd-dev Brj host | grep -q "invalid login" && run_vmbake template user add freebsd-dev brj 10x | grep -q "uid is a number" && run_vmbake template service add freebsd-dev sound pulse | grep -q "invalid service" && run_vmbake template forbid add freebsd-dev net | grep -q "takes an argument" && run_vmbake template session add freebsd-dev vnc | grep -q "unknown protocol"; then
    pass "every family validates its entry"
  else
    fail "family guards"
  fi
  run_vmbake template rc drop freebsd-dev linux_enable YES > /dev/null
  if [ ! -s "$d/rc" ]; then
    pass "rc drop removes the line by variable and value"
  else
    fail "rc drop: $(cat "$d/rc")"
  fi
  if run_vmbake template show freebsd-dev | grep -q "^# forbid of freebsd-dev" && run_vmbake template show freebsd-dev | grep -q "^#   freebsd-dev  *net 192.168.1.0/24"; then
    pass "show renders every family"
  else
    fail "show families: $(run_vmbake template show freebsd-dev | grep -c '^# ')"
  fi
}

test_template_drop_guards() {
  test_header "template drop: children and the root protect, a leaf goes with its record"
  test_setup
  run_vmbake template add freebsd > /dev/null
  run_vmbake template add freebsd-15.1 freebsd > /dev/null
  if run_vmbake template drop freebsd | grep -q "is the parent of freebsd-15.1"; then
    pass "a parent is not dropped"
  else
    fail "parent dropped: $(run_vmbake template drop freebsd)"
  fi
  if run_vmbake template drop empty | grep -q "root empty cannot be dropped"; then
    pass "the root is not dropped"
  else
    fail "root drop: $(run_vmbake template drop empty)"
  fi
  local d; d=$(record_of freebsd-15.1)
  run_vmbake template drop freebsd-15.1 > /dev/null
  if [ ! -e "$TEST_DIR/template/freebsd-15.1" ] && [ ! -d "$d" ]; then
    pass "drop removes the name and the record"
  else
    fail "drop left: $(ls "$TEST_DIR/template" "$TEST_DIR/.templates")"
  fi
  if run_vmbake template drop freebsd | grep -q "Dropped template freebsd"; then
    pass "the former parent drops once childless"
  else
    fail "drop of childless parent"
  fi
  if run_vmbake template drop nosuch | grep -q "unknown template nosuch"; then
    pass "drop of an unknown template is refused"
  else
    fail "drop unknown"
  fi
}

test_template_dump_restore() {
  test_header "template dump and restore: parents first, a second database equals the first, replay idempotent"
  test_setup
  run_vmbake template add freebsd > /dev/null
  run_vmbake template bake chroot freebsd > /dev/null
  run_vmbake template firmware uefi freebsd > /dev/null
  run_vmbake template package add freebsd emacs > /dev/null
  run_vmbake template add freebsd-15.1 freebsd > /dev/null
  run_vmbake template base release freebsd-15.1 amd64 15.1-RELEASE > /dev/null
  run_vmbake template add freebsd-dev freebsd-15.1 > /dev/null
  run_vmbake template resource freebsd-dev 8 32G 64G > /dev/null
  run_vmbake template package add freebsd-dev vscode > /dev/null
  run_vmbake template package mask freebsd-dev emacs > /dev/null
  run_vmbake template rc add freebsd-dev linux_enable YES > /dev/null
  run_vmbake template service add freebsd-dev net dev > /dev/null
  run_vmbake template forbid add freebsd-dev net 192.168.1.0/24 > /dev/null
  run_vmbake template data add freebsd-dev home 64G proton > /dev/null
  run_vmbake template session add freebsd-dev x > /dev/null
  run_vmbake template dump all > "$TEST_DIR/all.vmb" 2>/dev/null
  if [ "$(grep -n "template add 'freebsd' 'empty'" "$TEST_DIR/all.vmb" | cut -d: -f1)" -lt "$(grep -n "template add 'freebsd-15.1'" "$TEST_DIR/all.vmb" | cut -d: -f1)" ]; then
    pass "dump all writes parents before children"
  else
    fail "dump order: $(grep 'template add' "$TEST_DIR/all.vmb")"
  fi
  if grep -q "template base release 'freebsd-15.1' 'amd64' '15.1-RELEASE'" "$TEST_DIR/all.vmb" && grep -q "template bake chroot 'freebsd'" "$TEST_DIR/all.vmb" && grep -q "template package mask 'freebsd-dev' 'emacs'" "$TEST_DIR/all.vmb" && grep -q "template rc add 'freebsd-dev' 'linux_enable' 'YES'" "$TEST_DIR/all.vmb" && grep -q "template forbid add 'freebsd-dev' 'net' '192.168.1.0/24'" "$TEST_DIR/all.vmb"; then
    pass "dump replays scalars, lines and masks in the command vocabulary"
  else
    fail "dump lines: $(cat "$TEST_DIR/all.vmb")"
  fi
  local second="$TEST_BASE_DIR/test-$TESTS_RUN-second"
  mkdir -p "$second"
  VM_BAKE_ROOT="$TEST_BASE_DIR" VM_BAKE_BASE="$second" "$TEST_SCRIPT" bootstrap "test-$TESTS_RUN-second" "$TEST_PROFILE" > /dev/null 2>&1
  VM_BAKE_BASE="$second" "$TEST_SCRIPT" setenv VM_BAKE_TERMINAL_INTERPRETER sh > /dev/null 2>&1
  if VM_BAKE_BASE="$second" "$TEST_SCRIPT" template restore "$TEST_DIR/all.vmb" > "$TEST_DIR/restore.log" 2>&1; then
    pass "restore replays the dump"
  else
    fail "restore failed: $(tail -5 "$TEST_DIR/restore.log")"
  fi
  if [ "$(run_vmbake template show freebsd-dev | grep -v 'template-')" = "$(VM_BAKE_BASE="$second" "$TEST_SCRIPT" template show freebsd-dev 2>&1 | grep -v 'template-')" ]; then
    pass "the restored template shows identical to the source"
  else
    fail "show differs after restore"
  fi
  if VM_BAKE_BASE="$second" "$TEST_SCRIPT" template restore "$TEST_DIR/all.vmb" 2>&1 | grep -q "already exists" && [ "$(VM_BAKE_BASE="$second" "$TEST_SCRIPT" template list 2>&1 | grep -c '^#   freebsd')" = "3" ]; then
    pass "a second replay is idempotent"
  else
    fail "second replay: $(VM_BAKE_BASE="$second" "$TEST_SCRIPT" template list 2>&1)"
  fi
  if run_vmbake template dump freebsd-dev | grep -q "template add 'freebsd-dev' 'freebsd-15.1'" && ! run_vmbake template dump freebsd-dev | grep -q "template add 'freebsd' "; then
    pass "dump of one template writes that template only"
  else
    fail "single dump"
  fi
}

test_dispatch_and_help() {
  test_header "dispatch: wrong arity, unknown command; help: group and detail"
  test_setup
  if run_vmbake template package add | grep -q "wrong number of arguments for 'template package add'"; then
    pass "a known path with wrong arity says so"
  else
    fail "wrong arity: $(run_vmbake template package add)"
  fi
  if run_vmbake template nosuch | grep -q "unknown command: template nosuch"; then
    pass "an unknown word under template is unknown"
  else
    fail "unknown: $(run_vmbake template nosuch)"
  fi
  if run_vmbake help template | grep -q "^Templates" && run_vmbake help template show | grep -q "vm-bake template show freebsd-dev"; then
    pass "help renders the template group and the example of a command"
  else
    fail "help: $(run_vmbake help template | head -3)"
  fi
  if ! run_vmbake help | grep -q "template leaf write" && run_vmbake help template leaf write | grep -q "Act terminal"; then
    pass "internal anchors stay out of the overview and answer when asked"
  else
    fail "internal visibility"
  fi
  if run_vmbake version | grep -q "[0-9]"; then
    pass "version answers"
  else
    fail "version: $(run_vmbake version)"
  fi
}

test_inspect_by_default() {
  test_header "inspect by default: the display terminals print under cat, the pinned acts still act"
  test_setup
  VM_BAKE_BASE="$TEST_DIR" "$TEST_SCRIPT" setenv VM_BAKE_TERMINAL_INTERPRETER cat > /dev/null 2>&1
  run_vmbake template add freebsd > /dev/null
  if [ -L "$TEST_DIR/template/freebsd" ]; then
    pass "template add acts under the cat default (its terminals are pinned to sh)"
  else
    fail "template add did not act: $(run_vmbake template add freebsd)"
  fi
  if run_vmbake template list | grep -q "^#   freebsd"; then
    pass "display terminals print under cat"
  else
    fail "list under cat: $(run_vmbake template list)"
  fi
}

# pin_image_cat - every act terminal of the image bake and the guests pinned
# to cat in the sandbox, VERIFIED through getintp before any of them is
# called: the acts default to 'sudo sh', and a sudo that does not ask would
# run them for real.
IMAGE_ACTS="lock_take lock_drop lock_release tree_ensure dataset_create dataset_destroy fetch verify disk_write disk_create disk_attach disk_partition disk_format disk_grow disk_relabel disk_mount keys_write pkg_base repo_write boot_write pkg_install pkgfile_stage_host pkgfile_stage_builder pkgfile_add port_build port_install rc_write env_write user_make root_lock doas_write ssh_write pkg_report disk_unmount disk_detach disk_release digest_write snapshot_take readonly_set builder_conf_write builder_wait builder_shutdown builder_gone"
GUEST_ACTS="switch_ensure clone conf_write link_write link_drop network_write dns_write knownhosts_drop run halt dataset_destroy"
pin_image_cat() {
  local f
  for f in $IMAGE_ACTS; do printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_INTERPRETER_image_$f"; done
  for f in $GUEST_ACTS; do printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_INTERPRETER_guest_$f"; done
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  [ "$(run_vmbake getintp image_dataset_create | tail -1)" = cat ] && [ "$(run_vmbake getintp image_snapshot_take | tail -1)" = cat ] && [ "$(run_vmbake getintp guest_clone | tail -1)" = cat ]
}

# image_chain - the template chain of the walkthrough in the sandbox: a
# release-based freebsd-dev and an image-based freebsd-builder
image_chain() {
  run_vmbake template add freebsd > /dev/null
  run_vmbake template add freebsd-15.1 freebsd > /dev/null
  run_vmbake template base release freebsd-15.1 amd64 15.1-RELEASE > /dev/null
  run_vmbake template add freebsd-dev freebsd-15.1 > /dev/null
  run_vmbake template resource freebsd-dev 8 32G 64G > /dev/null
  run_vmbake template package add freebsd-dev claude-code > /dev/null
  run_vmbake template package add freebsd-dev git > /dev/null
  run_vmbake template rc add freebsd-dev sshd_enable YES > /dev/null
  run_vmbake template rc add freebsd-dev kern_securelevel 2 > /dev/null
  run_vmbake template user add freebsd-dev "$(id -un)" host > /dev/null
  run_vmbake template add freebsd-builder freebsd > /dev/null
  run_vmbake template base image freebsd-builder amd64 15.1-RELEASE https://download.freebsd.org/x/FreeBSD-15.1-RELEASE-amd64-ufs.raw.xz a8e2c0f8331be615ef008c167069076833a417e968ff6b7d8e83b4ac762e9409 > /dev/null
  run_vmbake template resource freebsd-builder 2 4G 16G > /dev/null
  run_vmbake template package add freebsd-builder doas > /dev/null
  run_vmbake template rc add freebsd-builder sshd_enable YES > /dev/null
  run_vmbake template user add freebsd-builder bake 1010 > /dev/null
}

test_image_plan() {
  test_header "image plan: make freebsd is the chain of five steps; create, base and close choose by base kind and VM_BAKE_BAKE_IN (batches shown, not run)"
  test_setup
  image_chain
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  local plan today
  today=$(date -u '+%Y%m%d')
  plan=$(run_vmbake image make freebsd freebsd-dev)
  if [ "$(printf '%s\n' "$plan" | grep -c '"\$VM_BAKE_CONTEXT_SCRIPT"')" = "7" ] && printf '%s\n' "$plan" | sed -n 1p | grep -q "note 'image make freebsd: template freebsd-dev -> image freebsd-dev-$today" && printf '%s\n' "$plan" | grep -q "image create 'freebsd-dev' 'freebsd-dev-$today'" && printf '%s\n' "$plan" | sed -n 7p | grep -q "image seal 'freebsd-dev-$today'"; then
    pass "make freebsd: the name announced, the template checked, then create, base, burn, close, seal"
  else
    fail "make plan: $plan"
  fi
  plan=$(run_vmbake image create freebsd-dev x)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "13" ] && printf '%s\n' "$plan" | grep -q "image disk create 'x' '64G'" && printf '%s\n' "$plan" | grep -q "image lock take 'x'" && printf '%s\n' "$plan" | sed -n 13p | grep -q "image disk detach 'x'"; then
    pass "create of a release base: checks, lock, record, dataset, disk in 64G, attach, partition, format, detach"
  else
    fail "create release plan: $plan"
  fi
  plan=$(run_vmbake image create freebsd-builder b)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "15" ] && printf '%s\n' "$plan" | grep -q "image tree ensure" && printf '%s\n' "$plan" | grep -q "image fetch 'https://download.freebsd.org/x/FreeBSD-15.1-RELEASE-amd64-ufs.raw.xz'" && printf '%s\n' "$plan" | grep -q "image verify 'https://.*' 'a8e2c0f8" && printf '%s\n' "$plan" | grep -q "image disk write 'b' 'https://.*' '16G'" && printf '%s\n' "$plan" | grep -q "image disk relabel 'b'"; then
    pass "create of an image base: tree, fetch, verify against the record, write, attach, grow, relabel, detach"
  else
    fail "create image plan: $plan"
  fi
  if run_vmbake image create freebsd x | grep -q "no release or image base"; then
    pass "create without a base falls to the error line"
  else
    fail "create guard: $(run_vmbake image create freebsd x)"
  fi
  run_vmbake image record write freebsd-dev x > /dev/null
  run_vmbake image record write freebsd-builder b > /dev/null
  if [ "$(run_vmbake image base x | grep -c .)" = "5" ] && run_vmbake image base x | grep -q "image disk attach 'x'" && run_vmbake image base content x | grep -q "image pkg base 'x' 'FreeBSD:15:amd64' '1501000'" && [ "$(run_vmbake image base content b | grep -c .)" = "2" ]; then
    pass "base on the host: attach, mount, content; release content installs pkgbase, image content only repos and loader"
  else
    fail "base plan: $(run_vmbake image base x; run_vmbake image base content x; run_vmbake image base content b)"
  fi
  printf 'builder\n' > "$TEST_DIR/.env/local/VM_BAKE_BAKE_IN"; rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake image base x | grep -q "image builder start 'x'" && [ "$(run_vmbake image base x | grep -c .)" = "4" ] && run_vmbake image close x | grep -q "image builder stop" && run_vmbake image builder start x | grep -q "guest check record 'bake'"; then
    pass "base and close in the builder: the builder started with the disk, stopped before the digest"
  else
    fail "builder plans: $(run_vmbake image base x; run_vmbake image close x)"
  fi
  printf 'elsewhere\n' > "$TEST_DIR/.env/local/VM_BAKE_BAKE_IN"; rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake image base x | grep -q "VM_BAKE_BAKE_IN is 'elsewhere'"; then
    pass "an unknown VM_BAKE_BAKE_IN falls to the error line"
  else
    fail "bake-in guard: $(run_vmbake image base x)"
  fi
  printf 'host\n' > "$TEST_DIR/.env/local/VM_BAKE_BAKE_IN"; rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  plan=$(run_vmbake image burn x)
  if printf '%s\n' "$plan" | grep -q "image check users 'x'" && printf '%s\n' "$plan" | grep -q "image root lock 'x'" && [ "$(printf '%s\n' "$plan" | grep -c .)" = "9" ]; then
    pass "burn: users checked, then packages, rc, users, root locked, doas, sshd"
  else
    fail "burn plan: $plan"
  fi
  if [ "$(run_vmbake image close x | grep -c .)" = "6" ] && [ "$(run_vmbake image seal x | grep -c .)" = "6" ] && [ "$(run_vmbake image drop x | grep -c .)" = "5" ] && run_vmbake image drop x | grep -q "image dataset destroy 'x'"; then
    pass "close and seal six lines each, drop five: release, destroy, record, lock"
  else
    fail "close/seal/drop plan: $(run_vmbake image close x; run_vmbake image seal x; run_vmbake image drop x)"
  fi
  plan=$(run_vmbake image builder use)
  if printf '%s\n' "$plan" | sed -n 1p | grep -q "setenv VM_BAKE_BAKE_IN builder" && [ "$(printf '%s\n' "$plan" | grep -c "setintp image_")" = "17" ] && printf '%s\n' "$plan" | grep -q "setintp image_pkg_base 'ssh -p 2222 -i .* bake@172.16.100.250 doas sh'" && [ "$(run_vmbake image builder leave | grep -c "unsetintp image_")" = "17" ]; then
    pass "builder use and leave: the place and seventeen pins, each a setintp or unsetintp line"
  else
    fail "builder use/leave: $plan"
  fi
}

test_image_guards() {
  test_header "image guards: resource, name, absent, record, mounted, closed, lock, users"
  test_setup
  image_chain
  if run_vmbake image check resource freebsd | grep -q "no resource"; then
    pass "a template without resource is refused"
  else
    fail "resource guard: $(run_vmbake image check resource freebsd)"
  fi
  if run_vmbake image name valid 'bad name' | grep -q "invalid image name" && run_vmbake image name valid a-name-of-thirty-one-characters1 | grep -q "invalid image name" && [ -z "$(run_vmbake image name valid ok-name.1)" ]; then
    pass "image names are record names of at most 30 characters"
  else
    fail "name guard"
  fi
  if run_vmbake image check record x | grep -q "unknown image x" && run_vmbake image check mounted x | grep -q "not mounted" && run_vmbake image check closed x | grep -q "no digest" && run_vmbake image check lock x | grep -q "held by nobody"; then
    pass "record, mounted, closed and lock guards name what is missing"
  else
    fail "state guards"
  fi
  run_vmbake image record write freebsd-dev x > /dev/null
  if run_vmbake image check absent x | grep -q "x exists" && [ -z "$(run_vmbake image check record x)" ]; then
    pass "after the record: absent refuses, record passes"
  else
    fail "absent/record after write: $(run_vmbake image check absent x)"
  fi
  run_vmbake setenv VM_BAKE_HOST_KEY "$TEST_DIR/nokey.pub" > /dev/null
  if run_vmbake image check users x | grep -q "does not resolve"; then
    pass "users: an unreadable key file is refused"
  else
    fail "users key guard: $(run_vmbake image check users x)"
  fi
  printf 'ssh-ed25519 AAAATEST test@host\n' > "$TEST_DIR/key.pub"
  run_vmbake setenv VM_BAKE_HOST_KEY "$TEST_DIR/key.pub" > /dev/null
  if [ -z "$(run_vmbake image check users x)" ]; then
    pass "users: a host user and a readable key resolve"
  else
    fail "users resolve: $(run_vmbake image check users x)"
  fi
  run_vmbake template user add freebsd-dev zz_no_such_user_zz host > /dev/null
  if run_vmbake image check users x | grep -q "does not resolve"; then
    pass "users: uid host without a host user is refused"
  else
    fail "users host guard"
  fi
}

test_image_emissions() {
  test_header "image emissions: every act terminal shown under cat (pins verified first)"
  test_setup
  image_chain
  if pin_image_cat; then
    pass "every image and guest act is pinned to cat in the sandbox"
  else
    fail "acts not pinned to cat -- not calling them"; return
  fi
  run_vmbake setenv VM_BAKE_IMAGE_DIR "$TEST_DIR/img" > /dev/null
  run_vmbake setenv VM_BAKE_IMAGE_CACHE "$TEST_DIR/cache" > /dev/null
  printf 'ssh-ed25519 AAAATEST test@host\n' > "$TEST_DIR/key.pub"
  run_vmbake setenv VM_BAKE_HOST_KEY "$TEST_DIR/key.pub" > /dev/null
  run_vmbake image record write freebsd-dev x > /dev/null
  run_vmbake image record write freebsd-builder b > /dev/null
  local out
  out=$(run_vmbake image dataset create x)
  if printf '%s\n' "$out" | grep -q "zfs list -H -o name '$TEST_DIR/img'" && printf '%s\n' "$out" | grep -q 'zfs create "$ds/x"'; then
    pass "dataset create: under the images' dataset, as the user"
  else
    fail "dataset create: $out"
  fi
  out=$(run_vmbake image disk partition x; run_vmbake image disk format x; run_vmbake image disk mount x)
  if printf '%s\n' "$out" | grep -q "gpart add -t efi -s 260M -a 1m -l 'x-efi'" && printf '%s\n' "$out" | grep -q "gpart add -t freebsd-ufs -a 1m -l 'x-root'" && printf '%s\n' "$out" | grep -q "newfs -j '/dev/gpt/x-root'" && printf '%s\n' "$out" | grep -q "mount '/dev/gpt/x-root' '$TEST_DIR/img/x/mnt'" && printf '%s\n' "$out" | grep -q "mount -t msdosfs '/dev/gpt/x-efi'" && printf '%s\n' "$out" | grep -q "mount -t devfs devfs '$TEST_DIR/img/x/mnt/dev'"; then
    pass "partition, format, mount: labels <image>-efi and <image>-root, SUJ, both mounts by label"
  else
    fail "disk emissions: $out"
  fi
  out=$(run_vmbake image fetch https://h/FreeBSD.raw.xz; run_vmbake image verify https://h/FreeBSD.raw.xz 0123; run_vmbake image disk write b https://h/FreeBSD.raw.xz 16G; run_vmbake image disk grow b; run_vmbake image disk relabel b)
  if printf '%s\n' "$out" | grep -q "fetch -q -R -o '$TEST_DIR/cache/FreeBSD.raw.xz' 'https://h/FreeBSD.raw.xz'" && printf '%s\n' "$out" | grep -q "sha256 -q '$TEST_DIR/cache/FreeBSD.raw.xz'" && printf '%s\n' "$out" | grep -q "xz -dc '$TEST_DIR/cache/FreeBSD.raw.xz' > '$TEST_DIR/img/b/disk0.img'" && printf '%s\n' "$out" | grep -q "truncate -s '16G'" && printf '%s\n' "$out" | grep -q 'gpart recover "$md"' && printf '%s\n' "$out" | grep -q 'growfs -y "/dev/${md}p$i"' && printf '%s\n' "$out" | grep -q "gpart modify -i \"\$e\" -l 'b-efi'"; then
    pass "image base: fetch into the cache, verify, write and grow, relabel efiboot0 and rootfs"
  else
    fail "image-kind emissions: $out"
  fi
  out=$(run_vmbake image keys write x; run_vmbake image pkg base x FreeBSD:15:amd64 1501000)
  if printf '%s\n' "$out" | grep -q 'for d in /usr/share/keys/\*/; do' && printf '%s\n' "$out" | grep -q "pkg -r '$TEST_DIR/img/x/mnt' -o ABI='FreeBSD:15:amd64' -o OSVERSION='1501000' -o IGNORE_OSVERSION=yes -o ASSUME_ALWAYS_YES=yes install FreeBSD-set-minimal FreeBSD-kernel-generic FreeBSD-ssh pkg"; then
    pass "keys copied where it runs, then pkg -r with the pinned ABI and OSVERSION"
  else
    fail "keys/pkg base: $out"
  fi
  out=$(run_vmbake image boot write x)
  if printf '%s\n' "$out" | grep -q "EFI/BOOT/BOOTX64.efi" && printf '%s\n' "$out" | grep -q 'vfs.root.mountfrom="ufs:/dev/gpt/x-root"' && printf '%s\n' "$out" | grep -q "^/dev/gpt/x-efi.*noauto"; then
    pass "boot write: loader into the ESP, loader.conf and fstab on the image's labels"
  else
    fail "boot write: $out"
  fi
  out=$(run_vmbake image pkg install x FreeBSD:15:amd64 1501000; run_vmbake image rc write x)
  if printf '%s\n' "$out" | grep -q "pkg -c '$TEST_DIR/img/x/mnt' -o ABI='FreeBSD:15:amd64' .* install claude-code git && pkg -c '$TEST_DIR/img/x/mnt' clean -ay" && printf '%s\n' "$out" | grep -q "cp /etc/resolv.conf '$TEST_DIR/img/x/mnt/etc/resolv.conf'" && printf '%s\n' "$out" | grep -q '^sshd_enable="YES"$' && printf '%s\n' "$out" | grep -q '^kern_securelevel="2"$'; then
    pass "pkg install in a chroot with resolv.conf and a cleaned cache; rc write with quoted values"
  else
    fail "pkg install/rc: $out"
  fi
  out=$(run_vmbake image user make x; run_vmbake image root lock x; run_vmbake image ssh write x; run_vmbake image doas write x; run_vmbake image doas write b)
  if printf '%s\n' "$out" | grep -q "pw -R '$TEST_DIR/img/x/mnt' useradd '$(id -un)' -u '$(id -u)'" && printf '%s\n' "$out" | grep -q "ssh-ed25519 AAAATEST test@host" && printf '%s\n' "$out" | grep -q "^Port 2222$" && printf '%s\n' "$out" | grep -q "no doas in the template" && printf '%s\n' "$out" | grep -q "^permit nopass bake$" && printf '%s\n' "$out" | grep -q "pw -R '$TEST_DIR/img/x/mnt' usermod root -w no"; then
    pass "user make resolves uid host and writes the key; sshd on 2222; doas only where the template lists it"
  else
    fail "user/ssh/doas: $out"
  fi
  out=$(run_vmbake image pkg report x; run_vmbake image disk unmount x; run_vmbake image disk detach x; run_vmbake image digest write x; run_vmbake image snapshot take x; run_vmbake image readonly set x; run_vmbake image disk release x; run_vmbake image dataset destroy x)
  if printf '%s\n' "$out" | grep -q "audit -F > '$TEST_DIR/img/x/mnt/var/log/vm-bake/audit.txt'" && printf '%s\n' "$out" | grep -q "umount '$TEST_DIR/img/x/mnt/dev'" && printf '%s\n' "$out" | grep -q 'mdconfig -d -u "${md#md}"' && printf '%s\n' "$out" | grep -q "sha256 -q '$TEST_DIR/img/x/disk0.img'" && printf '%s\n' "$out" | grep -q 'zfs snapshot "$ds@image"' && printf '%s\n' "$out" | grep -q 'zfs set readonly=on "$ds"' && printf '%s\n' "$out" | grep -q 'zfs destroy -r "$ds"'; then
    pass "report into the image, unmount, detach, digest, snapshot, readonly, release, destroy in their words"
  else
    fail "close/seal/drop emissions: $out"
  fi
  run_vmbake guest record write b bake 172.16.100.250/24 > /dev/null
  out=$(run_vmbake image builder conf write x; run_vmbake image builder wait; run_vmbake image builder shutdown; run_vmbake image builder gone)
  if printf '%s\n' "$out" | grep -q "cat > '/data/vm/vm-bake/guest/bake/bake.conf'" && printf '%s\n' "$out" | grep -q "^cpu=2$" && printf '%s\n' "$out" | grep -q "^disk1_name=\"$TEST_DIR/img/x/disk0.img\"$" && printf '%s\n' "$out" | grep -q 'disk1_dev="custom"' && printf '%s\n' "$out" | grep -q "until ssh -p 2222 -i '$TEST_DIR/key'" && printf '%s\n' "$out" | grep -q "'doas shutdown -p now'" && printf '%s\n' "$out" | grep -q "pgrep -q -f 'bhyve: bake"; then
    pass "builder: conf with the image as disk1 and the builder template's resources, wait on ssh, shutdown, gone"
  else
    fail "builder emissions: $out"
  fi
}

test_image_record_lock_list() {
  test_header "image bookkeeping: record, lock, list (the sh-pinned acts of the user)"
  test_setup
  image_chain
  run_vmbake image record write freebsd-dev x > /dev/null
  if [ "$(cat "$TEST_DIR/image/x/template")" = "freebsd-dev" ] && [ -f "$TEST_DIR/image/x/created" ] && [ "$(cat "$TEST_DIR/image/x/dir")" = "/data/vm/vm-bake/image/x" ]; then
    pass "record write: template, created, dir"
  else
    fail "record: $(ls -la "$TEST_DIR/image/x" 2>&1)"
  fi
  if run_vmbake image list | grep -q "^#   x  *freebsd-dev .* open$"; then
    pass "list shows the open image"
  else
    fail "list: $(run_vmbake image list)"
  fi
  printf '%s\n' 0123456789abcdef > "$TEST_DIR/image/x/digest"
  if run_vmbake image list | grep -q "0123456789abcdef$" && [ -z "$(run_vmbake image check closed x)" ]; then
    pass "a digest closes the image for list and seal"
  else
    fail "list digest: $(run_vmbake image list)"
  fi
  run_vmbake image lock take x > /dev/null
  if [ "$(cat "$TEST_DIR/.tmp/image.lock/name")" = "x" ] && [ -z "$(run_vmbake image check lock x)" ] && run_vmbake image lock take y | grep -q "held by x"; then
    pass "lock take: held by x, a second bake is refused"
  else
    fail "lock: $(run_vmbake image lock take y)"
  fi
  run_vmbake image lock release y > /dev/null
  if [ -e "$TEST_DIR/.tmp/image.lock" ] && run_vmbake image lock release x > /dev/null && [ ! -e "$TEST_DIR/.tmp/image.lock" ]; then
    pass "lock release: only the holder's drop releases it"
  else
    fail "lock release"
  fi
  run_vmbake image record remove x > /dev/null
  if [ ! -e "$TEST_DIR/image/x" ] && run_vmbake image list | grep -q "(none)"; then
    pass "record remove"
  else
    fail "record remove: $(run_vmbake image list)"
  fi
}

test_guest_plan() {
  test_header "guests: make, start, stop, drop as plans; the records; the guards"
  test_setup
  image_chain
  run_vmbake image record write freebsd-builder b > /dev/null
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  local plan
  plan=$(run_vmbake guest make b bake 172.16.100.250/24)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "14" ] && printf '%s\n' "$plan" | grep -q "guest switch ensure" && printf '%s\n' "$plan" | grep -q "guest link write 'bake'" && printf '%s\n' "$plan" | grep -q "guest clone 'bake'" && printf '%s\n' "$plan" | sed -n 14p | grep -q "guest knownhosts drop 'bake'"; then
    pass "guest make: image checked, name, free, address, tree, switch, record, clone, conf, link, network, dns, known hosts"
  else
    fail "guest make plan: $plan"
  fi
  if [ "$(run_vmbake guest start bake | grep -c .)" = "2" ] && [ "$(run_vmbake guest stop bake | grep -c .)" = "2" ] && [ "$(run_vmbake guest drop bake | grep -c .)" = "6" ]; then
    pass "start and stop two lines, drop six"
  else
    fail "guest start/stop/drop: $(run_vmbake guest drop bake)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake guest name valid Bad_Name | grep -q "invalid guest name" && run_vmbake guest address valid 172.16.100.250 | grep -q "invalid address" && run_vmbake guest check record bake | grep -q "unknown guest bake" && [ -z "$(run_vmbake guest address valid 172.16.100.250/24)" ]; then
    pass "guest name, address and record guards"
  else
    fail "guest guards"
  fi
  run_vmbake guest record write b bake 172.16.100.250/24 > /dev/null
  if [ "$(cat "$TEST_DIR/guest/bake/image")" = "b" ] && [ "$(cat "$TEST_DIR/guest/bake/address")" = "172.16.100.250/24" ] && run_vmbake guest list | grep -q "^#   bake  *b  *172.16.100.250/24" && run_vmbake guest check absent bake | grep -q "bake exists"; then
    pass "guest record write and list"
  else
    fail "guest record: $(run_vmbake guest list)"
  fi
  if pin_image_cat; then
    pass "guest acts pinned to cat"
  else
    fail "guest acts not pinned -- not calling them"; return
  fi
  local out
  out=$(run_vmbake guest switch ensure; run_vmbake guest clone bake; run_vmbake guest conf write bake; run_vmbake guest link write bake; run_vmbake guest network write bake; run_vmbake guest dns write; run_vmbake image tree ensure)
  if printf '%s\n' "$out" | grep -q "vm switch create -t manual -b 'bridge0' 'dev'" && printf '%s\n' "$out" | grep -q 'zfs clone -o readonly=off "$src@image" "$dst/bake"' && printf '%s\n' "$out" | grep -q "^cpu=2$" && printf '%s\n' "$out" | grep -q 'network0_switch="dev"' && printf '%s\n' "$out" | grep -q "mount '/dev/gpt/b-root'" && printf '%s\n' "$out" | grep -q '^ifconfig_vtnet0="inet 172.16.100.250/24"$' && printf '%s\n' "$out" | grep -q '^defaultrouter="172.16.100.100"$' && printf '%s\n' "$out" | grep -q "ListenAddress %s.* '172.16.100.250'" && printf '%s\n' "$out" | grep -q 'local-data:     "bake.local. A 172.16.100.250"' && printf '%s\n' "$out" | grep -q "service local_unbound reload" && printf '%s\n' "$out" | grep -q "ln -sfn '/data/vm/vm-bake/guest/bake' '/data/vm/vm-bhyve/bake'" && printf '%s\n' "$out" | grep -q 'zfs create "$ds/image"'; then
    pass "switch on the bridge, clone writable, conf from the template, network into the clone by the image's label, unbound told"
  else
    fail "guest emissions: $out"
  fi
}

test_session_plan() {
  test_header "sessions: ssh and x scripts rendered from the guest record and the template's display service; X11Forwarding follows the service"
  test_setup
  image_chain
  run_vmbake template add freebsd-x freebsd-dev > /dev/null
  run_vmbake template service add freebsd-x display x > /dev/null
  run_vmbake template package add freebsd-x xauth > /dev/null
  run_vmbake image record write freebsd-dev d > /dev/null
  run_vmbake image record write freebsd-x x > /dev/null
  run_vmbake guest record write d dalmatia 172.16.100.101/24 > /dev/null
  run_vmbake guest record write x xenia 172.16.100.102/24 > /dev/null
  printf 'ssh-ed25519 AAAATEST test@host\n' > "$TEST_DIR/key.pub"
  run_vmbake setenv VM_BAKE_HOST_KEY "$TEST_DIR/key.pub" > /dev/null
  local out
  out=$(run_vmbake session create ssh dalmatia)
  if printf '%s\n' "$out" | sed -n 1p | grep -q '^#!/bin/sh$' && printf '%s\n' "$out" | grep -q "^exec ssh -p 2222 -i '$TEST_DIR/key' .* '$(id -un)@dalmatia.local' \"\$@\"$"; then
    pass "session create ssh: a script that execs ssh to <guest>.local on 2222 with the key"
  else
    fail "session ssh: $out"
  fi
  if run_vmbake session create ssh dalmatia 'claude --version' | grep -q "'$(id -un)@dalmatia.local' 'claude --version' \"\$@\"$"; then
    pass "session create ssh with a program runs it in the guest"
  else
    fail "session ssh program: $(run_vmbake session create ssh dalmatia 'claude --version')"
  fi
  if run_vmbake session create x dalmatia idea | grep -q "lists no service 'display x'"; then
    pass "session create x refuses a guest whose template lacks display x"
  else
    fail "session x guard: $(run_vmbake session create x dalmatia idea)"
  fi
  out=$(run_vmbake session create x xenia idea)
  if printf '%s\n' "$out" | grep -q "Xephyr :[0-9][0-9]* -screen '1600x1000' -dpi '96' -title 'xenia: idea' -resizeable -nolisten tcp &$" && printf '%s\n' "$out" | grep -q "^DISPLAY=:[0-9][0-9]* ssh -X -C -p 2222 -i '$TEST_DIR/key' .* '$(id -un)@xenia.local' 'idea' \"\$@\"$" && printf '%s\n' "$out" | grep -q '^wait "$xephyr"'; then
    pass "session create x: Xephyr compartment, ssh -X into it, the compartment stays until closed"
  else
    fail "session x: $out"
  fi
  if run_vmbake session create x nobody idea | grep -q "unknown guest nobody"; then
    pass "session create x refuses an unknown guest"
  else
    fail "session x unknown guest"
  fi
  if pin_image_cat; then
    pass "image acts pinned to cat"
  else
    fail "acts not pinned -- not calling them"; return
  fi
  run_vmbake setenv VM_BAKE_IMAGE_DIR "$TEST_DIR/img" > /dev/null
  if run_vmbake image ssh write x | grep -q '^X11Forwarding yes$' && ! run_vmbake image ssh write d | grep -q 'X11Forwarding'; then
    pass "ssh write adds X11Forwarding only for a template with display x"
  else
    fail "ssh write x11: $(run_vmbake image ssh write x)"
  fi
}

test_port_plan() {
  test_header "ports: the template family, burn builds and installs them in the builder only, the emissions"
  test_setup
  image_chain
  run_vmbake template add freebsd-x freebsd-dev > /dev/null
  if run_vmbake template port add freebsd-x editors/vscode | grep -q "port + editors/vscode" && run_vmbake template port add freebsd-x vscode | grep -q "invalid origin" && run_vmbake template port show freebsd-x | grep -q "^#   freebsd-x  *editors/vscode"; then
    pass "template port add validates category/name and show lists it with its origin"
  else
    fail "template port: $(run_vmbake template port show freebsd-x)"
  fi
  run_vmbake template port add freebsd-x editors/neovim > /dev/null
  run_vmbake template port drop freebsd-x editors/neovim > /dev/null
  if ! run_vmbake template port show freebsd-x | grep -q neovim && run_vmbake template dump freebsd-x | grep -q "template port add 'freebsd-x' 'editors/vscode'"; then
    pass "port drop removes the own line; the dump replays port add"
  else
    fail "port drop/dump: $(run_vmbake template dump freebsd-x | grep port)"
  fi
  run_vmbake image record write freebsd-x x > /dev/null
  run_vmbake image record write freebsd-dev d > /dev/null
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  printf 'builder\n' > "$TEST_DIR/.env/local/VM_BAKE_BAKE_IN"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  local plan
  plan=$(run_vmbake image burn x)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "11" ] && printf '%s\n' "$plan" | sed -n 4p | grep -q "image port build 'x'" && printf '%s\n' "$plan" | sed -n 5p | grep -q "image port install 'x'" && [ "$(run_vmbake image burn d | grep -c .)" = "9" ]; then
    pass "burn in the builder: port build and install after the packages, only when ports are listed"
  else
    fail "burn ports plan: $plan"
  fi
  printf 'host\n' > "$TEST_DIR/.env/local/VM_BAKE_BAKE_IN"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake image burn x | grep -q "ports build in the builder only" && [ "$(run_vmbake image burn d | grep -c .)" = "9" ]; then
    pass "burn on the host refuses listed ports with an error line"
  else
    fail "burn host ports: $(run_vmbake image burn x)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if pin_image_cat; then
    pass "image acts pinned to cat"
  else
    fail "acts not pinned -- not calling them"; return
  fi
  run_vmbake setenv VM_BAKE_IMAGE_DIR "$TEST_DIR/img" > /dev/null
  local out
  out=$(run_vmbake image port build x; run_vmbake image port install x)
  if printf '%s\n' "$out" | grep -q "git clone -q --depth 1 -b 'main' https://git.FreeBSD.org/ports.git /usr/ports" && printf '%s\n' "$out" | grep -q "make -C '/usr/ports/editors/vscode' -V PKGNAME" && printf '%s\n' "$out" | grep -q "make -C '/usr/ports/editors/vscode' BATCH=yes package" && printf '%s\n' "$out" | grep -q "pkg -c '$TEST_DIR/img/x/mnt' -o ASSUME_ALWAYS_YES=yes add \"/var/cache/vm-bake/\$n.pkg\""; then
    pass "port build clones the tree, builds missing packages; port install adds the package into the image"
  else
    fail "port emissions: $out"
  fi
  if run_vmbake image port build d | grep -q "lists no ports"; then
    pass "a template without ports is a note"
  else
    fail "port build without ports: $(run_vmbake image port build d)"
  fi
}

test_pkgfile_plan() {
  test_header "package files: the template family, burn checks, stages and adds them by VM_BAKE_BAKE_IN, the emissions"
  test_setup
  image_chain
  run_vmbake template add freebsd-x freebsd-dev > /dev/null
  if run_vmbake template pkgfile add freebsd-x vscode-1.130.0.pkg | grep -q "pkgfile + vscode-1.130.0.pkg" && run_vmbake template pkgfile add freebsd-x /tmp/x.pkg | grep -q "invalid file name" && run_vmbake template pkgfile add freebsd-x vscode | grep -q "invalid file name" && run_vmbake template pkgfile show freebsd-x | grep -q "^#   freebsd-x  *vscode-1.130.0.pkg"; then
    pass "template pkgfile add validates a bare .pkg name and show lists it"
  else
    fail "template pkgfile: $(run_vmbake template pkgfile show freebsd-x)"
  fi
  run_vmbake image record write freebsd-x x > /dev/null
  run_vmbake image record write freebsd-dev d > /dev/null
  run_vmbake setenv VM_BAKE_PKG_DIR "$TEST_DIR/pkg" > /dev/null
  if pin_image_cat; then
    pass "image acts pinned to cat"
  else
    fail "acts not pinned -- not calling them"; return
  fi
  if run_vmbake image check pkgfiles x | grep -q "package file missing in $TEST_DIR/pkg: vscode-1.130.0.pkg"; then
    pass "check pkgfiles names a missing file"
  else
    fail "check pkgfiles: $(run_vmbake image check pkgfiles x)"
  fi
  mkdir -p "$TEST_DIR/pkg" && : > "$TEST_DIR/pkg/vscode-1.130.0.pkg"
  if [ -z "$(run_vmbake image check pkgfiles x)" ]; then
    pass "check pkgfiles passes once the file is there"
  else
    fail "check pkgfiles present: $(run_vmbake image check pkgfiles x)"
  fi
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  printf 'builder\n' > "$TEST_DIR/.env/local/VM_BAKE_BAKE_IN"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  local plan
  plan=$(run_vmbake image burn x)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "12" ] && printf '%s\n' "$plan" | sed -n 4p | grep -q "image check pkgfiles 'x'" && printf '%s\n' "$plan" | sed -n 5p | grep -q "image pkgfile stage 'x'" && printf '%s\n' "$plan" | sed -n 6p | grep -q "image pkgfile add 'x'" && [ "$(run_vmbake image burn d | grep -c .)" = "9" ] && run_vmbake image pkgfile stage x | grep -q "streamed into the builder"; then
    pass "burn: check, stage and add after the packages, only when files are listed; stage chooses by the place"
  else
    fail "burn pkgfile plan: $plan"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  run_vmbake setenv VM_BAKE_IMAGE_DIR "$TEST_DIR/img" > /dev/null
  printf 'ssh-ed25519 AAAATEST test@host\n' > "$TEST_DIR/key.pub"
  run_vmbake setenv VM_BAKE_HOST_KEY "$TEST_DIR/key.pub" > /dev/null
  local out
  out=$(run_vmbake image pkgfile stage host x; run_vmbake image pkgfile stage builder x; run_vmbake image pkgfile add x)
  if printf '%s\n' "$out" | grep -q "cp '$TEST_DIR/pkg/vscode-1.130.0.pkg' '$TEST_DIR/img/x/mnt/var/cache/vm-bake/'" && printf '%s\n' "$out" | grep -q "ssh -p 2222 -i '$TEST_DIR/key' .* 'bake@172.16.100.250' \"doas sh -c .*cat > '$TEST_DIR/img/x/mnt/var/cache/vm-bake/vscode-1.130.0.pkg'.*\" < '$TEST_DIR/pkg/vscode-1.130.0.pkg'" && printf '%s\n' "$out" | grep -q "pkg -c '$TEST_DIR/img/x/mnt' -o ASSUME_ALWAYS_YES=yes add '/var/cache/vm-bake/vscode-1.130.0.pkg' && rm -f" && printf '%s\n' "$out" | grep -q "query -F '/var/cache/vm-bake/vscode-1.130.0.pkg' %dn"; then
    pass "stage host copies, stage builder streams over ssh into the builder's mount, add installs in the chroot and removes the copy"
  else
    fail "pkgfile emissions: $out"
  fi
}

test_tag_plan() {
  test_header "tags: the template family inherited and masked, the guest's own tags, find over both"
  test_setup
  image_chain
  run_vmbake template tag add freebsd-dev purpose 'development on FreeBSD with Claude Code' > /dev/null
  run_vmbake template tag add freebsd-dev can claude > /dev/null
  run_vmbake template add freebsd-x freebsd-dev > /dev/null
  run_vmbake template tag add freebsd-x can intellij > /dev/null
  run_vmbake template tag add freebsd-x can vscode > /dev/null
  if run_vmbake template tag show freebsd-x | grep -q "^#   freebsd-dev  *purpose development on FreeBSD with Claude Code" && run_vmbake template tag show freebsd-x | grep -q "^#   freebsd-x  *can intellij" && run_vmbake template tag add freebsd-x 'bad key' x | grep -q "not a plain word"; then
    pass "template tag add stores key and text, show resolves the chain with origins, the key is a word"
  else
    fail "template tag show: $(run_vmbake template tag show freebsd-x)"
  fi
  run_vmbake template tag mask freebsd-x can claude > /dev/null
  run_vmbake template tag drop freebsd-x can vscode > /dev/null
  if ! run_vmbake template tag show freebsd-x | grep -q "can claude" && ! run_vmbake template tag show freebsd-x | grep -q "can vscode" && run_vmbake template tag show freebsd-dev | grep -q "can claude"; then
    pass "mask hides the inherited tag below, drop removes the own one"
  else
    fail "tag mask/drop: $(run_vmbake template tag show freebsd-x)"
  fi
  if run_vmbake template find can intellij | grep -q "^#   freebsd-x  *freebsd-x  *can intellij" && run_vmbake template find can claude | grep -q "^#   freebsd-dev " && ! run_vmbake template find can claude | grep -q "^#   freebsd-x " && run_vmbake template find owner . | grep -q "(none)"; then
    pass "template find matches key and pattern over the resolved tags, masks respected"
  else
    fail "template find: $(run_vmbake template find can intellij; run_vmbake template find can claude)"
  fi
  run_vmbake image record write freebsd-x x > /dev/null
  run_vmbake image record write freebsd-dev d > /dev/null
  run_vmbake guest record write x caledonia 172.16.100.102/24 > /dev/null
  run_vmbake guest record write d dalmatia 172.16.100.101/24 > /dev/null
  run_vmbake guest tag add caledonia owner JB > /dev/null
  run_vmbake guest tag add caledonia note 'first X guest' > /dev/null
  if run_vmbake guest tag show caledonia | grep -q "^#   caledonia  *owner JB" && run_vmbake guest tag show caledonia | grep -q "^#   freebsd-x  *can intellij" && run_vmbake guest tag show caledonia | grep -q "^#   freebsd-dev  *purpose "; then
    pass "guest tag show lists own tags and the template's with origins"
  else
    fail "guest tag show: $(run_vmbake guest tag show caledonia)"
  fi
  if run_vmbake guest tag drop caledonia owner XX | grep -q "no own tag" && run_vmbake guest tag drop caledonia owner JB > /dev/null && ! run_vmbake guest tag show caledonia | grep -q "owner JB"; then
    pass "guest tag drop removes an own tag and refuses an unknown one"
  else
    fail "guest tag drop: $(run_vmbake guest tag show caledonia)"
  fi
  if run_vmbake guest find can intellij | grep -q "^#   caledonia  *x  *freebsd-x  *can intellij" && ! run_vmbake guest find can intellij | grep -q dalmatia && run_vmbake guest find purpose claude | grep -q caledonia && run_vmbake guest find purpose claude | grep -q dalmatia && run_vmbake guest find note 'first' | grep -q "^#   caledonia  *x  *caledonia  *note first X guest"; then
    pass "guest find answers from own and inherited tags, by key and pattern"
  else
    fail "guest find: $(run_vmbake guest find can intellij; run_vmbake guest find purpose claude)"
  fi
  if run_vmbake template dump freebsd-x | grep -q "template tag add 'freebsd-x' 'can' 'intellij'"; then
    pass "the dump replays tag add with key and text"
  else
    fail "dump tags: $(run_vmbake template dump freebsd-x | grep tag)"
  fi
}

test_env_plan() {
  test_header "env: the template family, written into the image as profile.d, handed to the x session's program; the compartment's window manager and cursor"
  test_setup
  image_chain
  run_vmbake template add freebsd-x freebsd-dev > /dev/null
  run_vmbake template service add freebsd-x display x > /dev/null
  run_vmbake template env add freebsd-dev LANG C.UTF-8 > /dev/null
  run_vmbake template env add freebsd-x XCURSOR_THEME redglass > /dev/null
  if run_vmbake template env show freebsd-x | grep -q "^#   freebsd-dev  *LANG=C.UTF-8" && run_vmbake template env show freebsd-x | grep -q "^#   freebsd-x  *XCURSOR_THEME=redglass" && run_vmbake template env add freebsd-x 'bad name' x | grep -q "invalid variable name"; then
    pass "template env add stores VAR=value, show resolves the chain, the name is validated"
  else
    fail "template env show: $(run_vmbake template env show freebsd-x)"
  fi
  run_vmbake image record write freebsd-x x > /dev/null
  run_vmbake image record write freebsd-dev d > /dev/null
  run_vmbake image record write freebsd-builder b > /dev/null
  run_vmbake guest record write x caledonia 172.16.100.102/24 > /dev/null
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake image burn x | grep -q "image env write 'x'"; then
    pass "burn writes the env after rc"
  else
    fail "burn env: $(run_vmbake image burn x)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if pin_image_cat; then
    pass "image acts pinned to cat"
  else
    fail "acts not pinned -- not calling them"; return
  fi
  run_vmbake setenv VM_BAKE_IMAGE_DIR "$TEST_DIR/img" > /dev/null
  printf 'ssh-ed25519 AAAATEST test@host\n' > "$TEST_DIR/key.pub"
  run_vmbake setenv VM_BAKE_HOST_KEY "$TEST_DIR/key.pub" > /dev/null
  run_vmbake setenv VM_BAKE_XCURSOR_THEME redglass > /dev/null
  local out
  out=$(run_vmbake image env write x)
  if printf '%s\n' "$out" | grep -q "cat > '$TEST_DIR/img/x/mnt/etc/profile.d/vm-bake.sh'" && printf '%s\n' "$out" | grep -q '^export LANG="C.UTF-8"$' && printf '%s\n' "$out" | grep -q '^export XCURSOR_THEME="redglass"$' && run_vmbake image env write b | grep -q "no environment variables"; then
    pass "env write renders profile.d/vm-bake.sh with exports, nothing for an empty list"
  else
    fail "env write: $out"
  fi
  out=$(run_vmbake session create x caledonia 'code-oss --disable-gpu')
  if printf '%s\n' "$out" | grep -q "^XCURSOR_THEME='redglass' Xephyr :[0-9]* " && printf '%s\n' "$out" | grep -q "^DISPLAY=:[0-9]* ratpoison > /dev/null 2>&1 &$" && printf '%s\n' "$out" | grep -q "ssh -X -C -p 2222 .* 'env LANG=C.UTF-8 XCURSOR_THEME=redglass code-oss --disable-gpu' \"\$@\"$" && printf '%s\n' "$out" | grep -q '^kill "$wm"'; then
    pass "session x: cursor theme for the server, the window manager in the compartment, ssh -C, the program under the template's env"
  else
    fail "session x env: $out"
  fi
  run_vmbake setenv VM_BAKE_XEPHYR_WM none > /dev/null
  if ! run_vmbake session create x caledonia idea | grep -q 'wm='; then
    pass "VM_BAKE_XEPHYR_WM none starts no window manager"
  else
    fail "wm empty: $(run_vmbake session create x caledonia idea)"
  fi
}

# ============================================================================

parallel_main() {
  local outdir rc=0 t
  outdir=$(mktemp -d "${TMPDIR:-/tmp}/vm-bake-unit-par.XXXXXX") || exit 1
  echo "${COLOR_BLUE}vm-bake Unit Test Suite (parallel, -P $MAXPROCS)${COLOR_RESET}"
  echo ""
  local tests
  if [ "$TEST_FILTER" = "$ALL_TESTS" ]; then
    tests=$(grep -E '^[[:space:]]*should_run_test ' "$0" | awk '{print $2}')
  else
    tests="$TEST_FILTER"
  fi
  printf '%s\n' $tests | xargs -n1 -P "$MAXPROCS" \
    sh -c 'sh "$0" --maxprocs 1 "$1" "$2" "$4" > "$3/$4.out" 2>&1; echo $? > "$3/$4.rc"' \
    "$0" "$TEST_PROFILE" "$KEEP_DATABASES" "$outdir"
  for t in $tests; do
    cat "$outdir/$t.out" 2>/dev/null
    [ "$(cat "$outdir/$t.rc" 2>/dev/null)" = "0" ] || rc=1
  done
  echo ""
  echo "========================================"
  echo "Aggregated Summary (parallel run)"
  echo "========================================"
  awk '
    /^Test Functions:/    { tf += $3 }
    /^Total Assertions:/  { ta += $3 }
    /^Passed Assertions:/ { pa += $3 }
    /^Failed Assertions:/ { fa += $3 }
    END {
      printf "Test Functions:     %d\n", tf
      printf "Total Assertions:   %d\n", ta
      printf "Passed Assertions:  %d\n", pa
      printf "Failed Assertions:  %d\n", fa
    }' "$outdir"/*.out
  if [ "$rc" -eq 0 ]; then
    echo ""; echo "ALL TESTS PASSED"; rm -rf "$outdir"
  else
    echo ""; echo "SOME TESTS FAILED"; echo "Per-test outputs preserved in: $outdir"
  fi
  return $rc
}

main() {
  if [ "$MAXPROCS" -gt 1 ]; then
    parallel_main
    return $?
  fi
  echo "${COLOR_BLUE}========================================${COLOR_RESET}"
  echo "${COLOR_BLUE}vm-bake Unit Test Suite${COLOR_RESET}"
  echo "${COLOR_BLUE}========================================${COLOR_RESET}"
  [ -f "$TEST_SCRIPT" ] || { echo "ERROR: $TEST_SCRIPT not found (run from the repository root)"; exit 1; }

  should_run_test test_bootstrap_layout
  should_run_test test_template_add_chain
  should_run_test test_template_scalars
  should_run_test test_template_lists
  should_run_test test_template_drop_guards
  should_run_test test_template_dump_restore
  should_run_test test_dispatch_and_help
  should_run_test test_inspect_by_default
  should_run_test test_image_plan
  should_run_test test_image_guards
  should_run_test test_image_emissions
  should_run_test test_image_record_lock_list
  should_run_test test_guest_plan
  should_run_test test_session_plan
  should_run_test test_port_plan
  should_run_test test_pkgfile_plan
  should_run_test test_tag_plan
  should_run_test test_env_plan

  test_summary
}

main
exit $?
