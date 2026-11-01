#!/bin/sh
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Dr. Johannes Brügmann
# vm-bake intp - interpreter sugar (setintp / getintp / unsetintp / help intp):
# the token is a function name, the variable is its pin
# VM_BAKE_INTERPRETER_<function>, and the command rewrites to setenv / getenv /
# unsetenv / help env of that variable. Nothing else: the class defaults
# (VM_BAKE_TERMINAL_INTERPRETER, VM_BAKE_COMBINATOR_INTERPRETER,
# VM_BAKE_BATCH_COMBINATOR_INTERPRETER) are set with setenv by their name.

#@help __setintp2
# @command setintp <function> <interpreter>
# @summary Pin a function's interpreter: rewrite to 'setenv VM_BAKE_INTERPRETER_<function> <interpreter>' -- sugar for the pin's name, nothing more; a class default is set with setenv by its own name
# @group   configuration
# @param   function     a function name, with or without its arity digit (e.g. image_pkg_base, template_mint)
# @param   interpreter  cat | sh | sudo sh | ...
# @example vm-bake setintp image_pkg_base cat
# @see     getintp
# @see     unsetintp
# @see     setenv
# @env     VM_BAKE_INTERPRETER_  the per-function pin prefix
#@end
__setintp2() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" setenv VM_BAKE_INTERPRETER_$1 $(sq "$2")"
}

#@help __getintp1
# @command getintp <function>
# @summary Show a function's pinned interpreter: rewrite to 'getenv VM_BAKE_INTERPRETER_<function>'
# @group   configuration
# @example vm-bake getintp image_pkg_base
# @see     setintp
# @see     getenv
# @env     VM_BAKE_INTERPRETER_  the per-function pin prefix
#@end
__getintp1() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" getenv VM_BAKE_INTERPRETER_$1"
}

#@help __unsetintp1
# @command unsetintp <function>
# @summary Drop a function's local interpreter pin: rewrite to 'unsetenv VM_BAKE_INTERPRETER_<function>'; the default of the profile applies again
# @group   configuration
# @example vm-bake unsetintp image_pkg_base
# @see     setintp
# @see     unsetenv
# @env     VM_BAKE_INTERPRETER_  the per-function pin prefix
#@end
__unsetintp1() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" unsetenv VM_BAKE_INTERPRETER_$1"
}

#@help __help_intp1
# @command help intp <function> [<location>]
# @summary Show the documentation of a function's interpreter pin: rewrite to 'help env VM_BAKE_INTERPRETER_<function>'
# @group   configuration
# @param   location  the layer to inspect: local | default | template
# @example vm-bake help intp image_pkg_base
# @see     help env
# @env     VM_BAKE_INTERPRETER_  the per-function pin prefix
#@end
__help_intp1() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" help env VM_BAKE_INTERPRETER_$1"
}

#@help __help_intp2
# @internal arity-2 of 'help intp' (a forced layer): rewrite to 'help env VM_BAKE_INTERPRETER_<function> <location>'
#@end
__help_intp2() {
        printf '%s\n' "\"\$VM_BAKE_CONTEXT_SCRIPT\" help env VM_BAKE_INTERPRETER_$1 '$2'"
}
