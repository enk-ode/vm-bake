# Tutorial: one home -- the view, the dowry and the guest's repositories

One topic: how a guest keeps state across rebuilds without owning any.
There is one home, the host's. A guest whose template says `service files
view` mounts a *view* of it over virtio-9p as its whole home: a ZFS
dataset of its own under `VM_BAKE_VIEW_DIR/<guest>`, in the invoking
user's home on the host, which survives the guest. Of the rest of the
host's home the guest sees what the template's `home` lines allow, as
nullfs overlays hung into the view at every start. Its repositories are
clones on its own disk, made from mirrors in the view, and the host
fetches the commits back.

Prerequisites: a baked image and a guest from `TUTORIAL_FREEBSD.md`,
`TUTORIAL_LINUX.md` or `TUTORIAL_ALPINE.md` (OpenBSD has no 9p).

## The datasets of the views, once

The views live beside the dataset that carries the invoking user's home,
under its parent, as a dataset path that reads like `VM_BAKE_VIEW_DIR`
(`~/vm-bake/guest` by default). Root makes the head once; everything
below inherits its mount point and belongs to the user:

    vm-bake guest view tree ensure
    zfs list -o name,mountpoint | grep vm-bake

## The view

    vm-bake template service add freebsd-dev files view
    vm-bake template home add freebsd-dev git/views
    vm-bake template home add freebsd-dev .vm-bake/db
    vm-bake template home add freebsd-dev Documents/notes rw
    vm-bake template home show freebsd-dev

`service files view` puts the share `home` into the guest's vm-bhyve
configuration (the PCI slot `VM_BAKE_VIEW_SLOT`) and the mount into the
image: FreeBSD mounts it as `p9fs` on the host-uid user's home, Linux as
`9p` with `trans=virtio`. The template needs exactly one user with the uid
word `host` -- the view is that user's home, and 9p passes uids through,
so the guest's user and the host's are the same person. A `home` line
names a path of the host's home that the guest may see, `ro` unless the
line says `rw`; `guest start` hangs them in, `guest stop` lets them go.
`git/views` is where the mirrors of the guest's repositories lie; a guest
reads them, never writes.

The image has to carry the mount, so the view is a decision of the
template and a rebuild:

    vm-bake image make freebsd freebsd-dev v2
    vm-bake guest stop dalmatia
    vm-bake guest drop dalmatia
    vm-bake guest make img:freebsd-dev:v2 dalmatia 172.16.100.101/24
    vm-bake guest start dalmatia
    ssh -p 2222 brj@dalmatia.local 'mount | grep home; ls -la ~'

`guest make` creates the view when it is missing and keeps it otherwise;
`guest drop` keeps it too. `guest view drop <guest>` is the command that
throws it away, with the dotfiles, the state of the guest's tools and its
clones.

## What the guest knows about itself

`guest start` writes `.vm-bake/GUEST.txt` into the view: what the records
say this guest should be -- image, template chain, address, resources,
the fingerprint of its ssh host key, every list family with its origin.
With `template home add <t> .vm-bake/db` the guest also reads the
database's records themselves, read-only. A guest can hold its SOLL
against what it finds:

    ssh -p 2222 brj@dalmatia.local 'cat ~/.vm-bake/GUEST.txt | head -40'

## The dowry

A dowry is an object kept in the database under a name -- a file or a
directory. A template hands it to the homes of its guests at every start:
`idem` puts it only where it is missing (the guest keeps what it makes of
it), `overwrite` replaces it every time (the place is not for the guest's
own work):

    vm-bake dowry add gitconfig ~/.gitconfig
    vm-bake dowry add claude-im-gast ~/git/Infrastruktur/Playbooks/CLAUDE-im-gast.md
    vm-bake template home copy idem freebsd-dev gitconfig .gitconfig
    vm-bake template home copy overwrite freebsd-dev claude-im-gast .claude/CLAUDE.md
    vm-bake dowry list
    vm-bake guest start dalmatia

`dowry add` with the same name replaces the object, which is how a dowry
is refreshed; the guest gets it at its next start. A dowry that should
land outside the home, as a system file of the image, is a `file` line
instead (`template file add`, applied at the bake).

## The guest's repositories

git cannot write its objects on 9p, so a guest's clones lie on its own
disk, under `VM_BAKE_REPO_LOCAL` (`git/local`) in its home, bound there
from `/var/git`. Their origin is the host's bare mirror of the repository
under `VM_BAKE_REPO_VIEWS` (`git/views`), which the `home` line above hangs
read-only into the view:

    vm-bake guest repo add dalmatia git/Infrastruktur
    vm-bake guest repo add dalmatia git/vm-bake
    vm-bake guest repo show dalmatia

The guest commits unsigned; the host fetches its branches into
`refs/remotes/dalmatia/*` of its own repository and takes them over by
fast-forward, signing if it signs:

    vm-bake guest repo fetch dalmatia git/Infrastruktur
    git -C ~/git/Infrastruktur log --oneline main..dalmatia/main
    vm-bake guest repo pull dalmatia git/Infrastruktur

`guest repo pull` is fetch and fast-forward in one go. `guest stop` holds
every repository first (`guest repo hold`): the commits are fetched while
the guest still answers, and the mark is written that `guest drop`
trusts -- a guest with unfetched commits is not dropped (`guest drop
unfetched` gives them up). A guest on a fresh image gets its clones back
at `guest start` (`guest repo ensure`). To refresh a mirror after the host
committed, `guest repo add` again; the guest then pulls from it.
