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

# The home lines of a template name paths under the invoking user's home,
# and the generators read that home (~user, not a sandbox) at generation
# time: so the tests take their home paths from a fixture directory the
# suite makes in the real home and removes on exit, never from the
# dotfiles that happen to be there.
HOME_FIXTURE=".vm-bake-unit-test.$$"
home_fixture() {
  mkdir -p "$HOME/$HOME_FIXTURE/config/gtk-3.0" "$HOME/$HOME_FIXTURE/cache" "$HOME/$HOME_FIXTURE/db" "$HOME/$HOME_FIXTURE/themes/NsCDE" "$HOME/$HOME_FIXTURE/ssh"
}
trap 'rm -rf "$HOME/$HOME_FIXTURE"' EXIT

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
  home_fixture
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
  local prof shown
  prof=$(ls "$TEST_DIR/.env/default" | sed -n 's/^VM_BAKE_PROFILE_//p' | tr '[:upper:]' '[:lower:]')
  shown=$(run_vmbake profile show)
  if [ -n "$prof" ] && printf '%s\n' "$shown" | grep -q "^# profile $prof: [0-9]* variables listed, [0-9]* held in .env/default, [0-9]* shipped by this vm-bake$" && ! printf '%s\n' "$shown" | grep -q "not installed"; then
    pass "profile show names the database's profile $prof, listed, held and shipped counts agree after bootstrap"
  else
    fail "profile show: $shown"
  fi
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  mv "$TEST_DIR/.env/default/VM_BAKE_PROFILE_$(printf '%s' "$prof" | tr '[:lower:]' '[:upper:]')" "$TEST_DIR/profile.away"
  local none
  none=$(run_vmbake environment init; run_vmbake profile show)
  mv "$TEST_DIR/profile.away" "$TEST_DIR/.env/default/VM_BAKE_PROFILE_$(printf '%s' "$prof" | tr '[:lower:]' '[:upper:]')"
  if run_vmbake environment init | grep -q "environment init '$prof'\$" && printf '%s\n' "$none" | grep -q "error 'environment init: no profile installed" && printf '%s\n' "$none" | grep -q "^# profile: none installed"; then
    pass "environment init without a profile rewrites to the database's own, an error when none is installed"
  else
    fail "environment init: $(run_vmbake environment init) / $none"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
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
  run_vmbake template package unmask freebsd-dev emacs > /dev/null
  if run_vmbake template package show freebsd-dev | grep -q emacs && run_vmbake template package unmask freebsd-dev emacs | grep -q "does not mask emacs"; then
    pass "unmask takes the mask back, and without a mask it is an error"
  else
    fail "unmask: $(run_vmbake template package show freebsd-dev)"
  fi
  run_vmbake template package mask freebsd-dev emacs > /dev/null
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
  run_vmbake template add freebsd-y freebsd-dev > /dev/null
  run_vmbake template rc mask freebsd-y linux_enable YES > /dev/null
  run_vmbake template user mask freebsd-y brj host > /dev/null
  run_vmbake template service mask freebsd-y display x > /dev/null
  run_vmbake template forbid mask freebsd-y usb > /dev/null
  run_vmbake template forbid mask freebsd-y net 192.168.1.0/24 > /dev/null
  run_vmbake template data mask freebsd-y home 64G proton > /dev/null
  run_vmbake template session mask freebsd-y ssh > /dev/null
  run_vmbake template rc unmask freebsd-y linux_enable YES > /dev/null
  run_vmbake template user unmask freebsd-y brj host > /dev/null
  run_vmbake template service unmask freebsd-y display x > /dev/null
  run_vmbake template forbid unmask freebsd-y usb > /dev/null
  run_vmbake template forbid unmask freebsd-y net 192.168.1.0/24 > /dev/null
  run_vmbake template data unmask freebsd-y home 64G proton > /dev/null
  run_vmbake template session unmask freebsd-y ssh > /dev/null
  local y; y=$(record_of freebsd-y)
  if [ -z "$(cd "$y" && cat rc.mask user.mask service.mask forbid.mask data.mask session.mask 2>/dev/null)" ] && run_vmbake template dump record freebsd-y | grep -vq mask; then
    pass "every family takes its mask back, with and without an argument, and the dump holds none"
  else
    fail "unmask over the families: $(cd "$y" && grep . ./*.mask 2>&1)"
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
IMAGE_ACTS="lock_take lock_drop lock_release tree_ensure dataset_create dataset_destroy fetch verify disk_write disk_place seed_meta_write seed_net_write seed_user_write seed_sshd_write seed_view_write seed_pack firstboot_conf_write firstboot_gone firstboot_conf_drop response_write site_write site_pack console_drive_tmux console_drive_nmdm disk_create disk_attach disk_partition disk_format disk_grow disk_relabel disk_mount keys_write pkg_base repo_write boot_write pkg_install pkgfile_stage_host pkgfile_stage_builder pkgfile_add port_build port_install rc_write env_write user_make view_write root_lock doas_write ssh_write pkg_report disk_unmount disk_detach disk_release digest_write snapshot_take readonly_set builder_conf_write builder_wait builder_shutdown builder_gone"
GUEST_ACTS="switch_ensure clone conf_write link_write link_drop disk_release network_write seed_write_cloud_init seed_write_autoinstall home_write hostkey_bind hostkey_unbind hostkey_write dns_write knownhosts_drop run install halt gone dataset_destroy view_tree_ensure view_ensure view_mount view_unmount view_destroy repo_clone repo_refs repo_merge repo_remove repo_show repo_tree_ensure repo_mirror repo_record repo_unrecord repo_wait fetched_write fetched_drop report_place dowry_place_idem dowry_place_overwrite vmm_release log_rotate_ensure"
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
  plan=$(run_vmbake image make freebsd freebsd-x v1 img:ides:v1)
  if [ "$(printf '%s\n' "$plan" | grep -c '"\$VM_BAKE_CONTEXT_SCRIPT"')" = "9" ] && printf '%s\n' "$plan" | sed -n 1p | grep -q "note 'image make freebsd: template freebsd-x, version v1 -> image img:ides:v1" && printf '%s\n' "$plan" | grep -q "image name valid 'img:ides:v1'" && printf '%s\n' "$plan" | grep -q "image check absent 'img:ides:v1'" && printf '%s\n' "$plan" | grep -q "image create 'freebsd-x' 'img:ides:v1'" && printf '%s\n' "$plan" | sed -n 9p | grep -q "image seal 'img:ides:v1'"; then
    pass "make freebsd with a name of its own: announced, template checked, name valid and free, then create, base, burn, close, seal"
  else
    fail "make plan: $plan"
  fi
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake image make freebsd freebsd-dev v2 | grep -q "image make freebsd from 'freebsd-dev' 'v2' 'img:freebsd-dev:v2'" && run_vmbake image make freebsd img:freebsd-dev:v3 | grep -q "image make freebsd from 'freebsd-dev' 'v3' 'img:freebsd-dev:v3'" && run_vmbake image make freebsd freebsd-x v1 img:ides:v1 | grep -q "image make freebsd from 'freebsd-x' 'v1' 'img:ides:v1'"; then
    pass "the three spellings meet in 'image make freebsd from': template and version compose img:<template>:<version>, the full name is read apart, a name of its own passes through"
  else
    fail "make freebsd spellings: $(run_vmbake image make freebsd freebsd-dev v2; run_vmbake image make freebsd img:freebsd-dev:v3)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
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
  if run_vmbake image base content x | sed -n 1p | grep -q "image check pkgbase place"; then
    pass "the release content asks first where pkgbase may be installed"
  else
    fail "pkgbase place guard missing: $(run_vmbake image base content x)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER"
  printf 'builder\n' > "$TEST_DIR/.env/local/VM_BAKE_BAKE_IN"
  if run_vmbake image check pkgbase place | grep -q "comment 'pkgbase can be installed in builder"; then
    pass "in the builder the answer is yes whatever this host's securelevel is"
  else
    fail "pkgbase place in the builder: $(run_vmbake image check pkgbase place)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  printf 'host\n' > "$TEST_DIR/.env/local/VM_BAKE_BAKE_IN"
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
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
  if printf '%s\n' "$plan" | grep -q "image check users 'x'" && printf '%s\n' "$plan" | grep -q "image root lock 'x'" && printf '%s\n' "$plan" | grep -q "image view write 'x'" && [ "$(printf '%s\n' "$plan" | grep -c .)" = "10" ]; then
    pass "burn: users checked, then packages, rc, users, the view, root locked, doas, sshd"
  else
    fail "burn plan: $plan"
  fi
  if [ "$(run_vmbake image close x | grep -c .)" = "6" ] && [ "$(run_vmbake image seal x | grep -c .)" = "6" ] && [ "$(run_vmbake image drop x | grep -c .)" = "5" ] && run_vmbake image drop x | grep -q "image dataset destroy 'x'"; then
    pass "close and seal six lines each, drop five: release, destroy, record, lock"
  else
    fail "close/seal/drop plan: $(run_vmbake image close x; run_vmbake image seal x; run_vmbake image drop x)"
  fi
  plan=$(run_vmbake image builder use)
  if printf '%s\n' "$plan" | sed -n 1p | grep -q "setenv VM_BAKE_BAKE_IN builder" && [ "$(printf '%s\n' "$plan" | grep -c "setintp image_")" = "18" ] && printf '%s\n' "$plan" | grep -q "setintp image_pkg_base 'ssh -p 2222 -i .* bake@172.16.100.250 doas sh'" && [ "$(run_vmbake image builder leave | grep -c "unsetintp image_")" = "18" ]; then
    pass "builder use and leave: the place and eighteen pins, each a setintp or unsetintp line"
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
  if run_vmbake image name valid 'img:bad name:v1' | grep -q "invalid image name" && run_vmbake image name valid img:a-name-of-twenty-characters:v1 | grep -q "invalid image name" && run_vmbake image name valid freebsd-dev-20261107 | grep -q "invalid image name" && run_vmbake image name valid img:freebsd-dev | grep -q "invalid image name" && [ -z "$(run_vmbake image name valid img:freebsd-dev:v1)" ] && [ -z "$(run_vmbake image name valid img:ides.2026:v20261107)" ]; then
    pass "image names are img:<name>:<version>, two words joined by the one separator, at most 30 characters"
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
  if printf '%s\n' "$out" | grep -q "gpart add -t efi -s 260M -a 1m -l 'x-efi'" && printf '%s\n' "$out" | grep -q "gpart add -t freebsd-ufs -a 1m -l 'x-root'" && printf '%s\n' "$out" | grep -q "newfs -j '/dev/gpt/x-root'" && printf '%s\n' "$out" | grep -q "mount -t ufs '/dev/gpt/x-root' '$TEST_DIR/img/x/mnt'" && printf '%s\n' "$out" | grep -q "mount -t msdosfs '/dev/gpt/x-efi'" && printf '%s\n' "$out" | grep -q "mount -t devfs devfs '$TEST_DIR/img/x/mnt/dev'"; then
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
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "19" ] && printf '%s\n' "$plan" | sed -n 6p | grep -q "guest repo tree ensure" && printf '%s\n' "$plan" | sed -n 7p | grep -q "guest check homes 'bake'" && printf '%s\n' "$plan" | grep -q "guest switch ensure" && printf '%s\n' "$plan" | grep -q "guest log rotate ensure" && printf '%s\n' "$plan" | grep -q "guest hostkey ensure 'bake'" && printf '%s\n' "$plan" | grep -q "guest view ensure 'bake'" && printf '%s\n' "$plan" | grep -q "guest disk write 'bake'" && printf '%s\n' "$plan" | grep -q "guest link write 'bake'" && printf '%s\n' "$plan" | grep -q "guest clone 'bake'" && printf '%s\n' "$plan" | sed -n 19p | grep -q "guest knownhosts drop 'bake'"; then
    pass "guest make: image checked, name, free, address, mirrors' directory, homes, tree, switch, log rotation, record, host key, view, clone, conf, link, disk (network, home and host key by the bake), dns, known hosts"
  else
    fail "guest make plan: $plan"
  fi
  if [ "$(run_vmbake guest start bake | grep -c .)" = "10" ] && printf '%s\n' "$(run_vmbake guest start bake)" | sed -n 2p | grep -q "guest check stopped" && printf '%s\n' "$(run_vmbake guest start bake)" | sed -n 3p | grep -q "guest repo tree ensure" && printf '%s\n' "$(run_vmbake guest start bake)" | sed -n 4p | grep -q "guest check homes 'bake'" && printf '%s\n' "$(run_vmbake guest start bake)" | grep -n "guest fetched drop\|guest run\|guest repo ensure" | tr '\n' ' ' | grep -q "8:.*fetched drop.* 9:.*guest run.* 10:.*repo ensure" && [ "$(run_vmbake guest stop bake | grep -c .)" = "6" ] && printf '%s\n' "$(run_vmbake guest stop bake)" | sed -n 2p | grep -q "guest repo hold" && printf '%s\n' "$(run_vmbake guest stop bake)" | sed -n 5p | grep -q "guest vmm release" && [ "$(run_vmbake guest drop bake | grep -c .)" = "10" ]; then
    pass "start ten lines, the running check second (before any mount and its sudo), the mirrors' directory third, the mark dropped before vm start and the clones ensured after; stop six with the hold first and the vm instance released; drop ten"
  else
    fail "guest start/stop/drop: $(run_vmbake guest drop bake)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake guest name valid Bad_Name | grep -q "invalid guest name" && run_vmbake guest address valid 172.16.100.250 | grep -q "invalid address" && run_vmbake guest check record bake | grep -q "unknown guest bake" && [ -z "$(run_vmbake guest address valid 172.16.100.250/24)" ]; then
    pass "guest name, address and record guards"
  else
    fail "guest guards"
  fi
  if [ -z "$(run_vmbake guest check stopped bake)" ] && printf 'x\n' > "$TEST_DIR/guest-dir-probe" && mkdir -p "$TEST_DIR/vmdir/bake" && printf 'x\n' > "$TEST_DIR/vmdir/bake/run.lock" && run_vmbake setenv VM_BAKE_GUEST_DIR "$TEST_DIR/vmdir" > /dev/null && run_vmbake guest check stopped bake | grep -q "run.lock in $TEST_DIR/vmdir/bake"; then
    pass "check stopped names the run.lock, and is silent when nothing of the guest is left running"
  else
    fail "check stopped: $(run_vmbake guest check stopped bake)"
  fi
  run_vmbake unsetenv VM_BAKE_GUEST_DIR > /dev/null
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
  if printf '%s\n' "$out" | grep -q "vm switch create -t manual -b 'bridge0' 'dev'" && printf '%s\n' "$out" | grep -q 'zfs clone -o readonly=off "$src@image" "$dst/bake"' && printf '%s\n' "$out" | grep -q "^cpu=2$" && printf '%s\n' "$out" | grep -q 'network0_switch="dev"' && printf '%s\n' "$out" | grep -q '^debug="yes"$' && printf '%s\n' "$out" | grep -q "mount -t ufs '/dev/gpt/b-root'" && printf '%s\n' "$out" | grep -q '^ifconfig_vtnet0="inet 172.16.100.250/24"$' && printf '%s\n' "$out" | grep -q '^defaultrouter="172.16.100.100"$' && printf '%s\n' "$out" | grep -q "ListenAddress %s.* '172.16.100.250'" && printf '%s\n' "$out" | grep -q 'local-data:     "bake.local. A 172.16.100.250"' && printf '%s\n' "$out" | grep -q "service local_unbound reload" && printf '%s\n' "$out" | grep -q "ln -sfn '/data/vm/vm-bake/guest/bake' '/data/vm/vm-bhyve/bake'" && printf '%s\n' "$out" | grep -q 'zfs create "$ds/image"'; then
    pass "switch on the bridge, clone writable, conf from the template, network into the clone by the image's label, unbound told"
  else
    fail "guest emissions: $out"
  fi
  if printf '%s\n' "$out" | grep -q '^cpu_sockets=1$' && printf '%s\n' "$out" | grep -q '^cpu_cores=2$' && printf '%s\n' "$out" | grep -q '^cpu_threads=1$'; then
    pass "without a topology record the cpus are one socket of <cpu> cores with one thread each"
  else
    fail "default topology: $(run_vmbake guest conf write bake)"
  fi
  run_vmbake template topology freebsd-builder 2 1 1 > /dev/null
  if run_vmbake guest conf write bake | grep -q '^cpu_sockets=2$' && run_vmbake guest conf write bake | grep -q '^cpu_cores=1$'; then
    pass "a topology record of the template is written as it says"
  else
    fail "topology record: $(run_vmbake guest conf write bake)"
  fi
  run_vmbake template topology drop freebsd-builder > /dev/null
  run_vmbake template topology freebsd-builder 3 3 1 > /dev/null
  if run_vmbake guest conf write bake | grep -q "whose product is not the cpu count 2"; then
    pass "a topology whose product is not the cpu count is an error at generation time"
  else
    fail "topology guard: $(run_vmbake guest conf write bake)"
  fi
  run_vmbake template topology drop freebsd-builder > /dev/null
}

