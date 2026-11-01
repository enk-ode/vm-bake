#!/bin/sh
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# vm-bake intp - interpreter sugar (setintp / getintp / help intp): a token
# names an interpreter variable (a class default from template/tbl/intp.tbl, or
# the per-function pin VM_BAKE_INTERPRETER_<function>), and the command
# rewrites to setenv / getenv / help env of that variable.

#@help __setintp2
# @command setintp <function> <interpreter>
# @summary Pin a function's interpreter: rewrite to 'setenv <variable> <interpreter>' (the variable from the token). Pin functions, not the batch class: with batch pinned to cat, setenv and unsetenv (batches themselves) only display, and the way back is the terminal 'unsetenv erase <variable>'
# @group   configuration
# @param   function     a class default (terminal | combinator | batch) or a function name (e.g. stage_deploy_write)
# @param   interpreter  cat | sh | sudo sh | ...
# @example vm-bake setintp stage_deploy_write 'sudo sh'
# @see     getintp
# @see     setenv
# @env     VM_BAKE_TEMPLATE_DIR  the template directory (awk programs, tables)
# @env     VM_BAKE_INTERPRETER_  the per-function pin prefix: VM_BAKE_INTERPRETER_<function> when the token names no class
#@end
__setintp2() {
        local var=""
        var=$(awk -v t="$(printf '%s' "$1" | tr 'A-Z' 'a-z')" '$1 == t { print $2 }' "$VM_BAKE_TEMPLATE_DIR/tbl/intp.tbl" 2>/dev/null)
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setenv ${var:-VM_BAKE_INTERPRETER_$1} $(sq "$2")"
}

#@help __getintp1
# @command getintp <function>
# @summary Show a function's pinned interpreter: rewrite to 'getenv <variable>'
# @group   configuration
# @example vm-bake getintp stage_deploy_write
# @see     setintp
# @see     getenv
# @env     VM_BAKE_TEMPLATE_DIR  the template directory (awk programs, tables)
# @env     VM_BAKE_INTERPRETER_  the per-function pin prefix: VM_BAKE_INTERPRETER_<function> when the token names no class
#@end
__getintp1() {
        local var=""
        var=$(awk -v t="$(printf '%s' "$1" | tr 'A-Z' 'a-z')" '$1 == t { print $2 }' "$VM_BAKE_TEMPLATE_DIR/tbl/intp.tbl" 2>/dev/null)
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" getenv ${var:-VM_BAKE_INTERPRETER_$1}"
}

#@help __help_intp1
# @command help intp <function> [<location>]
# @summary Show the documentation of an interpreter variable (class default or per-function): rewrite to 'help env <variable>'
# @group   configuration
# @param   function  a class default (terminal | combinator | batch) or a function name
# @param   location  the layer to inspect: local | default | template
# @example vm-bake help intp stage_deploy_write
# @see     help env
# @env     VM_BAKE_TEMPLATE_DIR  the template directory (awk programs, tables)
# @env     VM_BAKE_INTERPRETER_  the per-function pin prefix: VM_BAKE_INTERPRETER_<function> when the token names no class
#@end
__help_intp1() {
        local var=""
        var=$(awk -v t="$(printf '%s' "$1" | tr 'A-Z' 'a-z')" '$1 == t { print $2 }' "$VM_BAKE_TEMPLATE_DIR/tbl/intp.tbl" 2>/dev/null)
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" help env ${var:-VM_BAKE_INTERPRETER_$1}"
}

#@help __help_intp2
# @internal arity-2 of 'help intp' (a forced layer): rewrite to 'help env <variable> <location>'
#@end
__help_intp2() {
        local var=""
        var=$(awk -v t="$(printf '%s' "$1" | tr 'A-Z' 'a-z')" '$1 == t { print $2 }' "$VM_BAKE_TEMPLATE_DIR/tbl/intp.tbl" 2>/dev/null)
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" help env ${var:-VM_BAKE_INTERPRETER_$1} '$2'"
}

#@help __unsetintp1
# @command unsetintp <function>
# @summary Drop a function's local interpreter pin: rewrite to 'unsetenv <variable>' (the variable from the token); the default of the profile applies again
# @group   configuration
# @param   function  a class default (terminal | combinator | batch) or a function name (e.g. image_pkg_base)
# @example vm-bake unsetintp batch
# @example vm-bake unsetintp image_pkg_base
# @see     setintp
# @see     unsetenv
# @env     VM_BAKE_TEMPLATE_DIR  the template directory (awk programs, tables)
# @env     VM_BAKE_INTERPRETER_  the per-function pin prefix: VM_BAKE_INTERPRETER_<function> when the token names no class
#@end
__unsetintp1() {
        local var=""
        var=$(awk -v t="$(printf '%s' "$1" | tr 'A-Z' 'a-z')" '$1 == t { print $2 }' "$VM_BAKE_TEMPLATE_DIR/tbl/intp.tbl" 2>/dev/null)
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" unsetenv ${var:-VM_BAKE_INTERPRETER_$1}"
}
