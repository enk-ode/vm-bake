# vm-bake — bake images and guest configurations for vm-bhyve

**vm-bake turns a declared template into an image, a guest and the
host-side plumbing around it, reproducibly.**

A *template* is the build recipe: operating system base, packages,
configuration, users, the host services a guest may use (display, audio,
clipboard, files, network), resources, lifetime. An *image* is what
baking a template yields: an immutable ZFS snapshot with a digest and a
date, rebuilt whenever template or base change. A *guest* is a clone of
an image plus a rendered `vm.conf` plus the shares wired up on the host;
its data lives in datasets outside the image, so a new image replaces
the guest, never the data. A *session* is a rendered client script that
brings one application of the guest onto the host desktop.

vm-bake bakes and renders; starting and stopping guests stays with
[vm-bhyve](https://github.com/churchers/vm-bhyve). Templates live in a
database with dump and restore, built on the elebake engine of
[elvboot](https://github.com/enk-ode/elvboot).

Status: design stage, nothing to run yet.

License: BSD-2-Clause.