test_session_plan() {
  test_header "sessions: ssh, xterm (both with a program, both under screen) and x scripts rendered from the guest record and the template's display service; X11Forwarding follows the service"
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
  local lc
  lc="'$(id -un)@dalmatia.local' 'sh -lc '\\''claude --version \"\$@\"'\\'' sh' \"\$@\""
  if run_vmbake session create ssh dalmatia 'claude --version' | grep -q "^exec ssh -t -p 2222 .* '$(id -un)@dalmatia.local' " && run_vmbake session create ssh dalmatia 'claude --version' | grep -qF -- "$lc"; then
    pass "session create ssh with a program runs it in the guest with a pseudo-terminal (-t), in a login shell (sh -lc), the script's arguments appended"
  else
    fail "session ssh program: $(run_vmbake session create ssh dalmatia 'claude --version')"
  fi
  run_vmbake template env add freebsd-dev CLAUDE_CODE_DISABLE_MOUSE 1 > /dev/null
  lc="'sh -lc '\\''export CLAUDE_CODE_DISABLE_MOUSE=\"1\"; claude \"\$@\"'\\'' sh' \"\$@\""
  if run_vmbake session create ssh dalmatia claude | grep -qF -- "$lc" && run_vmbake session create ssh dalmatia | grep -q "'$(id -un)@dalmatia.local' \"\$@\"$"; then
    pass "the template's env lines are exported in the login shell before the program; a session without a program is the login itself"
  else
    fail "session env: $(run_vmbake session create ssh dalmatia claude)"
  fi
  run_vmbake template env drop freebsd-dev CLAUDE_CODE_DISABLE_MOUSE 1 > /dev/null
  lc="'sh -lc '\\''cd git/Infrastruktur && exec /usr/local/bin/claude --resume \"\$@\"'\\'' sh' \"\$@\""
  if run_vmbake session create ssh dalmatia claude screen | grep -q "^exec screen -dR -S 'claude@dalmatia' ssh -t -p 2222 .* '$(id -un)@dalmatia.local' 'sh -lc " && run_vmbake session create ssh dalmatia 'cd git/Infrastruktur && exec /usr/local/bin/claude --resume' screen | grep -q "^exec screen -dR -S 'claude@dalmatia:Infrastruktur' ssh -t " && run_vmbake session create ssh dalmatia 'cd git/Infrastruktur && exec /usr/local/bin/claude --resume' screen | grep -qF -- "$lc"; then
    pass "session create ssh ... screen wraps the ssh in screen -dR, the session named after the last command of the program line (no path, no exec), the guest, and the target of a leading cd"
  else
    fail "session ssh screen: $(run_vmbake session create ssh dalmatia claude screen)"
  fi
  if run_vmbake session create ssh dalmatia claude tmux | grep -q "the multiplexer is 'screen', not 'tmux'"; then
    pass "a multiplexer other than screen is refused by name"
  else
    fail "session mux guard: $(run_vmbake session create ssh dalmatia claude tmux)"
  fi
  lc="'sh -lc '\\''claude \"\$@\"'\\'' sh' \"\$@\""
  if run_vmbake session create xterm dalmatia | grep -q "^exec xterm -T 'dalmatia' -e ssh -p 2222 .* '$(id -un)@dalmatia.local' \"\$@\"$" && run_vmbake session create xterm dalmatia claude | grep -q "^exec xterm -T 'claude@dalmatia' -e ssh -t -p 2222 " && run_vmbake session create xterm dalmatia claude | grep -qF -- "$lc"; then
    pass "session create xterm opens a window titled after guest or program@guest, with the ssh (and -t for a program) as its command"
  else
    fail "session xterm: $(run_vmbake session create xterm dalmatia claude)"
  fi
  if run_vmbake session create xterm dalmatia claude screen | grep -q "^exec xterm -T 'claude@dalmatia' -e screen -dR -S 'claude@dalmatia' ssh -t -p 2222 " && run_vmbake session create xterm dalmatia claude screen | grep -qF -- "$lc" && run_vmbake session create xterm nobody claude screen | grep -q "unknown guest nobody"; then
    pass "session create xterm ... screen puts screen -dR between the window and the ssh; an unknown guest is refused"
  else
    fail "session xterm screen: $(run_vmbake session create xterm dalmatia claude screen)"
  fi
  if run_vmbake session create x dalmatia idea | grep -q "lists no service 'display x'"; then
    pass "session create x refuses a guest whose template lacks display x"
  else
    fail "session x guard: $(run_vmbake session create x dalmatia idea)"
  fi
  out=$(run_vmbake session create x xenia idea)
  if printf '%s\n' "$out" | grep -q "Xephyr :[0-9][0-9]* -screen '1600x1000' -dpi '96' -title 'xenia: idea' -resizeable -no-host-grab -noreset -nolisten tcp &$" && printf '%s\n' "$out" | grep -q "^DISPLAY=:[0-9][0-9]* ssh -X -C -p 2222 -i '$TEST_DIR/key' .* '$(id -un)@xenia.local' 'command -v dbus-launch > /dev/null && eval .*; idea' \"\$@\" '; rc=" && printf '%s\n' "$out" | grep -q 'kill $DBUS_SESSION_BUS_PID' && printf '%s\n' "$out" | grep -q "no idea process left" && printf '%s\n' "$out" | grep -q '^kill "$xephyr"'; then
    pass "session create x: Xephyr compartment, ssh -X into it, the compartment closes when the program is gone"
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
  if run_vmbake image ssh write x | grep -q '^X11Forwarding yes$' && ! run_vmbake image ssh write d | grep -q '^X11Forwarding'; then
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
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "12" ] && printf '%s\n' "$plan" | sed -n 4p | grep -q "image port build 'x'" && printf '%s\n' "$plan" | sed -n 5p | grep -q "image port install 'x'" && [ "$(run_vmbake image burn d | grep -c .)" = "10" ]; then
    pass "burn in the builder: port build and install after the packages, only when ports are listed"
  else
    fail "burn ports plan: $plan"
  fi
  printf 'host\n' > "$TEST_DIR/.env/local/VM_BAKE_BAKE_IN"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake image burn x | grep -q "ports build in the builder only" && [ "$(run_vmbake image burn d | grep -c .)" = "10" ]; then
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
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "13" ] && printf '%s\n' "$plan" | sed -n 4p | grep -q "image check pkgfiles 'x'" && printf '%s\n' "$plan" | sed -n 5p | grep -q "image pkgfile stage 'x'" && printf '%s\n' "$plan" | sed -n 6p | grep -q "image pkgfile add 'x'" && [ "$(run_vmbake image burn d | grep -c .)" = "10" ] && run_vmbake image pkgfile stage x | grep -q "streamed into the builder"; then
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
  if run_vmbake template find can intellij | grep -q "^#   freebsd-x  *freebsd-x  *can intellij" && run_vmbake template find can claude | grep -q "^#   freebsd-dev " && ! run_vmbake template find can claude | grep -q "^#   freebsd-x " && run_vmbake template find owner . | grep -q "(none)" && run_vmbake template find can freebsd | grep -q "(none)" && run_vmbake template find can | grep -q "^#   freebsd-x  *freebsd-x  *can intellij" && run_vmbake template find can '^intellij$' | grep -q "^#   freebsd-x " && run_vmbake template find can '^intelli$' | grep -q "(none)"; then
    pass "template find matches key and pattern over the resolved tags, masks respected; the pattern meets the text alone, anchors make it exact, no pattern lists every text"
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
  if run_vmbake guest find can intellij | grep -q "^#   caledonia  *x  *freebsd-x  *can intellij" && ! run_vmbake guest find can intellij | grep -q dalmatia && run_vmbake guest find purpose claude | grep -q caledonia && run_vmbake guest find purpose claude | grep -q dalmatia && run_vmbake guest find note 'first' | grep -q "^#   caledonia  *x  *caledonia  *note first X guest" && run_vmbake guest find can caledonia | grep -q "(none)" && run_vmbake guest find can | grep -q "^#   caledonia  *x  *freebsd-x  *can intellij" && run_vmbake guest find can '^intellij$' | grep -q caledonia && run_vmbake guest find can '^intelli$' | grep -q "(none)"; then
    pass "guest find answers from own and inherited tags, by key and pattern; the pattern meets the text alone, not the guest's name, anchors make it exact, no pattern lists every text"
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
  if printf '%s\n' "$out" | grep -q "^XCURSOR_THEME='redglass' Xephyr :[0-9]* " && printf '%s\n' "$out" | grep -q "^DISPLAY=:[0-9]* ratpoison < /dev/null >> \"\$log.wm\" 2>&1 &$" && printf '%s\n' "$out" | grep -q "ssh -X -C -p 2222 .* 'command -v dbus-launch > /dev/null && eval .*; env LANG=C.UTF-8 XCURSOR_THEME=redglass code-oss --disable-gpu' \"\$@\" '; rc=" && printf '%s\n' "$out" | grep -q "no code-oss process left" && printf '%s\n' "$out" | grep -q "Xcursor.theme: %s.* 'redglass' '24' '96' | xrdb -display :[0-9]* -merge - &&" && printf '%s\n' "$out" | grep -q '^kill "$wm"'; then
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

test_home_plan() {
  test_header "home paths: the template family, checked and seeded into the clone at guest make"
  test_setup
  image_chain
  run_vmbake template add freebsd-x freebsd-dev > /dev/null
  if run_vmbake template home add freebsd-x "$HOME_FIXTURE/themes/NsCDE" | grep -q "home + $HOME_FIXTURE/themes/NsCDE ro" && run_vmbake template home add freebsd-x /etc/passwd | grep -q "invalid path" && run_vmbake template home add freebsd-x ../x | grep -q "invalid path" && run_vmbake template home show freebsd-x | grep -q "^#   freebsd-x  *$HOME_FIXTURE/themes/NsCDE ro"; then
    pass "template home add takes a plain relative path, ro by default, show lists it"
  else
    fail "template home: $(run_vmbake template home show freebsd-x)"
  fi
  if run_vmbake template home add freebsd-x "$HOME_FIXTURE/themes/NsCDE" rw | grep -q "home + $HOME_FIXTURE/themes/NsCDE rw" && run_vmbake template home add freebsd-x "$HOME_FIXTURE/themes/NsCDE" xx | grep -q "ro or rw" && run_vmbake template home drop freebsd-x "$HOME_FIXTURE/themes/NsCDE" rw > /dev/null && [ "$(run_vmbake template home show freebsd-x | grep -c NsCDE)" = "1" ]; then
    pass "the mode rw is a line of its own, another word is refused, drop names the mode"
  else
    fail "home mode: $(run_vmbake template home show freebsd-x)"
  fi
  run_vmbake template home add freebsd-dev "$HOME_FIXTURE/config/gtk-3.0" > /dev/null
  run_vmbake image record write freebsd-x x > /dev/null
  run_vmbake image record write freebsd-builder b > /dev/null
  run_vmbake guest record write x caledonia 172.16.100.102/24 > /dev/null
  run_vmbake guest record write b bake 172.16.100.254/24 > /dev/null
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  local plan
  plan=$(run_vmbake guest make x caledonia 172.16.100.102/24)
  local disk
  disk=$(run_vmbake guest disk write caledonia)
  if printf '%s\n' "$plan" | grep -q "guest check homes 'caledonia'" && printf '%s\n' "$plan" | grep -q "guest disk write 'caledonia'" && printf '%s\n' "$disk" | grep -q "guest home write 'caledonia'" && printf '%s\n' "$disk" | grep -n "guest network write\|guest home write" | sed -n 2p | grep -q "home write"; then
    pass "guest make checks the home paths, and the disk write of a chroot bake seeds them after the network"
  else
    fail "guest make plan: $plan"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  run_vmbake template home add freebsd-x .no-such-dir-vmbake/x > /dev/null
  if run_vmbake guest check homes caledonia | grep -q "home path missing under $HOME: .no-such-dir-vmbake/x" && run_vmbake template home drop freebsd-x .no-such-dir-vmbake/x > /dev/null && [ -z "$(run_vmbake guest check homes caledonia)" ]; then
    pass "check homes names a path the host's home lacks"
  else
    fail "check homes: $(run_vmbake guest check homes caledonia)"
  fi
  if pin_image_cat; then
    pass "guest acts pinned to cat"
  else
    fail "acts not pinned -- not calling them"; return
  fi
  local out
  out=$(run_vmbake guest home write caledonia)
  if printf '%s\n' "$out" | grep -q "mount -t ufs '/dev/gpt/x-root' '/data/vm/vm-bake/guest/caledonia/mnt'" && printf '%s\n' "$out" | grep -q "cp -R '$HOME/$HOME_FIXTURE/themes/NsCDE' '/data/vm/vm-bake/guest/caledonia/mnt/home/$(id -un)/$HOME_FIXTURE/themes/NsCDE'" && printf '%s\n' "$out" | grep -q "cp -R '$HOME/$HOME_FIXTURE/config/gtk-3.0' " && printf '%s\n' "$out" | grep -q "chown -R '$(id -u)':\"\$g\" '/data/vm/vm-bake/guest/caledonia/mnt/home/$(id -un)/$HOME_FIXTURE'" && printf '%s\n' "$out" | grep -q 'mdconfig -d -u'; then
    pass "home write mounts the clone, copies every path into every user's home with the right owner, detaches"
  else
    fail "home write: $out"
  fi
  if run_vmbake guest home write bake | grep -q "nothing seeded"; then
    pass "a template without home paths seeds nothing"
  else
    fail "home write empty: $(run_vmbake guest home write bake)"
  fi
}



