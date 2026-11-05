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
in its own clones of the host's repositories, which the host fetches back.
A *session* is a rendered client script that brings one application of the
guest onto the host desktop.

vm-bake bakes and renders; starting and stopping guests stays with
[vm-bhyve](https://github.com/churchers/vm-bhyve). Every command generates
shell, an interpreter the user pins decides whether it is shown or run,
the database carries its records with dump and restore. The combinator
engine is vm-bake's own, forked from [elvboot](https://github.com/enk-ode/elvboot)
and renamed, as elvboot's was forked from vpn-switch.

Status: templates (add, drop, show, the scalars base/bake/firmware/
resource, the lists package/pkgfile/port/rc/env/user/home/service/forbid/
data/session/tag with add/drop/mask/show), images (`image make freebsd`,
on the host or in a builder guest), guests (`guest make`, tags, host keys,
home seeds, the view with its overlays and the guest's own repository
clones), sessions (ssh, and X in a Xephyr compartment) and the pair
that travels (`dump`/`restore` with the records as witnesses, `export`/
`import` with the bundle of host keys, package files and home seeds, sealed
to the dump). `docs/WALKTHROUGH.md` walks the first chain, the FreeBSD
development guest.

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
