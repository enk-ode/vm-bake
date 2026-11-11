# vm-bake — bake images and guest configurations for vm-bhyve

**vm-bake turns a declared template into an image, a guest and the
host-side plumbing around it, reproducibly.**

A *template* is the build recipe: operating system base, packages,
configuration, users, the host services a guest may use (display, audio,
clipboard, files, network), resources, lifetime. Templates inherit from a
parent down to the root `empty`. An *image* is what baking a template
yields: an immutable ZFS snapshot with a digest and a date, rebuilt
whenever template or base change. A *guest* is a clone of an image plus a
rendered `vm.conf` plus the shares wired up on the host; its data lives in
datasets outside the image, so a new image replaces the guest, never the
data. There is one home, the host's: a guest whose template says `service
files view` mounts its *view* of it over virtio-9p, sees of the rest what
the template's home lines allow (nullfs overlays, `ro` or `rw`), and works
in its own clones of the host's repositories -- on its own disk, from
mirrors in the view -- which the host fetches back over ssh.
A *session* is a rendered client script that brings one application of the
guest onto the host desktop.

vm-bake bakes and renders; starting and stopping guests stays with
[vm-bhyve](https://github.com/churchers/vm-bhyve). Every command generates
shell, an interpreter the user pins decides whether it is shown or run,
the database carries its records with dump and restore. The combinator
engine is vm-bake's own, forked from [elvboot](https://github.com/enk-ode/elvboot)
and renamed, as elvboot's was forked from vpn-switch.

Four ways bake an image, one per family of operating systems: `image make
freebsd` (the chroot way: pkgbase into the mounted disk, on the host or in
a builder guest), `image make linux` (the cloud-init way: a cloud image
and a seed CD, one first boot), `image make openbsd` (the autoinstall way:
the install ISO, a response file and a site set on a second CD, the
console driven) and `image make alpine` (the apkovl way: the live ISO and
an overlay on a second CD, unattended). Every bake ends with the first
boot reporting its packages; a missing one ends the bake.

Status: templates (add, drop, show, the scalars base/bake/firmware/
resource/topology, the lists package/pkgfile/port/rc/env/user/home/service/
forbid/data/session/tag/source/file with add/drop/mask/unmask/show), the
four image ways, ssh host keys as a resource (`hostkey create`, bound to
one guest each), guests (`guest make`, tags, home seeds, the view with its
overlays, the dowry a template hands to the homes of its guests, the
guest's own repository clones on its disk with the mirrors in the view and
the report of its records written into the view at every start), sessions
(ssh, xterm, and X in a Xephyr compartment) and the pair that travels
(`dump`/`restore` with the records as witnesses, `export`/`import` with
the bundle of ssh host keys, package files, dowries and home seeds, sealed
to the dump).

Documentation: `docs/TUTORIAL_QUICKSTART.md` (install, the database, pins
and traces), one tutorial per way (`docs/TUTORIAL_FREEBSD.md`,
`docs/TUTORIAL_LINUX.md`, `docs/TUTORIAL_OPENBSD.md`,
`docs/TUTORIAL_ALPINE.md`), `docs/TUTORIAL_VIEW.md` (one home: the view,
the dowry, the guest's repositories) and `docs/WALKTHROUGH.md`, the whole
chain for a FreeBSD development guest. The manual `vm-bake(8)` is
generated from the help corpus (`make manpage`) and published at
<https://enk-ode.github.io/vm-bake/>.

    vm-bake bootstrap production minimal
    vm-bake template add freebsd
    vm-bake template bake chroot freebsd
    vm-bake template add freebsd-15.1 freebsd
    vm-bake template base release freebsd-15.1 amd64 15.1-RELEASE
    vm-bake template show freebsd-15.1
    vm-bake help template

Development: `make metadata` after adding anchors, `make check`, `make
test` (the architecture rules, then the unit suite), `make install` for a
wrapper that execs this checkout. `docs/CONTRIBUTING.md` has the rules.

License: BSD-2-Clause.