# view_chain - freebsd-dev gets a view and three home lines of the fixture (all nested, so the mount makes their parent), freebsd-builder none
view_chain() {
  run_vmbake template service add freebsd-dev files view > /dev/null
  run_vmbake template rc add freebsd-dev kld_list nvidia > /dev/null
  run_vmbake template home add freebsd-dev "$HOME_FIXTURE/config" > /dev/null
  run_vmbake template home add freebsd-dev "$HOME_FIXTURE/cache" rw > /dev/null
  run_vmbake template home add freebsd-dev "$HOME_FIXTURE/db" > /dev/null
  run_vmbake image record write freebsd-dev x > /dev/null
  run_vmbake image record write freebsd-builder b > /dev/null
  run_vmbake guest record write x caledonia 172.16.100.102/24 > /dev/null
  run_vmbake guest record write b bake 172.16.100.254/24 > /dev/null
  run_vmbake setenv VM_BAKE_VIEW_DIR "$TEST_DIR/view" > /dev/null
}

test_view_plan() {
  test_header "view: 'service files view' puts the share into the guest's configuration and the mount into the image"
  test_setup
  image_chain
  view_chain
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  local plan
  plan=$(run_vmbake guest make x caledonia 172.16.100.102/24)
  if printf '%s\n' "$plan" | grep -q "guest view ensure 'caledonia'" && printf '%s\n' "$plan" | grep -n "guest hostkey ensure\|guest view ensure\|guest clone" | sed -n 2p | grep -q "view ensure"; then
    pass "guest make ensures the view between the host key and the clone"
  else
    fail "guest make plan: $plan"
  fi
  plan=$(run_vmbake guest start caledonia)
  if printf '%s\n' "$plan" | grep -q "guest check homes 'caledonia'" && printf '%s\n' "$plan" | grep -n "guest view mount\|guest run" | sed -n 1p | grep -q "view mount"; then
    pass "guest start hangs the overlays in before vm start"
  else
    fail "guest start plan: $plan"
  fi
  plan=$(run_vmbake guest stop caledonia)
  if printf '%s\n' "$plan" | grep -n "guest halt\|guest gone\|guest view unmount" | sed -n 3p | grep -q "view unmount"; then
    pass "guest stop lets the overlays go after the guest is gone"
  else
    fail "guest stop plan: $plan"
  fi
  plan=$(run_vmbake guest drop caledonia)
  if printf '%s\n' "$plan" | grep -q "guest view unmount 'caledonia'" && ! printf '%s\n' "$plan" | grep -q "guest view destroy"; then
    pass "guest drop lets the overlays go and keeps the view"
  else
    fail "guest drop plan: $plan"
  fi
  plan=$(run_vmbake guest view drop caledonia)
  if printf '%s\n' "$plan" | grep -q "guest check stopped 'caledonia'" && printf '%s\n' "$plan" | grep -q "guest view unmount 'caledonia'" && printf '%s\n' "$plan" | grep -q "guest view destroy 'caledonia'"; then
    pass "guest view drop lets go and destroys, the guest stopped"
  else
    fail "guest view drop plan: $plan"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake guest check view caledonia | grep -q "has no view"; then
    pass "check view refuses a guest whose view directory is not there"
  else
    fail "check view: $(run_vmbake guest check view caledonia)"
  fi
}

