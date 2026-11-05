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

An inherited list entry is not dropped in the child, it is masked there --
and `unmask` takes that back, so a mask is as reversible as everything else:

    vm-bake template package add freebsd emacs
    vm-bake template package show freebsd-dev
    vm-bake template package mask freebsd-dev emacs
    vm-bake template package show freebsd-dev
    vm-bake template package unmask freebsd-dev emacs
    vm-bake template package show freebsd-dev

Every list family has the same five verbs: `add`, `drop`, `mask`, `unmask`,
`show`. `drop` works on the template's own list, `mask` and `unmask` on
what the chain hands down; `template dump record <template>` shows both
lists as replay lines, which is also where you see the masks.

## Dump and restore

The dump is the replay: the commands above, parents before children. A
replay is idempotent, an existing template is never re-minted.

    vm-bake template dump all > templates.vmb
    vm-bake template restore templates.vmb

The whole database is `dump`: a header (generator, format, date, profile,
base), the environment the replay needs, every template, then the image
and guest records as witnesses -- what was baked from which template, with
which digest, which guest ran it at which address with which tags. A
replay of those lines places the records only; the images and clones stay
where they were made. On a host that has none, the records say what to
bake: `image drop` lets a witness go, `image make <template> <image>` bakes
it anew, `guest make` clones it.

    vm-bake dump > vm-bake.dump
    vm-bake restore vm-bake.dump

## Export and import

What the dump cannot carry travels in the bundle: the guest host keys (the
guests keep their identity, known_hosts stays right), the package files of
every `pkgfile` list, the home seeds of every `home` list. `export` writes
the pair -- the dump to a path you commit, the bundle to a store of your
own -- and seals the dump with the bundle's sha256. Nothing is signed or
encrypted by vm-bake: the signed commit that carries the dump is the
signature, and the bundle holds private keys, so it stays private.

    vm-bake export ~/git/vm-bake-dump/illyria/production/dump.sh \
        ~/Infrastruktur/vm-bake-export/illyria/production/20261103.tar.gz

The bundle is built in the database under `export/`: `collection` lists
the files, `tree/` is their copy with the `MANIFEST` (sha256 per file,
symlinks by target), readable before it is packed. `import` checks the
pair end to end before a byte lands: the seal, the MANIFEST against the
unpacked tree under `~/.vm-bake/incoming/`, then every file against its
place here -- absent or identical passes, a file that differs is refused
by name and nothing is placed. Then the missing files land (keys in the
database, packages in VM_BAKE_PKG_DIR, seeds in your home) and the dump
replays. Bootstrap the database first; the dump's `# Profile:` header
names the profile.

    vm-bake bootstrap production minimal
    vm-bake import ~/git/vm-bake-dump/illyria/production/dump.sh \
        ~/Infrastruktur/vm-bake-export/illyria/production/20261103.tar.gz

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
variables shape the bake: `VM_BAKE_IMAGE_DIR` (default `/data/vm/vm-bake/image`; vm-bake's datasets live under `VM_BAKE_DIR`, vm-bhyve's vm_dir is `VM_BAKE_VM_DIR`, where every vm-bake guest appears as a link),
`VM_BAKE_SSH_PORT` (default 2222, the port the host's pf passes into the
guest network) and `VM_BAKE_HOST_KEY` (the public key every user of the
image gets; the guests know no password). Each step shows its plan under
`vm-bake setintp image_create cat` (the pin of that batch, never the class
batch: pinned to cat it silences setenv and unsetenv too), each act its shell
under `vm-bake setintp image_pkg_base cat`; `unsetintp` takes a pin back. A
bake that died with
the lock held is released with `vm-bake image lock drop`.

After an update of the checkout, `vm-bake bootstrap <name> minimal` again:
the re-run refreshes `.env/default` with the variables of the new version
(the pins of `image` among them) and leaves `.env/local` alone. `init` and
`environment init` are its inner lines, not commands to type.

## The builder

