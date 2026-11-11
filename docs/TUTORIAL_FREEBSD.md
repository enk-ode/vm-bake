# Tutorial: the chroot way -- a FreeBSD image from pkgbase

One topic: baking a FreeBSD image from the pkgbase repository of a release
and putting a guest on it. The chroot way is the first of vm-bake's four
ways: the image's disk is partitioned, formatted and mounted, the base
system installed into it with `pkg -r`, the template's packages and
configuration applied in the mounted tree, the disk closed and sealed. No
first boot: everything the guest is, it is before it ever runs.

Prerequisites: `TUTORIAL_QUICKSTART.md` -- a bootstrapped database, the
host's pins in place.

## The chain of templates

Decisions go into templates that inherit from a parent down to `empty`.
The base and the bake are scalars (the nearest ancestor that sets them
wins), packages and the rest are lists (the union of the chain minus the
masks):

    vm-bake template add freebsd
    vm-bake template bake chroot freebsd
    vm-bake template add freebsd-15.1 freebsd
    vm-bake template base release freebsd-15.1 amd64 15.1-RELEASE
    vm-bake template add freebsd-dev freebsd-15.1
    vm-bake template resource freebsd-dev 4 8G 40G
    vm-bake template package add freebsd-dev git
    vm-bake template package add freebsd-dev doas
    vm-bake template rc add freebsd-dev sshd_enable YES
    vm-bake template user add freebsd-dev brj host
    vm-bake template show freebsd-dev

`base release` names a release that pkgbase carries; `resource` is cpu,
memory and disk. A user with the uid word `host` gets the invoking user's
uid, so files the guest writes into a shared home belong to the right
person on both sides. `doas` in the package list gives every user doas
without a password; without it the guest has no way to root. Every user
gets `VM_BAKE_HOST_KEY` as their authorized key; the image knows no
passwords, and root is locked.

## The builder

A host at securelevel 1 cannot install pkgbase: FreeBSD-runtime carries
files with the schg flag, and `pkg` refuses them at any securelevel above
-1. So the base is installed in the builder, a FreeBSD guest at securelevel
-1 that gets the image's disk as its second disk and mounts it under the
same path. The builder itself comes from the official VM image (base kind
`image`: fetched, verified against the sha256, written and grown), which
the host can do:

    vm-bake template add freebsd-builder freebsd
    vm-bake template base image freebsd-builder amd64 15.1-RELEASE https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/FreeBSD-15.1-RELEASE-amd64-ufs.raw.xz a8e2c0f8331be615ef008c167069076833a417e968ff6b7d8e83b4ac762e9409
    vm-bake template resource freebsd-builder 2 4G 16G
    vm-bake template package add freebsd-builder doas
    vm-bake template rc add freebsd-builder sshd_enable YES
    vm-bake template user add freebsd-builder bake 1010
    vm-bake image make freebsd freebsd-builder v1
    vm-bake guest make img:freebsd-builder:v1 bake 172.16.100.250/24
    vm-bake image builder use

`image builder use` sets `VM_BAKE_BAKE_IN=builder` and pins the content
terminals to `ssh ... doas sh` into the builder, one `setintp` line each,
so the pins are seen; `image builder leave` takes them back. The emissions
are the same on both sides -- the interpreter decides where they run.
`VM_BAKE_BUILDER`, `VM_BAKE_BUILDER_ADDRESS` and `VM_BAKE_BUILDER_USER`
name the guest, its address and the user the ssh logs in as.

## The bake

An image is `img:<name>:<version>`: the name is the template's, the
version yours. `image make freebsd` is the chain over five steps that are
commands of their own:

    vm-bake image make freebsd freebsd-dev v1
    vm-bake image list

    vm-bake image create freebsd-dev img:freebsd-dev:v1   # lock, record, dataset, disk, GPT, newfs, mount
    vm-bake image base   img:freebsd-dev:v1               # keys, pkg -r set-minimal + kernel + pkg, repos, loader, fstab
    vm-bake image burn   img:freebsd-dev:v1               # packages, rc.conf, env, users with the host key, doas, sshd
    vm-bake image close  img:freebsd-dev:v1               # reports, umount, md detach, sha256
    vm-bake image seal   img:freebsd-dev:v1               # snapshot @image, readonly, lock dropped

To read the plan before the bake runs, pin the chain to `cat` for the
moment (`vm-bake setintp image_make_freebsd_from cat`, then `unsetintp`);
the same for any step or act. The acts that need root (zfs, md, gpart,
newfs, mount) are pinned to `sudo sh`; sudo asks once within its timeout.
One bake at a time: `image create` takes a lock, `image seal` drops it; a
bake that died with the lock held is released with `vm-bake image lock
drop`, the half-baked image with `vm-bake image drop img:freebsd-dev:v1`.
Every step leaves its trace under `~/.vm-bake/db/.log/<date>/`.

## The guest

A guest is a clone of the image's snapshot with a rendered vm-bhyve
configuration. The host writes hostname, address and resolver into the
clone before the first start, because no one is root inside:

    vm-bake guest make img:freebsd-dev:v1 dalmatia 172.16.100.101/24
    vm-bake guest start dalmatia
    vm-bake guest list
    ssh -p 2222 brj@dalmatia.local

`guest make` also makes the guest's ssh host key when none of that name is
kept (`hostkey list`), so the guest answers with the same identity after
every rebuild. `guest stop` shuts it down over ACPI; `guest drop` destroys
the clone and keeps the key.

## A daemon of the guest

A `daemon` line names a program the guest's init starts at boot and keeps
running, under a user of the template (or root), as a service of the
given name. The same line works on every way: the FreeBSD bake writes an
rc.d script under daemon(8) (restart after five seconds, output to
`/var/log/<name>.log`) and enables it in rc.conf; OpenBSD gets an rc.d
script with `rc_bg`, Alpine an OpenRC script, Debian a systemd unit. The
program is one quoted word, plain -- no shell syntax; a bare program name
is looked up in the system's path, /usr/local included:

    vm-bake template package add proton-bridge protonmail-bridge
    vm-bake template package add proton-bridge socat
    vm-bake template daemon add proton-bridge bridge brj 'protonmail-bridge --noninteractive --log-level info'
    vm-bake template daemon add proton-bridge relay_imap root 'socat TCP4-LISTEN:1143,fork,reuseaddr,keepalive,nodelay,max-children=25 TCP4:127.0.0.1:1144'
    vm-bake template daemon show proton-bridge

The name is an identifier (letters, digits, underscore); the user must be
root or in the template's user list, which the bake checks first (`image
check daemons`). A daemon never runs in the bake, only in a guest.

## Rebuilding

A new decision is a new version. The guest moves to the new image, the
old image goes when no guest is made from it:

    vm-bake template package add freebsd-dev tmux
    vm-bake image make freebsd freebsd-dev v2
    vm-bake guest stop dalmatia
    vm-bake guest drop dalmatia
    vm-bake guest make img:freebsd-dev:v2 dalmatia 172.16.100.101/24
    vm-bake guest start dalmatia
    vm-bake image prune

`image prune` drops every sealed image no guest names and leaves an open
one (a bake under way) with a note. What a guest has to keep across the
rebuild does not live on its disk: see `TUTORIAL_VIEW.md`.