test_view_acts() {
  test_header "view: the acts -- the dataset, the overlays by their mode, the module and the fstab line of the image"
  test_setup
  image_chain
  view_chain
  if pin_image_cat; then
    pass "image and guest acts pinned to cat"
  else
    fail "acts not pinned -- not calling them"; return
  fi
  local out view
  view="$TEST_DIR/view"
  mkdir -p "$view/caledonia"
  out=$(run_vmbake guest view ensure caledonia)
  if printf '%s\n' "$out" | grep -q "zfs list -H -o name '$view'" && printf '%s\n' "$out" | grep -q "zfs create \"\$parent/caledonia\"" && printf '%s\n' "$out" | grep -q "chown '$(id -un)':'$(id -gn)' '$view/caledonia'"; then
    pass "view ensure creates the dataset under the view directory and hands it to the invoking user"
  else
    fail "view ensure: $out"
  fi
  if run_vmbake guest view ensure bake | grep -q "no view in the template freebsd-builder"; then
    pass "a template without the service gets no view"
  else
    fail "view ensure without the service: $(run_vmbake guest view ensure bake)"
  fi
  out=$(run_vmbake guest view mount caledonia)
  if printf '%s\n' "$out" | grep -q "mount -t nullfs -o ro '$HOME/$HOME_FIXTURE/config' '$view/caledonia/$HOME_FIXTURE/config'" && printf '%s\n' "$out" | grep -q "mount -t nullfs -o rw '$HOME/$HOME_FIXTURE/cache' '$view/caledonia/$HOME_FIXTURE/cache'" && printf '%s\n' "$out" | grep -q "install -d -o '$(id -un)' -g '$(id -gn)' -m 755 '$view/caledonia/$HOME_FIXTURE' '$view/caledonia/$HOME_FIXTURE/db'"; then
    pass "view mount hangs every home line in with its own mode, the directory made first"
  else
    fail "view mount: $out"
  fi
  if printf '%s\n' "$out" | grep -n "git/local\|mount -t nullfs" | sed -n 1p | grep -q "install -d -o '$(id -un)' -g '$(id -gn)' -m 755 '$view/caledonia/git' '$view/caledonia/git/local'"; then
    pass "view mount makes the mount point git/local (and its parent) for the guest's disk before the overlays"
  else
    fail "view mount: $out"
  fi
  run_vmbake template home add freebsd-dev .no-such-dir-vmbake > /dev/null
  if run_vmbake guest view mount caledonia | grep -q "no-such-dir-vmbake is no directory"; then
    pass "a home line that is no directory on the host stops the mount at generation time"
  else
    fail "view mount with a missing path: $(run_vmbake guest view mount caledonia)"
  fi
  run_vmbake template home drop freebsd-dev .no-such-dir-vmbake > /dev/null
  printf '%s\n' "$HOME_FIXTURE/ssh" >> "$(record_of freebsd-dev)/home"
  if run_vmbake guest view mount caledonia | grep -q "mount -t nullfs -o ro '$HOME/$HOME_FIXTURE/ssh' '$view/caledonia/$HOME_FIXTURE/ssh'"; then
    pass "a home line from before the modes (a bare path) counts as ro"
  else
    fail "view mount of a bare path: $(run_vmbake guest view mount caledonia)"
  fi
  run_vmbake template home drop freebsd-dev "$HOME_FIXTURE/ssh" > /dev/null 2>&1
  printf '%s\n' "$(grep -v "^$HOME_FIXTURE/ssh$" "$(record_of freebsd-dev)/home")" > "$(record_of freebsd-dev)/home"
  if run_vmbake guest view unmount caledonia | grep -q "nothing hung into its view" && run_vmbake guest view destroy caledonia | grep -q "zfs destroy -r"; then
    pass "view unmount reads the mount table, view destroy destroys the dataset"
  else
    fail "view unmount/destroy: $(run_vmbake guest view unmount caledonia) $(run_vmbake guest view destroy caledonia)"
  fi
  out=$(run_vmbake guest conf write caledonia)
  if printf '%s\n' "$out" | grep -q "bhyve_options=\"-s 30,virtio-9p,home=$view/caledonia\"" && ! run_vmbake guest conf write bake | grep -q bhyve_options; then
    pass "the configuration of a guest with a view carries the share, the one without does not"
  else
    fail "conf write: $out"
  fi
  if run_vmbake guest home write caledonia | grep -q "comes from the host through its view"; then
    pass "a guest with a view is seeded with nothing"
  else
    fail "home write with a view: $(run_vmbake guest home write caledonia)"
  fi
  out=$(run_vmbake image view write x)
  if printf '%s\n' "$out" | grep -q 'virtio_p9fs_load="YES"' && printf '%s\n' "$out" | grep -q "/data/vm/vm-bake/image/x/mnt/boot/loader.conf" && ! printf '%s\n' "$out" | grep -q "kld_list" && printf '%s\n' "$out" | grep -q "'/home/$(id -un)' >> '/data/vm/vm-bake/image/x/mnt/etc/fstab'" && printf '%s\n' "$out" | grep -q "install -d -m 755 '/data/vm/vm-bake/image/x/mnt/var/git' && chown '$(id -u)':\"\$g\"" && printf '%s\n' "$out" | grep -n "p9fs\|nullfs" | grep -q "nullfs.*failok.*/var/git '/home/$(id -un)/git/local' >> " && printf '%s\n' "$out" | grep -n "p9fs.*fstab\|nullfs.*fstab" | sed -n 2p | grep -q nullfs; then
    pass "image view write loads the transport from the loader (not kld_list, which comes after the fstab), mounts the share on the host-uid user's home, and after it /var/git of the disk (the user's, failok) on git/local of that home"
  else
    fail "image view write: $out"
  fi
  if run_vmbake image view write b | grep -q "no view in the template"; then
    pass "an image of a template without the service learns nothing about p9fs"
  else
    fail "image view write without the service: $(run_vmbake image view write b)"
  fi
  out=$(run_vmbake image ssh write x)
  if printf '%s\n' "$out" | grep -q "AuthorizedKeysFile /etc/ssh/authorized_keys/%u .ssh/authorized_keys" && run_vmbake image user make x | grep -q "/etc/ssh/authorized_keys/$(id -un)"; then
    pass "sshd reads the keys outside the home as well, and image user make puts them there"
  else
    fail "ssh write: $out"
  fi
  if printf '%s\n' "$out" | sed -n 2p | grep -q "sed -i '' -E 's/\^\[\[:space:\]\]\*(Port|PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|LogLevel|AuthorizedKeysFile|X11Forwarding)" && printf '%s\n' "$out" | grep -q "^LogLevel VERBOSE$" && [ "$(printf '%s\n' "$out" | grep -c "^X11Forwarding")" = "0" ]; then
    pass "the directives the shipped config sets are commented out BEFORE the block is appended (sshd takes the first value), the log says why a key is refused, and X11 stays off without the service"
  else
    fail "ssh write guard: $(printf '%s\n' "$out" | sed -n 2p)"
  fi
  local carrier parent
  carrier=$(df "$HOME" 2>/dev/null | awk 'NR == 2 { print $1 }')
  case "$carrier" in */?*) parent=${carrier%/*} ;; *) parent="" ;; esac
  run_vmbake setenv VM_BAKE_VIEW_DIR "$HOME/.vm-bake-view-test/guest" > /dev/null
  out=$(run_vmbake guest view tree ensure)
  if [ -z "$parent" ]; then
    if printf '%s\n' "$out" | grep -q "no ZFS dataset below a parent carries $HOME (df says $carrier)"; then
      pass "view tree ensure refuses where no ZFS dataset below a parent carries the home (here: $carrier), the carrier named"
    else
      fail "view tree ensure without a ZFS parent: $out"
    fi
  elif printf '%s\n' "$out" | grep -q "zfs create -o mountpoint='$HOME/.vm-bake-view-test' '$parent/.vm-bake-view-test'" && printf '%s\n' "$out" | grep -q "zfs create -p '$parent/.vm-bake-view-test/guest'" && printf '%s\n' "$out" | grep -q "chown '$(id -un)':'$(id -gn)' '$HOME/.vm-bake-view-test/guest' && chmod 0700" && printf '%s\n' "$out" | grep -q "zfs list -H -o name '$HOME/.vm-bake-view-test/guest' > /dev/null 2>&1 &&"; then
    pass "view tree ensure lays the path below the home out as a dataset path beside the home's own, the head carries the mount point, and an existing one is kept"
  else
    fail "view tree ensure: $out"
  fi
  run_vmbake setenv VM_BAKE_VIEW_DIR "$TEST_DIR/view" > /dev/null
  if run_vmbake guest view tree ensure | grep -q "lies outside the home"; then
    pass "a view directory outside the home is refused: a view is a part of that home"
  else
    fail "view tree ensure outside the home: $(run_vmbake guest view tree ensure)"
  fi
}

test_repo_plan() {
  test_header "repo: the host's mirror in the view, the guest's clone on its disk over ssh, fetched back over ssh; the record, ensure after start, hold before stop, the fetched mark before drop"
  test_setup
  image_chain
  view_chain
  printf 'ssh-ed25519 AAAATEST test@host\n' > "$TEST_DIR/key.pub"
  run_vmbake setenv VM_BAKE_HOST_KEY "$TEST_DIR/key.pub" > /dev/null
  run_vmbake setenv VM_BAKE_GUEST_DIR "$TEST_DIR/vmdir" > /dev/null
  mkdir -p "$TEST_DIR/vmdir/caledonia"
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  local plan out view lc
  view="$TEST_DIR/view"
  mkdir -p "$view/caledonia"
  plan=$(run_vmbake guest repo add caledonia git/Infrastruktur)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "7" ] && printf '%s\n' "$plan" | grep -q "guest check view 'caledonia'" && printf '%s\n' "$plan" | grep -q "guest check running 'caledonia'" && printf '%s\n' "$plan" | grep -q "guest repo valid 'git/Infrastruktur'" && printf '%s\n' "$plan" | grep -q "guest repo mirror 'git/Infrastruktur'" && printf '%s\n' "$plan" | sed -n 6p | grep -q "guest repo clone 'caledonia' 'git/Infrastruktur'" && printf '%s\n' "$plan" | sed -n 7p | grep -q "guest repo record 'caledonia' 'git/Infrastruktur'"; then
    pass "repo add checks record, view, running guest and path, then mirror, record, clone"
  else
    fail "repo add plan: $plan"
  fi
  plan=$(run_vmbake guest repo fetch caledonia git/Infrastruktur)
  if printf '%s\n' "$plan" | grep -q "guest check running 'caledonia'" && printf '%s\n' "$plan" | grep -q "guest repo refs 'caledonia' 'git/Infrastruktur'" && printf '%s\n' "$plan" | tail -1 | grep -q "comment 'repository git/Infrastruktur: .*git -C $HOME/git/Infrastruktur merge --ff-only caledonia/main'"; then
    pass "repo fetch needs the running guest, fetches into the refs of the host's repository and ends in the comment that names the merge"
  else
    fail "repo fetch plan: $plan"
  fi
  plan=$(run_vmbake guest repo pull caledonia git/Infrastruktur)
  if printf '%s\n' "$plan" | grep -q "guest check running 'caledonia'" && printf '%s\n' "$plan" | grep -q "guest repo refs 'caledonia' 'git/Infrastruktur'" && printf '%s\n' "$plan" | tail -1 | grep -q "guest repo merge 'caledonia' 'git/Infrastruktur'"; then
    pass "repo pull is the fetch of repo fetch, then repo merge"
  else
    fail "repo pull plan: $plan"
  fi
  plan=$(run_vmbake guest repo drop caledonia git/Infrastruktur)
  if printf '%s\n' "$plan" | grep -q "guest repo remove 'caledonia' 'git/Infrastruktur'" && printf '%s\n' "$plan" | grep -q "guest repo unrecord 'caledonia' 'git/Infrastruktur'"; then
    pass "repo drop removes the clone from the disk and the line from the record"
  else
    fail "repo drop plan: $plan"
  fi
  if run_vmbake guest repo ensure caledonia | grep -q "no repositories recorded" && run_vmbake guest repo hold caledonia | grep -q "is not running, nothing to hold" && [ -z "$(run_vmbake guest check fetched caledonia)" ]; then
    pass "without a record: ensure and hold are comments, the fetched check is silent"
  else
    fail "ensure/hold without record: $(run_vmbake guest repo ensure caledonia)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  run_vmbake guest repo record caledonia git/Infrastruktur > /dev/null
  run_vmbake guest repo record caledonia git/Infrastruktur > /dev/null
  run_vmbake guest repo record caledonia git/elvboot > /dev/null
  if [ "$(cat "$TEST_DIR/guest/caledonia/repo" | tr '\n' ' ')" = "git/Infrastruktur git/elvboot " ] && run_vmbake guest check fetched caledonia | grep -q "were not fetched after its last start" && run_vmbake guest check running caledonia | grep -q "is not running"; then
    pass "record lists each repository once; with a record and no mark the fetched check refuses, a stopped guest is named"
  else
    fail "record/fetched: $(cat "$TEST_DIR/guest/caledonia/repo"; run_vmbake guest check fetched caledonia)"
  fi
  printf 'x\n' > "$TEST_DIR/vmdir/caledonia/run.lock"
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  plan=$(run_vmbake guest repo ensure caledonia)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "4" ] && printf '%s\n' "$plan" | sed -n 2p | grep -q "guest repo wait 'caledonia'" && printf '%s\n' "$plan" | grep -q "guest repo clone 'caledonia' 'git/Infrastruktur'" && printf '%s\n' "$plan" | grep -q "guest repo clone 'caledonia' 'git/elvboot'"; then
    pass "ensure waits for ssh, then clones every recorded repository"
  else
    fail "ensure plan: $plan"
  fi
  plan=$(run_vmbake guest repo hold caledonia)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "4" ] && printf '%s\n' "$plan" | grep -q "guest repo refs 'caledonia' 'git/Infrastruktur'" && printf '%s\n' "$plan" | grep -q "guest repo refs 'caledonia' 'git/elvboot'" && printf '%s\n' "$plan" | sed -n 4p | grep -q "guest fetched write 'caledonia'"; then
    pass "hold fetches every recorded repository of the running guest, then writes the mark"
  else
    fail "hold plan: $plan"
  fi
  plan=$(run_vmbake guest drop caledonia)
  if printf '%s\n' "$plan" | sed -n 3p | grep -q "guest check fetched 'caledonia'" && ! run_vmbake guest drop unfetched caledonia | grep -q "check fetched" && [ "$(run_vmbake guest drop unfetched caledonia | grep -c .)" = "9" ]; then
    pass "drop checks the mark third; drop unfetched does not"
  else
    fail "drop plans: $plan"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  run_vmbake guest fetched write caledonia > /dev/null
  if [ -s "$TEST_DIR/guest/caledonia/fetched" ] && [ -z "$(run_vmbake guest check fetched caledonia)" ] && run_vmbake guest fetched drop caledonia > /dev/null && [ ! -e "$TEST_DIR/guest/caledonia/fetched" ]; then
    pass "the mark is written with a date, satisfies the check, and is dropped again"
  else
    fail "fetched mark: $(ls -l "$TEST_DIR/guest/caledonia")"
  fi
  if [ -z "$(run_vmbake guest repo valid git/Infrastruktur)" ] && run_vmbake guest repo valid ../x | grep -q "invalid repository" && run_vmbake guest repo valid /etc | grep -q "invalid repository"; then
    pass "a repository is a plain path relative to the home"
  else
    fail "repo valid: $(run_vmbake guest repo valid ../x)"
  fi
  if pin_image_cat; then
    pass "guest acts pinned to cat"
  else
    fail "acts not pinned -- not calling them"; return
  fi
  out=$(run_vmbake guest repo mirror git/Infrastruktur)
  if ! printf '%s\n' "$out" | grep -q "install -d" && printf '%s\n' "$out" | grep -q "git clone --mirror --no-hardlinks '$HOME/git/Infrastruktur' '$HOME/git/views/Infrastruktur'" && printf '%s\n' "$out" | grep -q "git -C '$HOME/git/views/Infrastruktur' fetch --prune origin" && printf '%s\n' "$out" | grep -q "config --get remote.origin.url"; then
    pass "the mirror is bare, without hardlinks, refreshed when there, refused when it is of another repository; the directory is not its business"
  else
    fail "repo mirror: $out"
  fi
  out=$(run_vmbake guest repo tree ensure)
  if [ "$(printf '%s\n' "$out" | grep -c .)" = "2" ] && printf '%s\n' "$out" | grep -q "^test -d '$HOME/git/views' || install -d -m 755 '$HOME/git/views' || exit 1$"; then
    pass "the mirrors' directory is made by the tool, in the invoking user's home, when it is missing"
  else
    fail "repo tree ensure: $out"
  fi
  git -c init.defaultBranch=main init -q "$HOME/$HOME_FIXTURE/repo" && git -C "$HOME/$HOME_FIXTURE/repo" config user.name 'vm-bake test' && git -C "$HOME/$HOME_FIXTURE/repo" config user.email 'test@vm-bake.invalid'
  out=$(run_vmbake guest repo clone caledonia "$HOME_FIXTURE/repo")
  lc="git clone \"\$HOME/git/views/repo\" '\\''git/local/repo'\\''"
  if printf '%s\n' "$out" | grep -q "^ssh -p 2222 -i '$TEST_DIR/key' .* -o BatchMode=yes '$(id -un)@caledonia.local' " && printf '%s\n' "$out" | grep -qF -- "$lc" && printf '%s\n' "$out" | grep -qF -- "if test -e '\\''git/local/repo'\\''; then printf '\\''# guest %s: %s is there already" && printf '%s\n' "$out" | grep -qF -- "git -C '\\''git/local/repo'\\'' config user.name '\\''vm-bake test'\\'' && git -C '\\''git/local/repo'\\'' config user.email '\\''test@vm-bake.invalid'\\''"; then
    pass "the clone is made over ssh on the guest's disk from the mirror in its view, an existing one left alone, with the identity that holds in the host's repository (its own, read with the home set)"
  else
    fail "repo clone: $out"
  fi
  out=$(run_vmbake guest repo refs caledonia git/Infrastruktur)
  if printf '%s\n' "$out" | grep -q "git -C '$HOME/git/Infrastruktur' -c core.sshCommand='ssh -i $TEST_DIR/key .*' fetch --no-tags --prune 'ssh://$(id -un)@caledonia.local:2222/~/git/local/Infrastruktur' '+refs/heads/\*:refs/remotes/caledonia/\*'"; then
    pass "the host fetches in its OWN repository, over ssh from the guest's disk, into refs/remotes/<guest>/"
  else
    fail "repo refs: $out"
  fi
  out=$(run_vmbake guest repo merge caledonia git/Infrastruktur)
  if printf '%s\n' "$out" | grep -q "^git -C '$HOME/git/Infrastruktur' log --oneline 'main..caledonia/main' | sed 's/^/# /' >&2$" && printf '%s\n' "$out" | grep -q "^git -C '$HOME/git/Infrastruktur' merge --ff-only 'caledonia/main' >&2 || { printf '# Error: .*does not fast-forward"; then
    pass "merge lists the guest's commits, then fast-forwards the host's checked-out branch in its OWN repository; a diverged branch is an error"
  else
    fail "repo merge: $out"
  fi
  out=$(run_vmbake guest repo remove caledonia git/Infrastruktur)
  if printf '%s\n' "$out" | grep -q "^ssh -p 2222 .* '$(id -un)@caledonia.local' " && printf '%s\n' "$out" | grep -qF -- "rm -rf '\\''git/local/Infrastruktur'\\''"; then
    pass "remove takes the clone off the guest's disk over ssh"
  else
    fail "repo remove: $out"
  fi
  out=$(run_vmbake guest repo show caledonia)
  if printf '%s\n' "$out" | grep -q "'#   git/Infrastruktur'" && printf '%s\n' "$out" | grep -q "'#   git/elvboot'" && printf '%s\n' "$out" | grep -q "^ssh -p 2222 .* '$(id -un)@caledonia.local' " && printf '%s\n' "$out" | grep -qF -- "git/local/*/.git/HEAD"; then
    pass "show prints the record and lists the clones on the disk over ssh"
  else
    fail "repo show: $out"
  fi
  run_vmbake unsetenv VM_BAKE_GUEST_DIR > /dev/null
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


test_guest_report() {
  test_header "report: what the records say about a guest, shown and written into its view as GUEST.txt"
  test_setup
  image_chain
  view_chain
  local out plan
  out=$(run_vmbake guest show caledonia)
  if printf '%s\n' "$out" | grep -q "^# guest caledonia" && printf '%s\n' "$out" | grep -q "^#   image     x" && printf '%s\n' "$out" | grep -q "^#   chain     empty > freebsd > freebsd-15.1 > freebsd-dev" && printf '%s\n' "$out" | grep -q "^#   view      $TEST_DIR/view/caledonia on the host" && printf '%s\n' "$out" | grep -q "slot 30, share home" && [ "$(printf '%s\n' "$out" | grep -c '^# [a-z]* (origin')" = "12" ]; then
    pass "guest show names record, template chain, view and every list family"
  else
    fail "guest show: $out"
  fi
  if run_vmbake guest show bake | grep -q "^#   view      none (the home lies on the disk of the guest)"; then
    pass "a guest without a view says so"
  else
    fail "guest show without a view: $(run_vmbake guest show bake | sed -n 9p)"
  fi
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  plan=$(run_vmbake guest report caledonia)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "3" ] && printf '%s\n' "$plan" | grep -q "guest show 'caledonia' > '$TEST_DIR/.tmp/report.caledonia'" && printf '%s\n' "$plan" | grep -q "guest report place 'caledonia'"; then
    pass "guest report renders into the database's .tmp and puts the file in place"
  else
    fail "guest report plan: $plan"
  fi
  plan=$(run_vmbake guest start caledonia)
  if printf '%s\n' "$plan" | grep -n "guest report\|guest run" | sed -n 1p | grep -q "guest report"; then
    pass "guest start writes the report before it starts the guest"
  else
    fail "guest start plan: $plan"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  mkdir -p "$TEST_DIR/view/caledonia"
  run_vmbake guest report caledonia > /dev/null
  if [ -s "$TEST_DIR/view/caledonia/.vm-bake/GUEST.txt" ] && grep -q "^# guest caledonia" "$TEST_DIR/view/caledonia/.vm-bake/GUEST.txt" && [ "$(stat -f '%Lp' "$TEST_DIR/view/caledonia/.vm-bake/GUEST.txt")" = 644 ] && [ ! -e "$TEST_DIR/.tmp/report.caledonia" ]; then
    pass "the report lands in the view as .vm-bake/GUEST.txt (0644), the directory made first, nothing left over"
  else
    fail "report file: $(ls -l "$TEST_DIR/view/caledonia/.vm-bake" 2>&1)"
  fi
  if [ -z "$(run_vmbake guest report bake)" ] && [ ! -e "$TEST_DIR/view/bake/.vm-bake/GUEST.txt" ]; then
    pass "a guest without a view gets no report"
  else
    fail "report without a view: $(run_vmbake guest report bake)"
  fi
}


# dowry_chain - an object in the database, handed to freebsd-dev's guests
dowry_chain() {
  mkdir -p "$TEST_DIR/src/sub"
  printf 'eins\n' > "$TEST_DIR/src/datei"
  printf 'zwei\n' > "$TEST_DIR/src/sub/mehr"
  run_vmbake template add freebsd-x freebsd-dev > /dev/null
  run_vmbake dowry add claude-state "$TEST_DIR/src" > /dev/null
  run_vmbake setenv VM_BAKE_VIEW_DIR "$TEST_DIR/view" > /dev/null
  mkdir -p "$TEST_DIR/view/caledonia" "$TEST_DIR/view/bake"
}

