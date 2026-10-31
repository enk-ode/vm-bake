# DESCRIPTION

**vm-bake** turns a declared template into an image, a guest and the
host-side plumbing around it, reproducibly. A *template* is the build
recipe: operating system base, packages, configuration, users, the host
services a guest may use, resources, lifetime; templates inherit from a
parent down to the root `empty`. An *image* is what baking a template
yields, a *guest* a clone of an image with its rendered vm.conf, a
*session* the client script that brings one application of the guest onto
the host desktop. Starting and stopping guests stays with vm-bhyve.

Every command GENERATES shell text; an interpreter the user pins decides
whether that text is displayed (the default, `cat`) or executed. The
bookkeeping of the templates is pinned to act; the bake, once there, shows
its shell first. All records live in a database (`~/.vm-bake/db` by
default) that dumps and restores as replay lines.
