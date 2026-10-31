# Working on vm-bake

vm-bake is a standalone tool: its engine (dispatch, interpreter pins, the
layered environment, the batch runner, bootstrap, the generated help) lives
in this repository under `include/`, forked from elvboot and renamed. The
first rule of the architecture test keeps it that way: the name of the
engine it was forked from does not occur in this code base. Nothing here
depends on another tool at run time.

The engine's doctrine applies: three function classes (`_` terminal emits
shell, `__` combinator emits one re-invocation, `___` batch emits a
sequence), no helpers, an enum is a word in the command path with one
function per word, records are immutable (drop, then add), every anchor
carries a help block (`#@help ... #@end`), and the architecture suite
enforces all of it.

After adding or renaming anchors:

    make metadata
    make check
    make test

`make metadata` rewrites the tables in `vm-bake.sh` and in both suites;
commit the result with the change. The unit suite bootstraps a sandbox
database per test under `$TMPDIR`; vm-bake execs its own script, so the
checkout must lie where exec is allowed.

A development install is a wrapper that execs this checkout:

    make PREFIX=$HOME install        -> ~/bin/vm-bake