test_dowry() {
  test_header "dowry: an object kept in the database, handed out by the template (copy, unlink, mask, unmask)"
  test_setup
  image_chain
  view_chain
  dowry_chain
  local out
  if run_vmbake dowry list | grep -q "^#   claude-state .*directory" && [ -f "$(record_of freebsd-dev)/../../dowry/claude-state/object/datei" ] && [ -f "$TEST_DIR/dowry/claude-state/object/sub/mehr" ]; then
    pass "dowry add copies the whole object into the database, list names it"
  else
    fail "dowry add: $(run_vmbake dowry list)"
  fi
  if run_vmbake dowry add 'bad name' "$TEST_DIR/src" | grep -q "invalid name" && run_vmbake dowry add other relative/path | grep -q "absolute path" && run_vmbake dowry add other "$TEST_DIR/no-such-source" | grep -q "absolute path"; then
    pass "the name is a word, the source an absolute path that is there"
  else
    fail "dowry guards: $(run_vmbake dowry add other relative/path)"
  fi
  if run_vmbake template home copy idem freebsd-dev claude-state .claude | grep -q "home + copy idem claude-state .claude" && run_vmbake template home copy overwrite freebsd-dev claude-state .vorlage | grep -q "home + copy overwrite claude-state .vorlage" && run_vmbake template home copy idem freebsd-dev no-such-dowry .x | grep -q "unknown dowry no-such-dowry" && run_vmbake template home copy idem freebsd-dev claude-state /etc | grep -q "invalid path"; then
    pass "copy idem and copy overwrite record their line, an unknown dowry and an absolute destination are refused"
  else
    fail "template home copy: $(run_vmbake template home show freebsd-dev)"
  fi
  if run_vmbake template home show freebsd-x | grep -q "^#   freebsd-dev  *copy idem claude-state .claude"; then
    pass "a child inherits the rule"
  else
    fail "inheritance: $(run_vmbake template home show freebsd-x)"
  fi
  run_vmbake template home mask idem freebsd-x claude-state .claude > /dev/null
  if ! run_vmbake template home show freebsd-x | grep -q "copy idem claude-state .claude" && run_vmbake template home show freebsd-dev | grep -q "copy idem claude-state .claude"; then
    pass "mask idem hides the inherited rule below, not at its origin"
  else
    fail "mask idem: $(run_vmbake template home show freebsd-x)"
  fi
  run_vmbake template home unmask idem freebsd-x claude-state .claude > /dev/null
  if run_vmbake template home show freebsd-x | grep -q "copy idem claude-state .claude" && run_vmbake template home unmask idem freebsd-x claude-state .claude | grep -q "does not mask"; then
    pass "unmask idem takes the mask back, and without a mask it is an error"
  else
    fail "unmask idem: $(run_vmbake template home show freebsd-x)"
  fi
  run_vmbake template home unlink overwrite freebsd-dev claude-state .vorlage > /dev/null
  if ! run_vmbake template home show freebsd-dev | grep -q "copy overwrite" && run_vmbake template home unlink idem freebsd-x claude-state .claude | grep -q "no own home entry"; then
    pass "unlink removes the template's own rule and refuses an inherited one"
  else
    fail "unlink: $(run_vmbake template home show freebsd-dev)"
  fi
  if run_vmbake dowry drop claude-state | grep -q "removed from the database" && run_vmbake dowry drop claude-state | grep -q "unknown dowry claude-state" && [ ! -d "$TEST_DIR/dowry/claude-state" ]; then
    pass "dowry drop throws the object out, a second drop is an error"
  else
    fail "dowry drop: $(run_vmbake dowry list)"
  fi
}

test_dowry_place() {
  test_header "dowry: placed into the view by its policy at guest start, witnessed in the dump, carried by the bundle"
  test_setup
  image_chain
  view_chain
  dowry_chain
  local out plan
  run_vmbake template home copy idem freebsd-dev claude-state .claude > /dev/null
  run_vmbake template home copy overwrite freebsd-dev claude-state .vorlage > /dev/null
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  plan=$(run_vmbake guest start caledonia)
  if printf '%s\n' "$plan" | grep -n "guest dowry place\|guest view mount" | sed -n 1p | grep -q "dowry place" && [ "$(run_vmbake guest dowry place caledonia | grep -c .)" = "2" ]; then
    pass "guest start places the dowry before it hangs the overlays in, by its two policies"
  else
    fail "guest start plan: $plan"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  run_vmbake guest dowry place caledonia > /dev/null
  printf 'des gastes\n' > "$TEST_DIR/view/caledonia/.claude/eigenes"
  printf 'des gastes\n' > "$TEST_DIR/view/caledonia/.vorlage/eigenes"
  run_vmbake guest dowry place caledonia > /dev/null
  if [ -f "$TEST_DIR/view/caledonia/.claude/datei" ] && [ -f "$TEST_DIR/view/caledonia/.claude/sub/mehr" ] && [ -f "$TEST_DIR/view/caledonia/.claude/eigenes" ] && [ ! -e "$TEST_DIR/view/caledonia/.vorlage/eigenes" ]; then
    pass "idem keeps what the guest made of it, overwrite replaces the destination"
  else
    fail "policies: $(find "$TEST_DIR/view/caledonia" | sort | tr '\n' ' ')"
  fi
  if run_vmbake guest dowry place bake | grep -q "hands out no dowry"; then
    pass "a guest of a template without rules gets a note"
  else
    fail "dowry place without rules: $(run_vmbake guest dowry place bake)"
  fi
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_INTERPRETER_guest_view_mount"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if [ "$(run_vmbake getintp guest_view_mount | tail -1)" != cat ]; then
    fail "guest view mount not pinned to cat -- not calling it (its default is sudo sh and WOULD mount)"
  elif [ -z "$(run_vmbake guest check homes caledonia)" ] && ! run_vmbake guest view mount caledonia | grep -q "nullfs -o copy"; then
    pass "the readers of the home lines skip the copy lines"
  else
    fail "readers: $(run_vmbake guest view mount caledonia)"
  fi
  run_vmbake dowry drop claude-state > /dev/null
  if run_vmbake guest dowry place caledonia | grep -q "which this database does not keep"; then
    pass "a rule whose dowry the database no longer keeps is an error at generation time"
  else
    fail "missing dowry: $(run_vmbake guest dowry place caledonia)"
  fi
  run_vmbake dowry add claude-state "$TEST_DIR/src" > /dev/null
  out=$(run_vmbake dowry dump all)
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if printf '%s\n' "$out" | grep -q "dowry record restore 'claude-state' '$TEST_DIR/src'" && run_vmbake dump all | grep -n "dowry dump all\|template dump all" | sed -n 1p | grep -q "dowry dump all"; then
    pass "the dump witnesses the dowry record, dump all calls it before the templates"
  else
    fail "dowry dump: $out"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  run_vmbake export collection write > /dev/null
  if grep -q "^db/dowry/claude-state/object/datei$" "$TEST_DIR/export/collection" && grep -q "^db/dowry/claude-state/object/sub/mehr$" "$TEST_DIR/export/collection"; then
    pass "the collection carries the object, so the bundle takes it along"
  else
    fail "collection: $(grep dowry "$TEST_DIR/export/collection" 2>&1)"
  fi
}

test_dump_witness() {
  test_header "dump: header, image and guest records as witnesses, env and tag lines with their arity, a replay restores the records"
  test_setup
  run_vmbake template add freebsd > /dev/null
  run_vmbake template env add freebsd LANG C.UTF-8 > /dev/null
  run_vmbake template tag add freebsd purpose 'dev with spaces' > /dev/null
  run_vmbake image record write freebsd img:dev:v1 > /dev/null
  printf '%s\n' 0123456789abcdef > "$TEST_DIR/image/img:dev:v1/digest"
  run_vmbake image record write freebsd img:dev:v2 > /dev/null
  run_vmbake guest record write img:dev:v1 g1 172.16.100.5/24 > /dev/null
  run_vmbake guest tag add g1 note 'two words' > /dev/null
  run_vmbake guest repo record g1 git/Infrastruktur > /dev/null
  run_vmbake dump > "$TEST_DIR/all.vmb" 2>/dev/null
  if grep -q '^# vm-bake database dump$' "$TEST_DIR/all.vmb" && grep -q "^# Profile: $TEST_PROFILE$" "$TEST_DIR/all.vmb" && grep -q '^# Version: 1$' "$TEST_DIR/all.vmb"; then
    pass "the dump opens with its header: generator, version, profile"
  else
    fail "header: $(head -8 "$TEST_DIR/all.vmb")"
  fi
  if grep -q "template env add 'freebsd' 'LANG' 'C.UTF-8'" "$TEST_DIR/all.vmb" && grep -q "template tag add 'freebsd' 'purpose' 'dev with spaces'" "$TEST_DIR/all.vmb"; then
    pass "env and tag lines replay with the arity of their commands"
  else
    fail "env/tag lines: $(grep 'template env\|template tag' "$TEST_DIR/all.vmb")"
  fi
  if grep -q "image record restore 'img:dev:v1' 'freebsd' '[0-9T:Z-]*' '0123456789abcdef'" "$TEST_DIR/all.vmb" && grep -q "image record restore 'img:dev:v2' 'freebsd' '[0-9T:Z-]*' 'open'" "$TEST_DIR/all.vmb" && grep -q "guest record restore 'g1' 'img:dev:v1' '172.16.100.5/24' '[0-9T:Z-]*'" "$TEST_DIR/all.vmb" && grep -q "guest tag add 'g1' 'note' 'two words'" "$TEST_DIR/all.vmb" && grep -q "guest repo record 'g1' 'git/Infrastruktur'" "$TEST_DIR/all.vmb"; then
    pass "image and guest records are witnesses in the dump, the guest with its own tags and repositories"
  else
    fail "witness lines: $(grep 'record restore\|guest tag' "$TEST_DIR/all.vmb")"
  fi
  local second="$TEST_BASE_DIR/test-$TESTS_RUN-second"
  mkdir -p "$second"
  VM_BAKE_ROOT="$TEST_BASE_DIR" VM_BAKE_BASE="$second" "$TEST_SCRIPT" bootstrap "test-$TESTS_RUN-second" "$TEST_PROFILE" > /dev/null 2>&1
  VM_BAKE_BASE="$second" "$TEST_SCRIPT" setenv VM_BAKE_TERMINAL_INTERPRETER sh > /dev/null 2>&1
  VM_BAKE_BASE="$second" "$TEST_SCRIPT" restore "$TEST_DIR/all.vmb" > "$TEST_DIR/restore.log" 2>&1
  if [ "$(cat "$second/image/img:dev:v1/digest")" = "0123456789abcdef" ] && [ ! -e "$second/image/img:dev:v2/digest" ] && [ "$(cat "$second/image/img:dev:v1/dir")" = "/data/vm/vm-bake/image/img:dev:v1" ] && [ "$(cat "$second/guest/g1/address")" = "172.16.100.5/24" ] && grep -qx 'note two words' "$second/guest/g1/tag"; then
    pass "the replay places the records: digest or none, this host's dir, the guest's address and tags"
  else
    fail "restored records: $(tail -5 "$TEST_DIR/restore.log")"
  fi
  if VM_BAKE_BASE="$second" "$TEST_SCRIPT" restore "$TEST_DIR/all.vmb" > /dev/null 2>&1 && VM_BAKE_BASE="$second" "$TEST_SCRIPT" image record restore img:dev:v1 other 2026-01-01T00:00:00Z open 2>&1 | grep -q "differs"; then
    pass "a second replay keeps identical records (silently); a record that differs is refused"
  else
    fail "record compare: $(VM_BAKE_BASE="$second" "$TEST_SCRIPT" image record restore img:dev:v1 other 2026-01-01T00:00:00Z open 2>&1)"
  fi
}

test_archive_pair() {
  test_header "export and import: the pair (dump sealed to the bundle, MANIFEST), files placed where their kind lives, identical files kept, a differing file or a wrong bundle refused"
  test_setup
  mkdir -p "$TEST_DIR/pkg" "$TEST_DIR/pair"
  run_vmbake setenv VM_BAKE_PKG_DIR "$TEST_DIR/pkg" > /dev/null
  run_vmbake template add freebsd > /dev/null
  run_vmbake template pkgfile add freebsd foo-1.0.pkg > /dev/null
  run_vmbake template pkgfile add freebsd gone-2.0.pkg > /dev/null
  printf 'package\n' > "$TEST_DIR/pkg/foo-1.0.pkg"
  run_vmbake image record write freebsd img:dev:v1 > /dev/null
  run_vmbake guest record write img:dev:v1 g1 172.16.100.5/24 > /dev/null
  run_vmbake guest hostkey ensure g1 > /dev/null 2>&1
  if run_vmbake export pair/dump.sh "$TEST_DIR/pair/bundle.tar.gz" | grep -q "must be absolute"; then
    pass "export refuses a relative path"
  else
    fail "relative path accepted"
  fi
  run_vmbake export "$TEST_DIR/pair/dump.sh" "$TEST_DIR/pair/bundle.tar.gz" > "$TEST_DIR/export.log" 2>&1
  if [ "$(tar tzf "$TEST_DIR/pair/bundle.tar.gz" | tr '\n' ' ')" = "db/hostkey/g1/key db/hostkey/g1/key.pub pkg/foo-1.0.pkg MANIFEST collection " ] && grep -q "not bundled: pkg/gone-2.0.pkg" "$TEST_DIR/export.log"; then
    pass "the bundle carries the host key pair, the package file, MANIFEST and collection; a missing package file is noted"
  else
    fail "bundle: $(tar tzf "$TEST_DIR/pair/bundle.tar.gz" 2>&1 | tr '\n' ' '); $(cat "$TEST_DIR/export.log")"
  fi
  if grep -q "^pkg/foo-1.0.pkg sha256=$(sha256 -q "$TEST_DIR/pkg/foo-1.0.pkg")$" "$TEST_DIR/export/tree/MANIFEST" && [ "$(tail -1 "$TEST_DIR/pair/dump.sh")" = "# Bundle: sha256=$(sha256 -q "$TEST_DIR/pair/bundle.tar.gz") bytes=$(wc -c < "$TEST_DIR/pair/bundle.tar.gz" | tr -d ' ')" ] && grep -q "image record restore 'img:dev:v1'" "$TEST_DIR/pair/dump.sh"; then
    pass "the MANIFEST hashes the files, the dump ends with the seal of this bundle and carries the records"
  else
    fail "manifest/seal: $(cat "$TEST_DIR/export/tree/MANIFEST"); $(tail -2 "$TEST_DIR/pair/dump.sh")"
  fi
  local second="$TEST_BASE_DIR/test-$TESTS_RUN-second"
  mkdir -p "$second" "$TEST_DIR/pkg2"
  VM_BAKE_ROOT="$TEST_BASE_DIR" VM_BAKE_BASE="$second" "$TEST_SCRIPT" bootstrap "test-$TESTS_RUN-second" "$TEST_PROFILE" > /dev/null 2>&1
  VM_BAKE_BASE="$second" "$TEST_SCRIPT" setenv VM_BAKE_TERMINAL_INTERPRETER sh > /dev/null 2>&1
  VM_BAKE_BASE="$second" "$TEST_SCRIPT" setenv VM_BAKE_PKG_DIR "$TEST_DIR/pkg2" > /dev/null 2>&1
  if VM_BAKE_ROOT="$TEST_BASE_DIR" VM_BAKE_BASE="$second" "$TEST_SCRIPT" import "$TEST_DIR/pair/dump.sh" "$TEST_DIR/pair/bundle.tar.gz" > "$TEST_DIR/import.log" 2>&1 && grep -q "3 files placed, 0 already here" "$TEST_DIR/import.log" && cmp -s "$TEST_DIR/hostkey/g1/key" "$second/hostkey/g1/key" && cmp -s "$TEST_DIR/pkg/foo-1.0.pkg" "$TEST_DIR/pkg2/foo-1.0.pkg" && [ "$(stat -f %Lp "$second/hostkey/g1/key")" = "600" ] && [ "$(cat "$second/guest/g1/image")" = "img:dev:v1" ] && [ -d "$TEST_BASE_DIR/incoming/bundle" ]; then
    pass "import verifies, unpacks into incoming, places the key (0600) and the package file, replays the records"
  else
    fail "import: $(grep -v '^$' "$TEST_DIR/import.log" | tail -8)"
  fi
  if VM_BAKE_ROOT="$TEST_BASE_DIR" VM_BAKE_BASE="$second" "$TEST_SCRIPT" import "$TEST_DIR/pair/dump.sh" "$TEST_DIR/pair/bundle.tar.gz" 2>&1 | grep -q "0 files placed, 3 already here"; then
    pass "a second import keeps the identical files and replays idempotently"
  else
    fail "second import"
  fi
  printf 'changed\n' > "$TEST_DIR/pkg/foo-1.0.pkg"
  if ! VM_BAKE_ROOT="$TEST_BASE_DIR" VM_BAKE_BASE="$second" "$TEST_SCRIPT" import "$TEST_DIR/pair/dump.sh" "$TEST_DIR/pair/bundle.tar.gz" > "$TEST_DIR/import3.log" 2>&1 && grep -q "DIFFERS pkg/foo-1.0.pkg" "$TEST_DIR/import3.log" && [ "$(cat "$TEST_DIR/pkg/foo-1.0.pkg")" = "changed" ]; then
    pass "a file here that differs from the bundle's is refused and left alone"
  else
    fail "differs: $(tail -3 "$TEST_DIR/import3.log")"
  fi
  printf 'x' >> "$TEST_DIR/pair/bundle.tar.gz"
  if VM_BAKE_ROOT="$TEST_BASE_DIR" VM_BAKE_BASE="$second" "$TEST_SCRIPT" import "$TEST_DIR/pair/dump.sh" "$TEST_DIR/pair/bundle.tar.gz" 2>&1 | grep -q "MISMATCHED PAIR"; then
    pass "a bundle the dump does not name is refused before anything is unpacked"
  else
    fail "seal verify"
  fi
  if run_vmbake export "$TEST_DIR/pair/dump.sh" "$TEST_DIR/pair/bundle.tar.gz" > /dev/null 2>&1 && [ "$(grep -c '^# Bundle:' "$TEST_DIR/pair/dump.sh")" = "1" ]; then
    pass "export again writes a fresh pair with one seal"
  else
    fail "re-export: $(grep -c '^# Bundle:' "$TEST_DIR/pair/dump.sh") seals"
  fi
}

