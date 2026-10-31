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
  VM_BAKE_BASE="$TEST_DIR" "$TEST_SCRIPT" setintp terminal sh > /dev/null 2>&1
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
  run_vmbake template base image debian amd64 https://cloud.debian.org/x.qcow2 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef > /dev/null
  run_vmbake template add windows > /dev/null
  run_vmbake template base iso windows amd64 /data/iso/win.iso 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef > /dev/null
  if [ "$(cat "$(record_of freebsd)/base")" = "stage amd64 daily-v1" ] && grep -q '^image amd64 https://cloud.debian.org/x.qcow2 0123' "$(record_of debian)/base" && grep -q '^iso amd64 /data/iso/win.iso 0123' "$(record_of windows)/base"; then
    pass "base stage, image and iso record their variant"
  else
    fail "base variants: $(cat "$(record_of freebsd)/base" "$(record_of debian)/base" "$(record_of windows)/base" 2>&1)"
  fi
  if run_vmbake template base image debian amd64 ftp://x 0123 | grep -q "invalid url" && run_vmbake template base iso windows amd64 relative/win.iso 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef | grep -q "invalid path"; then
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
  VM_BAKE_BASE="$second" "$TEST_SCRIPT" setintp terminal sh > /dev/null 2>&1
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
  VM_BAKE_BASE="$TEST_DIR" "$TEST_SCRIPT" setintp terminal cat > /dev/null 2>&1
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

  test_summary
}

main
exit $?
