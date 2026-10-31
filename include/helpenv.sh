#!/bin/sh
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# vm-bake helpenv - documentation access for environment variables. Each
# file template/environment/<VAR> (and its copies under .env/{local,default})
# holds the effective value on line 1 and the documentation on lines 2+;
# getenv shows line 1, help env shows value and documentation through the
# same cascade (env_resolve_file), so the two can never drift.

#@help _help_env0
# @command help env [<name> [<location>]]
# @summary Text terminal: the documented variables (templates, and the copies under .env); show one with 'help env <name>' -- the name resolves literal, then VM_BAKE_<name>, then VM_BAKE_INTERPRETER_<name>
# @group   configuration
# @param   name      variable name (full, or short for VM_BAKE_ / VM_BAKE_INTERPRETER_)
# @param   location  the layer to inspect: local | default | template
# @env     VM_BAKE_TEMPLATE_DIR  where the shipped variable templates (and their docs) live
# @example vm-bake help env FREEBSD_SRC
# @see     getenv
# @see     help intp
#@end
_help_env0() {
        printf '%s\n' "Documented environment variables -- show one with: help env <name>" ""
        {
                ls "$VM_BAKE_TEMPLATE_DIR/environment" 2>/dev/null
                ls "$VM_BAKE_BASE/.env/default" 2>/dev/null
                ls "$VM_BAKE_BASE/.env/local" 2>/dev/null
        } | sort -u | sed 's/^/  /'
}

#@help __help_env1
# @internal arity-1 of 'help env' (help env <name>): the name resolves to a documented variable (literal, VM_BAKE_<name>, VM_BAKE_INTERPRETER_<name>) -> rewrite to 'help env <variable> <effective layer>', else an error line
#@end
__help_env1() {
        local cand="" var=""
        for cand in "$1" "VM_BAKE_$1" "VM_BAKE_INTERPRETER_$1"; do
                env_resolve_file "$cand" > /dev/null 2>&1 && var=$cand && break
        done
        if test -n "$var"; then
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" help env '$var' '$(env_resolve_file "$var" | sed -n 1p)'"
        else
                printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" error 'No documented environment variable: $1'"
        fi
}

#@help _help_env2
# @internal arity-2 of 'help env' (help env <name> <location>): the variable's source (layer and file), its value and its documentation (lines 2+ of the shown file, or of the first deeper layer that documents anything; @tags as labelled sections; VM_BAKE_TEMPLATE_DIR)
#@end
_help_env2() {
        local resolved="" layer="" path="" doc="" l="" d=""
        resolved=$(env_resolve_file "$1" "$2" 2>/dev/null)
        layer=$(printf '%s\n' "$resolved" | sed -n 1p)
        path=$(printf '%s\n' "$resolved" | sed -n 2p)
        for l in "$layer" default template; do
                d=$(env_resolve_file "$1" "$l" 2>/dev/null | sed -n 2p)
                test -n "$d" && tail -n +2 "$d" | grep -q '[^[:space:]]' && doc=$d && break
        done
        test -n "$doc" || doc=$path
        if test -z "$resolved"; then
                printf '# %s: no value in location: %s\n' "$1" "$2"
        else
                printf '# Source: %s (%s)\n' "$path" "$(printf '%s' "$layer" | sed 's/^local$/override/')"
                printf '%s = %s\n\n' "$1" "$(head -n 1 "$path")"
                test "$doc" = "$path" || printf '# (documentation from %s)\n' "$(basename "$(dirname "$doc")")"
                tail -n +2 "$doc" | awk -f "$VM_BAKE_TEMPLATE_DIR/awk/env-doc.awk"
        fi
}