test_hostkey() {
  test_header "hostkey: a key under a name of its own, bound to at most one guest, kept across a guest's rebuild"
  test_setup
  image_chain
  run_vmbake image record write freebsd-dev img:dev:v1 > /dev/null
  run_vmbake guest record write img:dev:v1 g1 172.16.100.5/24 > /dev/null
  run_vmbake guest record write img:dev:v1 g2 172.16.100.6/24 > /dev/null
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_INTERPRETER_guest_hostkey_write"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake hostkey create k1 > /dev/null 2>&1 && [ "$(stat -f %Lp "$TEST_DIR/hostkey/k1/key")" = "600" ] && [ "$(stat -f %Lp "$TEST_DIR/hostkey/k1/key.pub")" = "644" ] && run_vmbake hostkey list | grep -q "^#   k1 .*SHA256:.* -$"; then
    pass "hostkey create makes the pair (0600/0644), list names it with its fingerprint and no guest"
  else
    fail "hostkey create: $(run_vmbake hostkey list)"
  fi
  if run_vmbake hostkey create k1 2>&1 | grep -q "is already kept" && run_vmbake hostkey create 'bad name' 2>&1 | grep -q "invalid name"; then
    pass "a name that is taken and a name that is no word are refused"
  else
    fail "create guards: $(run_vmbake hostkey create k1 2>&1 | tail -2)"
  fi
  ssh-keygen -q -t ed25519 -N '' -C test -f "$TEST_DIR/outside" 2>/dev/null
  ssh-keygen -q -t rsa -b 2048 -N '' -C test -f "$TEST_DIR/rsa" 2>/dev/null
  if run_vmbake hostkey add k2 "$TEST_DIR/outside" > /dev/null 2>&1 && cmp -s "$TEST_DIR/outside" "$TEST_DIR/hostkey/k2/key" && cmp -s "$TEST_DIR/outside.pub" "$TEST_DIR/hostkey/k2/key.pub"; then
    pass "hostkey add takes an existing pair into the database unchanged"
  else
    fail "hostkey add: $(run_vmbake hostkey add k2 "$TEST_DIR/outside" 2>&1 | tail -2)"
  fi
  if run_vmbake hostkey add k3 relative/key 2>&1 | grep -q "not an absolute path" && run_vmbake hostkey add k3 "$TEST_DIR/no-such-key" 2>&1 | grep -q "not there or not readable" && run_vmbake hostkey add k3 "$TEST_DIR/rsa" 2>&1 | grep -q "not an ed25519 key"; then
    pass "a relative path, a path that is not there and a key of another type are refused"
  else
    fail "add guards: $(run_vmbake hostkey add k3 "$TEST_DIR/rsa" 2>&1 | tail -2)"
  fi
  if run_vmbake guest hostkey use g1 k1 > /dev/null 2>&1 && [ "$(cat "$TEST_DIR/guest/g1/hostkey")" = "k1" ] && run_vmbake hostkey list | grep -q "^#   k1 .* g1$"; then
    pass "guest hostkey use writes the binding, list names the guest that carries it"
  else
    fail "guest hostkey use: $(run_vmbake hostkey list)"
  fi
  if run_vmbake guest hostkey use g2 k1 2>&1 | grep -q "is carried by g1" && [ ! -f "$TEST_DIR/guest/g2/hostkey" ] && run_vmbake guest hostkey use g1 no-such-key 2>&1 | grep -q "unknown hostkey"; then
    pass "a key another guest carries is refused, and so is an unknown one"
  else
    fail "uniqueness: $(run_vmbake guest hostkey use g2 k1 2>&1 | tail -2)"
  fi
  if run_vmbake hostkey drop k1 2>&1 | grep -q "is carried by g1" && [ -f "$TEST_DIR/hostkey/k1/key" ]; then
    pass "hostkey drop refuses a key a guest carries"
  else
    fail "hostkey drop guard: $(run_vmbake hostkey drop k1 2>&1 | tail -2)"
  fi
  if run_vmbake guest hostkey write g1 | grep -q "install -m 600 -o root -g wheel '$TEST_DIR/hostkey/k1/key' " && run_vmbake guest hostkey write g2 2>&1 | grep -q "carries no ssh host key"; then
    pass "guest hostkey write installs the bound key, a guest without a binding is an error"
  else
    fail "guest hostkey write: $(run_vmbake guest hostkey write g1 | tail -3)"
  fi
  if run_vmbake guest hostkey drop g1 > /dev/null 2>&1 && [ ! -f "$TEST_DIR/guest/g1/hostkey" ] && run_vmbake hostkey drop k1 2>&1 | grep -q "removed from the database" && [ ! -d "$TEST_DIR/hostkey/k1" ]; then
    pass "guest hostkey drop lets go of the key, which can then be dropped"
  else
    fail "drop pair: $(run_vmbake hostkey list)"
  fi
  local fp=""
  if run_vmbake guest hostkey ensure g1 > /dev/null 2>&1 && [ "$(cat "$TEST_DIR/guest/g1/hostkey")" = "g1" ] && fp=$(ssh-keygen -l -f "$TEST_DIR/hostkey/g1/key.pub" | cut -d' ' -f2) && [ -n "$fp" ]; then
    pass "guest hostkey ensure makes a key of the guest's name and binds it"
  else
    fail "ensure: $(run_vmbake hostkey list)"
  fi
  run_vmbake guest record remove g1 > /dev/null 2>&1
  run_vmbake guest record write img:dev:v1 g1 172.16.100.5/24 > /dev/null
  if [ -f "$TEST_DIR/hostkey/g1/key" ] && run_vmbake guest hostkey ensure g1 > /dev/null 2>&1 && [ "$(ssh-keygen -l -f "$TEST_DIR/hostkey/g1/key.pub" | cut -d' ' -f2)" = "$fp" ]; then
    pass "the record of the guest goes, the key stays: the guest built anew takes the same identity back"
  else
    fail "rebuild: $(run_vmbake hostkey list)"
  fi
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  local plan
  plan=$(run_vmbake guest hostkey ensure g1)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "1" ] && printf '%s\n' "$plan" | grep -q "comment 'guest g1 carries the hostkey g1'"; then
    pass "a guest that carries a kept key is left alone"
  else
    fail "ensure plan (bound): $plan"
  fi
  rm -f "$TEST_DIR/guest/g1/hostkey"
  plan=$(run_vmbake guest hostkey ensure g1)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "1" ] && printf '%s\n' "$plan" | grep -q "guest hostkey use 'g1' 'g1'"; then
    pass "a guest without a binding takes the kept key of its own name"
  else
    fail "ensure plan (key kept): $plan"
  fi
  rm -rf "$TEST_DIR/hostkey/g1"
  plan=$(run_vmbake guest hostkey ensure g1)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "2" ] && printf '%s\n' "$plan" | sed -n 1p | grep -q "hostkey create 'g1'" && printf '%s\n' "$plan" | sed -n 2p | grep -q "guest hostkey use 'g1' 'g1'"; then
    pass "with neither a binding nor a key it makes one and binds it"
  else
    fail "ensure plan (nothing): $plan"
  fi
  printf 'no-such-key\n' > "$TEST_DIR/guest/g1/hostkey"
  if run_vmbake guest hostkey ensure g1 | grep -q "which is not kept"; then
    pass "a binding whose key is gone is an error, not a silent new key"
  else
    fail "dangling binding: $(run_vmbake guest hostkey ensure g1)"
  fi
}

# linux_chain - a Debian chain beside the FreeBSD one: the cloud image as
# base, cloud-init as bake, a dev template with packages, an env line, an
# rc line (which a Linux image ignores), the host-uid user and the view
linux_chain() {
  run_vmbake template add debian > /dev/null
  run_vmbake template add debian-13 debian > /dev/null
  run_vmbake template base image debian-13 amd64 13 https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.raw 0000000000000000000000000000000000000000000000000000000000000000 > /dev/null
  run_vmbake template bake cloud-init debian-13 > /dev/null
  run_vmbake template add debian-dev debian-13 > /dev/null
  run_vmbake template resource debian-dev 4 8G 32G > /dev/null
  run_vmbake template package add debian-dev git > /dev/null
  run_vmbake template package add debian-dev sudo > /dev/null
  run_vmbake template rc add debian-dev sshd_enable YES > /dev/null
  run_vmbake template env add debian-dev EDITOR vi > /dev/null
  run_vmbake template user add debian-dev "$(id -un)" host > /dev/null
  run_vmbake template service add debian-dev files view > /dev/null
}

