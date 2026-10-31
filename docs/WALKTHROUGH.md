# Walkthrough: the FreeBSD development guest

The first vertical cut through vm-bake: a chain of templates from the root
to `freebsd-dev`, the template that will bake the guest with VS Code and
Claude Code. Everything below is bookkeeping in the database; nothing
touches vm-bhyve or zfs yet. `image make` is the next chapter.

## The database

vm-bake keeps its records in `~/.vm-bake/<name>`, `~/.vm-bake/db` pointing
at the active one. The engine's bootstrap creates it; the root template
`empty` exists from that moment on without a record of its own.

    vm-bake bootstrap production minimal
    vm-bake template list

## The chain

A template inherits from its parent: scalars (base, bake, firmware,
resource) from the nearest ancestor that sets them, lists (package, rc,
user, service, forbid, data, session) as the union of the chain minus the
masks. The words of an enum stand before the template (`bake chroot
<template>`, `firmware uefi <template>`, `base release <template> ...`),
the way the engine dispatches: a word it does not know falls to the error
line.

    vm-bake template add freebsd
    vm-bake template firmware uefi freebsd
    vm-bake template bake chroot freebsd
    vm-bake template add freebsd-15.1 freebsd
    vm-bake template base release freebsd-15.1 amd64 15.1-RELEASE
    vm-bake template add freebsd-16.0 freebsd
    vm-bake template base release freebsd-16.0 amd64 16.0-RELEASE
    vm-bake template add freebsd-stage freebsd
    vm-bake template base stage freebsd-stage amd64 daily-v1
    vm-bake template add freebsd-dev freebsd-15.1
    vm-bake template resource freebsd-dev 8 32G 64G
    printf 'vscode\nclaude-code\n' | vm-bake template package add freebsd-dev -
    vm-bake template rc add freebsd-dev linux_enable YES
    vm-bake template rc add freebsd-dev sshd_enable YES
    vm-bake template user add freebsd-dev brj host
    vm-bake template service add freebsd-dev display x
    vm-bake template service add freebsd-dev audio pulse
    vm-bake template service add freebsd-dev clipboard broker
    vm-bake template service add freebsd-dev net dev
    vm-bake template data add freebsd-dev home 64G proton
    vm-bake template forbid add freebsd-dev net 192.168.1.0/24
    vm-bake template forbid add freebsd-dev usb
    vm-bake template session add freebsd-dev ssh
    vm-bake template session add freebsd-dev x
    vm-bake template show freebsd-dev

`16.0-RELEASE` is allowed today: add stores, the bake checks whether the
repository exists.

## Changing a decision

Records are immutable: a differing scalar is refused, drop it first.

    vm-bake template base drop freebsd-16.0
    vm-bake template base release freebsd-16.0 amd64 16.0-RC1

An inherited list entry is not dropped in the child, it is masked there:

    vm-bake template package add freebsd emacs
    vm-bake template package show freebsd-dev
    vm-bake template package mask freebsd-dev emacs
    vm-bake template package show freebsd-dev

## Dump and restore

The dump is the replay: the commands above, parents before children. A
replay is idempotent, an existing template is never re-minted.

    vm-bake template dump all > templates.vmb
    vm-bake template restore templates.vmb

## Inspect first

The engine shows shell before it runs it. The bookkeeping terminals of the
templates are pinned to `sh` so that add, drop and mask act directly; the
display terminals to `cat`. Any single act can be read instead of run:

    vm-bake setintp template_mint cat
    vm-bake template add probe
    vm-bake unsetenv VM_BAKE_INTERPRETER_template_mint

`vm-bake help template` lists the family, `vm-bake help template base
release` one command.

## The image

An image is the template baked onto a sparse UFS disk under
`VM_BAKE_IMAGE_DIR/<image>` (a ZFS dataset of its own), from the pkgbase
repository of the template's release, sealed by the snapshot `@image`.
The bake is five commands; `image make freebsd` is the chain over them
and names the image `<template>-<yyyymmdd>`:

    vm-bake image create freebsd-dev freebsd-dev-20261031   # lock, record, dataset, disk, GPT, newfs, mount
    vm-bake image base   freebsd-dev-20261031               # keys, pkg -r set-minimal + kernel + pkg, repos, loader, fstab
    vm-bake image burn   freebsd-dev-20261031               # packages, rc.conf, users with the host key, sshd
    vm-bake image close  freebsd-dev-20261031               # reports, umount, md detach, sha256
    vm-bake image seal   freebsd-dev-20261031               # snapshot @image, readonly, lock dropped
    vm-bake image list

The acts that need root (zfs, md, gpart, newfs, mount, pkg -r, pw) are
pinned to `sudo sh`; sudo asks once per terminal within its timeout. Three
variables shape the bake: `VM_BAKE_IMAGE_DIR` (default `/data/vm/.images`),
`VM_BAKE_SSH_PORT` (default 2222, the port the host's pf passes into the
guest network) and `VM_BAKE_HOST_KEY` (the public key every user of the
image gets; the guests know no password). Each step shows its plan under
`vm-bake setintp batch cat`, each act its shell under
`vm-bake setintp image_pkg_base cat` and the like; a bake that died with
the lock held is released with `vm-bake image lock drop`.

After an update of the checkout, `vm-bake bootstrap <name> minimal` again:
the re-run refreshes `.env/default` with the variables of the new version
(the pins of `image` among them) and leaves `.env/local` alone. `init` and
`environment init` are its inner lines, not commands to type.