A host at securelevel 1 cannot install pkgbase with `pkg -r`: FreeBSD-runtime
carries files with the schg flag, and pkg refuses them at any securelevel
above -1, wherever the root is. So a release base is baked in the builder,
a FreeBSD guest at securelevel -1 that gets the image's disk as its second
disk and mounts it under the same path. The builder itself comes from the
official FreeBSD VM image (base kind `image`: fetched, verified against the
template's sha256, written, grown, relabelled), baked on the host:

    vm-bake template add freebsd-builder freebsd
    vm-bake template base image freebsd-builder amd64 15.1-RELEASE https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/FreeBSD-15.1-RELEASE-amd64-ufs.raw.xz a8e2c0f8331be615ef008c167069076833a417e968ff6b7d8e83b4ac762e9409
    vm-bake template resource freebsd-builder 2 4G 16G
    vm-bake template package add freebsd-builder doas
    vm-bake template rc add freebsd-builder sshd_enable YES
    vm-bake template user add freebsd-builder bake 1010
    vm-bake image make freebsd freebsd-builder
    vm-bake guest make freebsd-builder-20261101 bake 172.16.100.250/24
    vm-bake image builder use
    vm-bake image make freebsd freebsd-dev

A template that lists `doas` gives its users doas without a password; that
is how the builder's user escalates. `image builder use` sets
`VM_BAKE_BAKE_IN=builder` and pins the twelve content terminals to
`ssh ... doas sh`, one setintp line each; `image builder leave` takes them
back. The emissions are the same on both sides: the interpreter decides
where they run.

## The session

A session is a client script, printed by `session create`, kept wherever you
like. `ssh` opens a terminal in the guest, `x` opens a Xephyr compartment on
the host's display and runs one program of the guest inside it over
`ssh -X`, so the program's windows never touch the host's own X server:

    vm-bake template add freebsd-x freebsd-dev
    vm-bake template service add freebsd-x display x
    vm-bake template package add freebsd-x xauth
    vm-bake template package add freebsd-x intellij
    vm-bake image make freebsd freebsd-x
    vm-bake guest make freebsd-x-20261102 xenia 172.16.100.102/24
    vm-bake session create ssh xenia > ~/bin/xenia && chmod +x ~/bin/xenia
    vm-bake session create x xenia idea > ~/bin/xenia-idea && chmod +x ~/bin/xenia-idea

The service `display x` gives the image `X11Forwarding yes` in sshd at bake
time; the template lists `xauth` itself. The host needs the package
`xephyr`. The compartment takes `VM_BAKE_XEPHYR_SCREEN` and
`VM_BAKE_XEPHYR_DPI`; its display number is the first free one from
`VM_BAKE_XEPHYR_FIRST`, read when the script is made. A separate X server
per compartment is the isolation: the guest's program sees only its
Xephyr, and the clipboard between host and compartment is the broker
service still to come.

## Package files and ports

Two more lists of a template, both installed after its packages:

- `template pkgfile add <template> <file>`: a .pkg file you keep under
  `VM_BAKE_PKG_DIR` (default `/data/vm/vm-bake/distfiles/pkg`), of the host's ABI, for
  example the package another host fetched from the signed repository while
  the cluster has not rebuilt it yet. The bake checks it is there, stages
  it into the image (copied on the host, streamed over ssh into the
  builder) and installs it with `pkg add`; the dependencies come from the
  repositories.
- `template port add <template> <origin>`: a port built from source in the
  builder guest (`image port build`: the ports tree on
  `VM_BAKE_PORTS_BRANCH`, the missing dependencies from the repositories,
  `make package`), then installed into the image (`image port install`).
  Built packages stay in the builder under `/usr/ports/packages`. Ports
  build only in the builder; a bake on the host refuses them.

    scp /var/cache/pkg/vscode-1.130.0~*.pkg illyria:/data/vm/vm-bake/distfiles/pkg/vscode-1.130.0.pkg
    vm-bake template pkgfile add freebsd-x vscode-1.130.0.pkg
    vm-bake template port add freebsd-x editors/neovim

## Tags

Tags tell templates, images and guests apart and answer questions like
"which guest can run IntelliJ": a key and a text, the keys are yours.
`template tag` is a list family like the others, inherited down the chain
and masked where a child disagrees; `guest tag` holds what belongs to one
guest (owner, note). `template find` and `guest find` search by key and
pattern over the resolved tags, from the records, without starting anything:

    vm-bake template tag add freebsd-dev purpose 'development on FreeBSD with Claude Code'
    vm-bake template tag add freebsd-x can intellij
    vm-bake guest tag add caledonia owner JB
    vm-bake guest tag show caledonia
    vm-bake guest find can intellij

## Homes and host keys

What a guest sees of your home is a list of the template:
`template home add <template> <path> [<mode>]` names a path of your own
home (relative: `.themes/NsCDE`, `.config/gtk-3.0`) and how the guest sees
it, `ro` unless you say `rw`. A guest without a view gets each path copied
into the home of every user of the template at `guest make`, offline
through the clone's disk, owned by that user; a rebuilt guest gets the
files again. The guest's ssh host key is part of its record
(`guest/<guest>/ssh_host_ed25519_key`, made once) and installed into every
clone, so the host's known_hosts stays right across rebuilds.

    vm-bake template home add freebsd-x .themes/NsCDE
    vm-bake template home add freebsd-x .config/gtk-3.0 rw
    vm-bake template home show freebsd-x

## The view: one home

There is one home, yours on the host. `guest view tree ensure` makes the
datasets that carry the views, once per host: beside the dataset that
carries your home, under its parent, with the path of `VM_BAKE_VIEW_DIR`
below the home as the dataset path, slash for slash -- `~/vm-bake/guest`
becomes `<parent>/vm-bake/guest`, the head carries the mount point and
everything below inherits it. A view is a dataset of its own, so it is not
in the snapshots of the home's dataset: a backup takes the parent
recursively. A template that says `service files view` then gives its
guests a view:
`guest make` makes the ZFS dataset `VM_BAKE_VIEW_DIR/<guest>` below that
one, which inherits the mount point, and writes the share into the guest's
configuration as `bhyve_options`; the image learns at `image burn` to load
`virtio_p9fs` and to mount the share `home` on the home of the user whose
uid is `host`. What the guest writes -- its dotfiles, the state of its
tools, its clones -- lies in the view, in your home, and is backed up with
it. A new image replaces the guest, not its view: `guest drop` keeps the
view, `guest view drop` is the command that throws it away.

Of the rest of your home the guest sees what the template's home lines
allow: `guest start` hangs each one into the view as a nullfs overlay, `ro`
or `rw` as the line says, `guest stop` lets them go once the guest's bhyve
process is gone. The login does not hang on the mount: sshd reads the keys
from `/etc/ssh/authorized_keys/%u` as well, where `image user make` puts
them.

    vm-bake guest view tree ensure          # once per host, needs root
    vm-bake template service add freebsd-dev files view
    vm-bake template user add freebsd-dev brj host
    vm-bake template home add freebsd-dev .vm-bake/db
    vm-bake guest make freebsd-dev-20261104 dalmatia 172.16.100.101/24
    vm-bake guest start dalmatia
    vm-bake guest view drop dalmatia        # the view and everything in it

## Repositories of a guest

A repository of the host is never hung into a view: git runs what
`.git/config` and the hooks say, so a guest that fell would own the host.
The guest gets its own clone instead, at the same path it has on the host,
and commits unsigned; you fetch it back into your own repository, read it
and sign there. `guest repo fetch` runs git only in YOUR repository and
fetches the guest's branches into `refs/remotes/<guest>/*`:

    vm-bake guest repo add dalmatia git/Infrastruktur
    vm-bake guest repo show dalmatia
    vm-bake guest repo fetch dalmatia git/Infrastruktur
    git -C ~/git/Infrastruktur log dalmatia/main
    git -C ~/git/Infrastruktur merge --ff-only dalmatia/main