test_linux_plan() {
  test_header "linux: image make linux as plans, the cloud image placed, the seed rendered, the guest's seed and MAC"
  test_setup
  image_chain
  linux_chain
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  local plan out disk
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  plan=$(run_vmbake image make linux debian-dev v1)
  if printf '%s\n' "$plan" | grep -q "image make linux from 'debian-dev' 'v1' 'img:debian-dev:v1'" && run_vmbake image make linux img:debian-dev:v1 | grep -q "image make linux from 'debian-dev' 'v1' 'img:debian-dev:v1'" && run_vmbake image make linux debian-dev v1 img:k8s:v1 | grep -q "image make linux from 'debian-dev' 'v1' 'img:k8s:v1'"; then
    pass "the three spellings of image make linux rewrite to image make linux from"
  else
    fail "image make linux spellings: $plan"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  plan=$(run_vmbake image make linux from debian-dev v1 img:debian-dev:v1)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "8" ] && printf '%s\n' "$plan" | sed -n 5p | grep -q "image create cloud 'debian-dev' 'img:debian-dev:v1'" && printf '%s\n' "$plan" | sed -n 6p | grep -q "image firstboot 'img:debian-dev:v1'" && printf '%s\n' "$plan" | sed -n 7p | grep -q "image close cloud 'img:debian-dev:v1'" && printf '%s\n' "$plan" | sed -n 8p | grep -q "image seal 'img:debian-dev:v1'"; then
    pass "image make linux from: note, template, name, free, then create cloud, firstboot, close cloud, seal"
  else
    fail "image make linux from plan: $plan"
  fi
  plan=$(run_vmbake image create cloud debian-dev img:debian-dev:v1)
  if printf '%s\n' "$plan" | grep -q "image check cloud 'debian-dev'" && printf '%s\n' "$plan" | grep -q "image fetch 'https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.raw'" && printf '%s\n' "$plan" | grep -q "image disk place 'img:debian-dev:v1' 'https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.raw' '32G'" && printf '%s\n' "$plan" | grep -n "image record write\|image dataset create\|image disk place" | tr '\n' ' ' | grep -q "record write.* dataset create.* disk place"; then
    pass "image create cloud: the cloud check, the record, the dataset, fetch, verify, the disk placed at the template's disk size"
  else
    fail "image create cloud plan: $plan"
  fi
  plan=$(run_vmbake image firstboot img:debian-dev:v1)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "8" ] && printf '%s\n' "$plan" | sed -n 2p | grep -q "image seed write 'img:debian-dev:v1'" && printf '%s\n' "$plan" | sed -n 5p | grep -q "guest run 'firstboot'" && printf '%s\n' "$plan" | sed -n 6p | grep -q "image firstboot gone" && printf '%s\n' "$plan" | sed -n 8p | grep -q "image firstboot conf drop"; then
    pass "image firstboot: record, seed, conf, link, run, gone, link drop, conf drop"
  else
    fail "image firstboot plan: $plan"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake image check cloud freebsd-dev 2>&1 | grep -q "Error" && [ -z "$(run_vmbake image check cloud debian-dev 2>&1 | grep -v '^#')" ]; then
    pass "image check cloud: a chroot bake is an error, a cloud-init bake on a cloud image passes"
  else
    fail "image check cloud: $(run_vmbake image check cloud freebsd-dev 2>&1 | tail -2)"
  fi
  if pin_image_cat; then
    pass "every image and guest act is pinned to cat in the sandbox"
  else
    fail "acts not pinned to cat -- not calling them"; return
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_INTERPRETER_guest_hostkey_bind" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  run_vmbake setenv VM_BAKE_IMAGE_DIR "$TEST_DIR/img" > /dev/null
  run_vmbake setenv VM_BAKE_IMAGE_CACHE "$TEST_DIR/cache" > /dev/null
  run_vmbake setenv VM_BAKE_GUEST_DIR "$TEST_DIR/gst" > /dev/null
  printf 'ssh-ed25519 AAAATEST test@host\n' > "$TEST_DIR/key.pub"
  run_vmbake setenv VM_BAKE_HOST_KEY "$TEST_DIR/key.pub" > /dev/null
  run_vmbake image record write debian-dev img:debian-dev:v1 > /dev/null
  out=$(run_vmbake image seed write img:debian-dev:v1 2>&1)
  if printf '%s\n' "$out" | grep -q "^instance-id: bake-img:debian-dev:v1$" && printf '%s\n' "$out" | grep -q "^local-hostname: firstboot$" && printf '%s\n' "$out" | grep -q "^#cloud-config$" && printf '%s\n' "$out" | grep -q "^  - git$" && printf '%s\n' "$out" | grep -q "^  - name: $(id -un)$" && printf '%s\n' "$out" | grep -q "^    uid: $(id -u)$" && printf '%s\n' "$out" | grep -q "^      - ssh-ed25519 AAAATEST test@host$" && printf '%s\n' "$out" | grep -q "NOPASSWD:ALL" && printf '%s\n' "$out" | grep -q "^      Port 2222$" && printf '%s\n' "$out" | grep -q "path: /etc/ssh/authorized_keys/$(id -un)$" && printf '%s\n' "$out" | grep -q '^      export EDITOR="vi"$' && printf '%s\n' "$out" | grep -q "^      9pnet_virtio$" && printf '%s\n' "$out" | grep -q "^  - \[home, /home/$(id -un), 9p, 'trans=virtio,version=9p2000.L,rw,_netdev,nofail', '0', '0'\]$" && printf '%s\n' "$out" | grep -q "/home/$(id -un)/git/local, none, 'bind,nofail'" && printf '%s\n' "$out" | grep -q "^  mode: poweroff$" && printf '%s\n' "$out" | grep -q "makefs -t cd9660 -o rockridge -o label=cidata '$TEST_DIR/img/img:debian-dev:v1/seed.iso'" && printf '%s\n' "$out" | grep -q "rc lines are FreeBSD's rc.conf" && printf '%s\n' "$out" | grep "^instance-id\|^#cloud-config\|^write_files:\|^mounts:\|^power_state:" | tr '\n' ' ' | grep -q "instance-id.* #cloud-config.* write_files.* mounts.* power_state"; then
    pass "image seed write: meta-data, then user-data in order -- packages, the host-uid user with the key and sudo, sshd on 2222, the authorized key, the env line, the 9p modules and mounts, poweroff; makefs; the rc lines noted"
  fi
  if printf '%s\n' "$out" | grep -q "^      macaddress: '58:9c:fc:10:64:f9'$" && printf '%s\n' "$out" | grep -q "^      - 172.16.100.249/24$" && printf '%s\n' "$out" | grep -q "^        via: 172.16.100.100$" && printf '%s\n' "$out" | grep "^instance-id\|^version: 2\|^#cloud-config" | tr '\n' ' ' | grep -q "instance-id.* version: 2.* #cloud-config"; then
    pass "image seed write: the network-config of the first boot -- VM_BAKE_FIRSTBOOT_ADDRESS static on its MAC, gateway and nameserver, between meta-data and user-data"
  else
    fail "image seed write: $out"
  fi
  run_vmbake template service drop debian-dev files view > /dev/null
  if run_vmbake image seed view write img:debian-dev:v1 | grep -q "no 'service files view'" && ! run_vmbake image seed sshd write img:debian-dev:v1 | grep -q 9pnet_virtio; then
    pass "without a view: no mounts and no 9p modules"
  else
    fail "seed without view: $(run_vmbake image seed view write img:debian-dev:v1)"
  fi
  run_vmbake template service add debian-dev files view > /dev/null
  run_vmbake template user add debian-dev builder 1002 > /dev/null
  run_vmbake template user add debian-dev other host > /dev/null
  if run_vmbake image seed write img:debian-dev:v1 2>&1 | grep -q "has 2 of them"; then
    pass "a view with two host-uid users is an error"
  else
    fail "two host users: $(run_vmbake image seed write img:debian-dev:v1 2>&1 | tail -2)"
  fi
  run_vmbake template user drop debian-dev other host > /dev/null
  out=$(run_vmbake image disk place img:debian-dev:v1 https://x/debian-13-genericcloud-amd64.raw 32G; run_vmbake image disk place img:debian-dev:v1 https://x/debian-13-generic-amd64.raw.xz 32G; run_vmbake image disk place img:debian-dev:v1 https://x/debian-13-generic-amd64.qcow2 32G 2>&1)
  if printf '%s\n' "$out" | grep -q "^cp '$TEST_DIR/cache/debian-13-genericcloud-amd64.raw' '$TEST_DIR/img/img:debian-dev:v1/disk0.img' || exit 1$" && printf '%s\n' "$out" | grep -q "^xz -dc '$TEST_DIR/cache/debian-13-generic-amd64.raw.xz' > '$TEST_DIR/img/img:debian-dev:v1/disk0.img' || exit 1$" && [ "$(printf '%s\n' "$out" | grep -c "^truncate -s '32G' '$TEST_DIR/img/img:debian-dev:v1/disk0.img' || exit 1$")" = "2" ] && printf '%s\n' "$out" | grep -q "neither raw nor xz"; then
    pass "image disk place: raw copied, xz unpacked, both grown to the disk size, qcow2 refused"
  else
    fail "image disk place: $out"
  fi
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake image firstboot conf img:debian-dev:v1 | grep -q "image firstboot conf 'cloud-init' 'img:debian-dev:v1'" && run_vmbake image firstboot conf cloud-init img:debian-dev:v1 | grep -q "image firstboot conf write 'img:debian-dev:v1' '$TEST_DIR/img/img:debian-dev:v1/seed.iso'" && run_vmbake image firstboot conf chroot img:debian-dev:v1 | grep -q "cloud-init | autoinstall"; then
    pass "image firstboot conf: the bake word from the template, cloud-init hangs the seed.iso on, another word is an error"
  else
    fail "image firstboot conf: $(run_vmbake image firstboot conf img:debian-dev:v1)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  out=$(run_vmbake image firstboot conf write img:debian-dev:v1 "$TEST_DIR/img/img:debian-dev:v1/seed.iso")
  if printf '%s\n' "$out" | grep -q '^cpu=4$' && printf '%s\n' "$out" | grep -q '^memory=8G$' && printf '%s\n' "$out" | grep -q '^network0_mac="58:9c:fc:10:64:f9"$' && printf '%s\n' "$out" | grep -q "^disk0_name=\"$TEST_DIR/img/img:debian-dev:v1/disk0.img\"$" && printf '%s\n' "$out" | grep -q '^disk1_type="ahci-cd"$' && printf '%s\n' "$out" | grep -q "^disk1_name=\"$TEST_DIR/img/img:debian-dev:v1/seed.iso\"$" && printf '%s\n' "$out" | grep -q "$TEST_DIR/gst/firstboot/firstboot.conf" && [ "$(printf '%s\n' "$out" | sed -n "/<<'EOF_CONF'/,/^EOF_CONF/p" | grep -c '^[a-z0-9_]*=')" = "14" ]; then
    pass "image firstboot conf write: the template's resources, the image's disk and seed, under the guests' directory as firstboot"
  else
    fail "firstboot conf: $out"
  fi
  out=$(run_vmbake image firstboot gone)
  if [ "$(printf '%s\n' "$out" | grep -c .)" = "4" ] && printf '%s\n' "$out" | sed -n 1p | grep -q "^n=0; until test -e '$TEST_DIR/gst/firstboot/run.lock' || pgrep -q -f 'bhyve: firstboot\$'; do .* -lt 60 " && printf '%s\n' "$out" | sed -n 3p | grep -q "^n=0; while test -e '$TEST_DIR/gst/firstboot/run.lock' || pgrep -q -f 'bhyve: firstboot\$'; do .* -lt 1800 "; then
    pass "image firstboot gone: waits for run.lock or bhyve to appear (a minute), then for both to leave (an hour)"
  else
    fail "firstboot gone: $out"
  fi
  run_vmbake guest record write img:debian-dev:v1 tirol 172.16.100.110/24 > /dev/null
  run_vmbake image record write freebsd-dev x > /dev/null
  run_vmbake guest record write x caledonia 172.16.100.102/24 > /dev/null
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  out=$(run_vmbake guest disk write chroot caledonia)
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  disk=$(run_vmbake guest disk write tirol)
  if [ "$(printf '%s\n' "$disk" | grep -c .)" = "1" ] && printf '%s\n' "$disk" | grep -q "guest disk write 'cloud-init' 'tirol'" && run_vmbake guest disk write cloud-init tirol | grep -q "guest seed write cloud-init 'tirol'" && run_vmbake guest disk write caledonia | grep -q "guest disk write 'chroot' 'caledonia'" && run_vmbake guest disk write foo caledonia | grep -q "chroot | cloud-init | autoinstall" && [ "$(printf '%s\n' "$out" | grep -c .)" = "3" ] && printf '%s\n' "$out" | grep -n "network write\|home write\|hostkey write" | tr '\n' ' ' | grep -q "1:.*network write.* 2:.*home write.* 3:.*hostkey write"; then
    pass "guest disk write: the bake word from the template (none is chroot); cloud-init rewrites to its seed, chroot to network, home and host key, another word is an error"
  else
    fail "guest disk write: $disk / $out"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  out=$(run_vmbake guest conf write tirol)
  if printf '%s\n' "$out" | grep -q '^network0_mac="58:9c:fc:10:64:6e"$' && printf '%s\n' "$out" | grep -q '^disk1_type="ahci-cd"$' && printf '%s\n' "$out" | grep -q "^disk1_name=\"$TEST_DIR/gst/tirol/seed.iso\"$" && ! run_vmbake guest conf write caledonia | grep -q network0_mac && ! printf '%s\n' "$out" | grep -q 'bhyve_options=.*-w'; then
    pass "guest conf write: a cloud-init guest carries the MAC of its address and the seed as disk1, a chroot guest neither"
  else
    fail "guest conf write cloud: $out"
  fi
  if run_vmbake guest seed write cloud-init tirol 2>&1 | grep -q "carries no ssh host key"; then
    pass "guest seed write without a host key is an error"
  else
    fail "seed without key: $(run_vmbake guest seed write cloud-init tirol 2>&1 | tail -2)"
  fi
  run_vmbake hostkey create k1 > /dev/null 2>&1
  run_vmbake guest hostkey use tirol k1 > /dev/null
  out=$(run_vmbake guest seed write cloud-init tirol 2>&1)
  if printf '%s\n' "$out" | grep -q "^instance-id: tirol$" && printf '%s\n' "$out" | grep -q "^      macaddress: '58:9c:fc:10:64:6e'$" && printf '%s\n' "$out" | grep -q "^      - 172.16.100.110/24$" && printf '%s\n' "$out" | grep -q "^        via: 172.16.100.100$" && printf '%s\n' "$out" | grep -q "^users: \[\]$" && printf '%s\n' "$out" | grep -q "sed 's/^/    /' '$TEST_DIR/hostkey/k1/key'" && ! printf '%s\n' "$out" | grep -q "PRIVATE KEY" && printf '%s\n' "$out" | grep -q "label=cidata '$TEST_DIR/gst/tirol/seed.iso'"; then
    pass "guest seed write: hostname, the address on the MAC's interface, gateway and resolver, no users, the host key read when it runs and never emitted"
  else
    fail "guest seed write: $out"
  fi
}

# openbsd_chain - an OpenBSD chain beside the others: the install ISO as
# base (an empty file in the sandbox), autoinstall as bake, a dev template
# with packages (doas among them, the escalation word), an env line and
# the host-uid user
openbsd_chain() {
  : > "$TEST_DIR/install80.iso"
  run_vmbake template add openbsd > /dev/null
  run_vmbake template add openbsd-8.0 openbsd > /dev/null
  run_vmbake template base iso openbsd-8.0 amd64 "$TEST_DIR/install80.iso" 0000000000000000000000000000000000000000000000000000000000000000 > /dev/null
  run_vmbake template bake autoinstall openbsd-8.0 > /dev/null
  run_vmbake template add openbsd-dev openbsd-8.0 > /dev/null
  run_vmbake template resource openbsd-dev 4 4G 40G > /dev/null
  run_vmbake template package add openbsd-dev git > /dev/null
  run_vmbake template package add openbsd-dev doas > /dev/null
  run_vmbake template env add openbsd-dev EDITOR vi > /dev/null
  run_vmbake template user add openbsd-dev "$(id -un)" host > /dev/null
}

