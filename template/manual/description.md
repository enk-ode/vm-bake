# DESCRIPTION

**vm-bake** turns a declared template into an image, a guest and the
host-side plumbing around it, reproducibly. A *template* is the build
recipe: operating system base, packages, configuration, users, the host
services a guest may use, resources, lifetime; templates inherit from a
parent down to the root `empty`. An *image* is what baking a template
yields, a *guest* a clone of an image with its rendered vm.conf, a
*session* the client script that brings one application of the guest onto
the host desktop. There is one home, the host's: a guest whose template
says `service files view` mounts a *view* of it over virtio-9p, sees of the
rest what the template's home lines allow, and works in its own clones of
the host's repositories. Starting and stopping guests stays with vm-bhyve.

Four ways bake an image, chosen by the template's `bake` word: `chroot`
(FreeBSD: pkgbase into the mounted disk, on the host or in a builder
guest, no first boot), `cloud-init` (Linux: a cloud image and a seed CD,
one first boot), `autoinstall` (OpenBSD: the install ISO with a response
file and a site set on a second CD, the console driven) and `apkovl`
(Alpine: the live ISO and an overlay on a second CD, unattended). Every
way ends with the first boot reporting its packages on the console; a
missing package ends the bake with an error naming it.

Every command GENERATES shell text; an interpreter the user pins decides
whether that text is displayed (the default, `cat`) or executed. The
bookkeeping of the templates is pinned to act; the bake, once there, shows
its shell first. All records live in a database (`~/.vm-bake/db` by
default) that dumps and restores as replay lines.