test_openbsd_plan() {
  test_header "openbsd: image make openbsd as plans, the response file, the site set, the console driver, the guest's seed"
  test_setup
  image_chain
  openbsd_chain
  local plan out img="img:openbsd-dev:v1"
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER"
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake template bake autoinstall openbsd-8.0 | grep -q "template leaf record 'openbsd-8.0' bake autoinstall" && run_vmbake template bake foo openbsd-8.0 | grep -q "chroot | cloud-init | autoinstall"; then
    pass "template bake autoinstall records the bake, an unknown way names the three"
  else
    fail "template bake autoinstall: $(run_vmbake template bake foo openbsd-8.0)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  plan=$(run_vmbake image make openbsd openbsd-dev v1)
  if printf '%s\n' "$plan" | grep -q "image make openbsd from 'openbsd-dev' 'v1' '$img'" && run_vmbake image make openbsd $img | grep -q "image make openbsd from 'openbsd-dev' 'v1' '$img'" && run_vmbake image make openbsd openbsd-dev v1 img:k8s:v1 | grep -q "image make openbsd from 'openbsd-dev' 'v1' 'img:k8s:v1'"; then
    pass "the three spellings of image make openbsd rewrite to image make openbsd from"
  else
    fail "image make openbsd spellings: $plan"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  plan=$(run_vmbake image make openbsd from openbsd-dev v1 $img)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "8" ] && printf '%s\n' "$plan" | sed -n 5p | grep -q "image create iso 'openbsd-dev' '$img'" && printf '%s\n' "$plan" | sed -n 6p | grep -q "image install '$img'" && printf '%s\n' "$plan" | sed -n 7p | grep -q "image close iso '$img'" && printf '%s\n' "$plan" | sed -n 8p | grep -q "image seal '$img'"; then
    pass "image make openbsd from: note, template, name, free, then create iso, install, close iso, seal"
  else
    fail "image make openbsd from plan: $plan"
  fi
  plan=$(run_vmbake image create iso openbsd-dev $img)
  if printf '%s\n' "$plan" | grep -q "image check autoinstall 'openbsd-dev'" && printf '%s\n' "$plan" | tail -1 | grep -q "image disk create '$img' '40G'" && printf '%s\n' "$plan" | grep -n "image record write\|image dataset create\|image disk create" | tr '\n' ' ' | grep -q "record write.* dataset create.* disk create" && ! printf '%s\n' "$plan" | grep -q "image fetch"; then
    pass "image create iso: the autoinstall check, the record, the dataset, an empty disk of the template's disk size, nothing fetched"
  else
    fail "image create iso plan: $plan"
  fi
  run_vmbake image record write openbsd-dev $img > /dev/null
  plan=$(run_vmbake image install $img)
  if [ "$(printf '%s\n' "$plan" | grep -c .)" = "11" ] && printf '%s\n' "$plan" | sed -n 2p | grep -q "image response write '$img'" && printf '%s\n' "$plan" | sed -n 4p | grep -q "image site pack '$img'" && printf '%s\n' "$plan" | sed -n 5p | grep -q "image firstboot conf '$img'" && printf '%s\n' "$plan" | sed -n 7p | grep -q "guest install 'firstboot' '$TEST_DIR/install80.iso'" && printf '%s\n' "$plan" | sed -n 8p | grep -q "image console drive '$img'" && printf '%s\n' "$plan" | sed -n 9p | grep -q "image firstboot gone" && printf '%s\n' "$plan" | sed -n 11p | grep -q "image firstboot conf drop"; then
    pass "image install: record, response, site, pack, conf, link, install from the ISO, console, gone, link drop, conf drop"
  else
    fail "image install plan: $plan"
  fi
  printf '%s\n' 'env VM_BAKE_PIN_PROBE=1 $VM_BAKE_BATCH_COMBINATOR_INTERPRETER' > "$TEST_DIR/.env/local/VM_BAKE_INTERPRETER_image_install"
  out=$(run_vmbake image install $img)
  if [ "$out" = "$plan" ]; then
    pass "image install pin: a pin naming \$VM_BAKE_BATCH_COMBINATOR_INTERPRETER expands to the class default before it runs -- 'sudo -E \$VM_BAKE_BATCH_COMBINATOR_INTERPRETER' puts the whole bake under one sudo"
  else
    fail "image install pin: $out"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_INTERPRETER_image_install"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_BATCH_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  mv "$TEST_DIR/install80.iso" "$TEST_DIR/install80.iso.away"
  if run_vmbake image check autoinstall freebsd-dev 2>&1 | grep -q "Error" && run_vmbake image check autoinstall debian-dev 2>&1 | grep -q "Error" && run_vmbake image check autoinstall openbsd-dev 2>&1 | grep -q "Error" && mv "$TEST_DIR/install80.iso.away" "$TEST_DIR/install80.iso" && [ -z "$(run_vmbake image check autoinstall openbsd-dev 2>&1 | grep -v '^#')" ]; then
    pass "image check autoinstall: a release base, a cloud image and a missing ISO are errors, a readable install ISO with the bake autoinstall passes"
  else
    fail "image check autoinstall: $(run_vmbake image check autoinstall openbsd-dev 2>&1 | tail -2)"
  fi
  if pin_image_cat; then
    pass "every image and guest act is pinned to cat in the sandbox"
  else
    fail "acts not pinned to cat -- not calling them"; return
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_INTERPRETER_guest_hostkey_bind" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  run_vmbake setenv VM_BAKE_IMAGE_DIR "$TEST_DIR/img" > /dev/null
  run_vmbake setenv VM_BAKE_GUEST_DIR "$TEST_DIR/gst" > /dev/null
  printf 'ssh-ed25519 AAAATEST test@host\n' > "$TEST_DIR/key.pub"
  run_vmbake setenv VM_BAKE_HOST_KEY "$TEST_DIR/key.pub" > /dev/null
  out=$(run_vmbake image response write $img 2>&1)
  if printf '%s\n' "$out" | grep -q "^System hostname = firstboot$" && printf '%s\n' "$out" | grep -q "^IPv4 address for vio0 = 172.16.100.249$" && printf '%s\n' "$out" | grep -q "^Netmask for vio0 = 255.255.255.0$" && printf '%s\n' "$out" | grep -q "^Default IPv4 route = 172.16.100.100$" && printf '%s\n' "$out" | grep -q "^Setup a user = no$" && printf '%s\n' "$out" | grep -q "^Do you expect to run the X Window System = no$" && printf '%s\n' "$out" | grep -q "^Location of sets = @INSTCD@$" && printf '%s\n' "$out" | grep -q "^Location of sets = @SITECD@$" && printf '%s\n' "$out" | grep -q "^INSTALL.amd64 not found. Use sets found here anyway = yes$" && [ "$(printf '%s\n' "$out" | grep -c "^Directory does not contain SHA256.sig. Continue without verification = yes$")" = "2" ] && printf '%s\n' "$out" | grep -q "^Pathname to the sets = 8.0/amd64/$" && printf '%s\n' "$out" | grep -n "^Set name(s) = " | tr '\n' ' ' | grep -q "= -x\*.* = done.* = site80.tgz.* = done" && printf '%s\n' "$out" | grep -q "install -d -m 700 '$TEST_DIR/img/$img/site/8.0/amd64'"; then
    pass "image response write: the bake's hostname and static address, no user, no X, the sets from the install CD without X, the site set from the site CD taken without INSTALL.amd64, both CDs taken without SHA256.sig, the release directory from the ISO's name"
  else
    fail "image response write: $out"
  fi
  out=$(run_vmbake image site write $img 2>&1)
  if printf '%s\n' "$out" | grep -q "^sed -i -E 's/\^\[\[:space:\]\]\*(Port|PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|AuthorizedKeysFile|X11Forwarding)\[\[:space:\]\]/#&/' /etc/ssh/sshd_config$" && printf '%s\n' "$out" | grep -q "^Port 2222$" && printf '%s\n' "$out" | grep -q "^useradd -m -u $(id -u) -G wheel -s /bin/ksh '$(id -un)'$" && printf '%s\n' "$out" | grep -q "ssh-ed25519 AAAATEST test@host' > '/etc/ssh/authorized_keys/$(id -un)'" && printf '%s\n' "$out" | grep -q "^permit nopass keepenv $(id -un) as root$" && printf '%s\n' "$out" | grep -q "^pkg_add -I git 2>&1" && ! printf '%s\n' "$out" | grep -q "pkg_add.*doas" && printf '%s\n' "$out" | grep -q '^export EDITOR="vi"$' && printf '%s\n' "$out" | grep -q "^usermod -p '\*' root$" && printf '%s\n' "$out" | grep -q "'!/usr/local/libexec/vm-bake-seed' > /etc/hostname.vio0" && printf '%s\n' "$out" | grep -q "^shutdown -p now$" && ! printf '%s\n' "$out" | grep -q "^X11Forwarding"; then
    pass "image site write: sshd on the port, the host-uid user with the key, doas from the word (not a package), the env line, root locked, the seed hook as hostname.vio0, the packages and the power-off at the first boot, no X11"
  else
    fail "image site write: $out"
  fi
  out=$(run_vmbake image site pack $img 2>&1)
  if printf '%s\n' "$out" | grep -q "bsdtar -czf '$TEST_DIR/img/$img/site/8.0/amd64/site80.tgz' --uid 0 --gid 0 --uname root --gname wheel -C '$TEST_DIR/img/$img/site.d' install.site" && printf '%s\n' "$out" | grep -q "sha256 site80.tgz > SHA256" && printf '%s\n' "$out" | grep -q "label=vmbakesite '$TEST_DIR/img/$img/site.iso' '$TEST_DIR/img/$img/site'"; then
    pass "image site pack: the set as root:wheel under the release directory, its SHA256, the site directory as site.iso"
  else
    fail "image site pack: $out"
  fi
  out=$(run_vmbake image firstboot conf write $img "$TEST_DIR/img/$img/site.iso")
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if printf '%s\n' "$out" | grep -q '^cpu=4$' && printf '%s\n' "$out" | grep -q '^memory=4G$' && printf '%s\n' "$out" | grep -q "^disk1_name=\"$TEST_DIR/img/$img/site.iso\"$" && printf '%s\n' "$out" | grep -q '^bhyve_options="-w"$' && ! printf '%s\n' "$out" | grep -q "install80" && run_vmbake image firstboot conf $img | grep -q "image firstboot conf 'autoinstall' '$img'" && run_vmbake image firstboot conf autoinstall $img | grep -q "image firstboot conf write '$img' '$TEST_DIR/img/$img/site.iso'"; then
    pass "image firstboot conf: autoinstall hangs the site.iso on as the one CD, the install ISO is not in the configuration"
  else
    fail "firstboot conf autoinstall: $out"
  fi
  if run_vmbake image console drive $img | grep -q "image console drive 'nmdm' '$img'" && run_vmbake setenv VM_BAKE_CONSOLE tmux > /dev/null && run_vmbake image console drive $img | grep -q "image console drive 'tmux' '$img'" && run_vmbake image console drive foo $img | grep -q "tmux | nmdm"; then
    pass "image console drive: VM_BAKE_CONSOLE picks the driver, nmdm by default, another word is an error"
  else
    fail "image console drive: $(run_vmbake image console drive $img)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  out=$(run_vmbake image console drive tmux $img 2>&1)
  plan=$(run_vmbake image console drive nmdm $img 2>&1)
  if printf '%s\n' "$out" | grep -q "^g='firstboot'$" && printf '%s\n' "$out" | grep -q 'tmux send-keys -t "$g"' && printf '%s\n' "$out" | grep -q "^wait_for 'boot>' 120$" && printf '%s\n' "$out" | grep -q "s/@INSTCD@/\$i/;s/@SITECD@/\$s/" && printf '%s\n' "$out" | grep -q "^send 'a'$" && printf '%s\n' "$out" | grep -q "^wait_for 'CONGRATULATIONS' 1800$" && printf '%s\n' "$plan" | grep -q "dev='/dev/nmdm-firstboot.1B' log='$TEST_DIR/gst/firstboot/console.log'" && printf '%s\n' "$plan" | grep -q "^wait_for 'CONGRATULATIONS' 1800$" && [ "$(printf '%s\n' "$out$plan" | grep -c '^wait_for .rebooted by root. 120$')" = "2" ] && [ "$(printf '%s\n' "$out$plan" | grep -c '^vm start "$g" >&2 || give_up')" = "2" ] && [ "$(printf '%s\n' "$out$plan" | grep -c 'failed; check /tmp/ai/ai.log" >/dev/null && give_up')" = "2" ] && printf '%s\n' "$plan" | grep -q '^exec 3<> "$dev"; stty raw -echo <&3$' && printf "%s\\n" "$plan" | grep -q "tr -d .\\\\r. | cat -v; }" && printf '%s\n' "$plan" | grep -q '^send() { printf "%s\\r" "$1" >&3; }$' && [ "$(printf '%s\n' "$out$plan" | grep -c '^give_up() .*vm poweroff -f "$g"')" = "2" ] && [ "$(printf '%s\n' "$out$plan" | grep -c '^n=0; until booting; do .*send "${bs}boot"; m=0; until booting || test "$m" -ge 5')" = "2" ] && [ "$(printf '%s\n' "$out" | grep -c '^send \|^wait_')" = "$(printf '%s\n' "$plan" | grep -c '^send \|^wait_')" ] && printf '%s\n' "$out" | grep -q 'mount_cd9660 /dev/${s}a /mnt' && ! printf '%s\n' "$out" | grep -q 'mount_cd9660 -r'; then
    pass "image console drive tmux and nmdm: the same dialogue -- com0, boot, the shell fills the CD names into the response file, autoinstall, CONGRATULATIONS -- over the session or the raw, echo-free device held open; both power the guest off when a wait runs out; boot is sent until the loader reports booting; after the install's reboot the guest is powered off and started from its disk; the installer's failure line ends a wait at once; mount_cd9660 without -r (OpenBSD has none)"
  else
    fail "console drive: $out / $plan"
  fi
  run_vmbake guest record write $img istria 172.16.100.120/24 > /dev/null
  printf 'cat\n' > "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER"
  rm -f "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  if run_vmbake guest disk write istria | grep -q "guest disk write 'autoinstall' 'istria'" && run_vmbake guest disk write autoinstall istria | grep -q "guest seed write autoinstall 'istria'"; then
    pass "guest disk write: an autoinstall guest gets the autoinstall seed"
  else
    fail "guest disk write autoinstall: $(run_vmbake guest disk write istria)"
  fi
  rm -f "$TEST_DIR/.env/local/VM_BAKE_COMBINATOR_INTERPRETER" "$TEST_DIR/.env/local/VM_BAKE_CACHE_ENV_ARGS"
  out=$(run_vmbake guest conf write istria)
  if printf '%s\n' "$out" | grep -q '^network0_mac="58:9c:fc:10:64:78"$' && printf '%s\n' "$out" | grep -q "^disk1_name=\"$TEST_DIR/gst/istria/seed.iso\"$" && printf '%s\n' "$out" | grep -q '^bhyve_options="-w"$'; then
    pass "guest conf write: an autoinstall guest carries the MAC of its address and the seed as disk1"
  else
    fail "guest conf write autoinstall: $out"
  fi
  if run_vmbake guest seed write autoinstall istria 2>&1 | grep -q "carries no ssh host key"; then
    pass "guest seed write autoinstall without a host key is an error"
  else
    fail "autoinstall seed without key: $(run_vmbake guest seed write autoinstall istria 2>&1 | tail -2)"
  fi
  run_vmbake hostkey create k1 > /dev/null 2>&1
  run_vmbake guest hostkey use istria k1 > /dev/null
  out=$(run_vmbake guest seed write autoinstall istria 2>&1)
  if printf '%s\n' "$out" | grep -q "'istria.local' > '$TEST_DIR/gst/istria/seed/myname'" && printf '%s\n' "$out" | grep -q "'172.16.100.120' > '$TEST_DIR/gst/istria/seed/address'" && printf '%s\n' "$out" | grep -q "'255.255.255.0' > '$TEST_DIR/gst/istria/seed/netmask'" && printf '%s\n' "$out" | grep -q "'172.16.100.100' > '$TEST_DIR/gst/istria/seed/mygate'" && printf '%s\n' "$out" | grep -q "cp '$TEST_DIR/hostkey/k1/key' '$TEST_DIR/gst/istria/seed/ssh_host_ed25519_key'" && ! printf '%s\n' "$out" | grep -q "PRIVATE KEY" && printf '%s\n' "$out" | grep -q "label=vmbakeseed '$TEST_DIR/gst/istria/seed.iso'"; then
    pass "guest seed write autoinstall: the marker, myname in the domain, address and netmask, gateway, the host key copied when it runs and never emitted"
  else
    fail "guest seed write autoinstall: $out"
  fi
  out=$(run_vmbake guest install firstboot /x/install80.iso)
  if printf '%s\n' "$out" | grep -q "^vm install 'firstboot' '/x/install80.iso' || exit 1$"; then
    pass "guest install: vm install with the ISO for this one run"
  else
    fail "guest install: $out"
  fi
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
  should_run_test test_home_plan
  should_run_test test_view_plan
  should_run_test test_view_acts
  should_run_test test_repo_plan
  should_run_test test_guest_report
  should_run_test test_dowry
  should_run_test test_dowry_place
  should_run_test test_hostkey
  should_run_test test_linux_plan
  should_run_test test_openbsd_plan
  should_run_test test_dump_witness
  should_run_test test_archive_pair

  test_summary
}

main
exit $?
