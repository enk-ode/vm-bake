# Tutorial: the first hour with vm-bake

One topic: getting vm-bake onto a FreeBSD host, opening its database, and
learning to read what it says before anything runs. Every other tutorial
starts where this one ends.

## What the host needs

A FreeBSD host with ZFS, [vm-bhyve](https://github.com/churchers/vm-bhyve)
configured (a `vm_dir`, a switch on a bridge), `sudo` for the invoking
user, and the base system's `makefs`, `bsdtar`, `mdconfig`, `gpart`,
`newfs`. The guests live in a network of their own behind the host's pf;
the host passes `VM_BAKE_SSH_PORT` (2222) into it. Optional: `xephyr` for
X sessions, `tmux` when vm-bhyve's `console=tmux` is in use, `pandoc` and
`mandoc` for `make manpage`.

## Install

    git clone https://github.com/enk-ode/vm-bake.git ~/git/vm-bake
    cd ~/git/vm-bake
    make check
    make PREFIX=$HOME install
    vm-bake version

`make install` puts a wrapper into `$PREFIX/bin` that execs this checkout,
so `git pull` updates the tool. `make check` runs the architecture rules;
`make test` runs them and the unit suite.

## The database

vm-bake keeps every record under `~/.vm-bake/<name>`, with `~/.vm-bake/db`
pointing at the active one. `bootstrap` creates it with a profile of
variables and pins; `minimal` is the profile for a host:

    vm-bake bootstrap production minimal
    vm-bake template list
    vm-bake printenv | head

After every update of the checkout, run `bootstrap` again with the same
name: it refreshes the defaults under `.env/default` with the variables of
the new version and leaves your own settings under `.env/local` alone.
Without it a command that reads a new variable stops with `parameter not
set`.

    vm-bake environment cache on

The cache keeps the resolved environment between calls; `environment
refresh` rebuilds it after a `setenv`.

## Reading before running

Every vm-bake command GENERATES shell. An interpreter decides what happens
to that text: `cat` shows it, `sh` runs it, `sudo sh` runs it as root.
Every anchor has its pin in the profile: the bookkeeping -- `template
add`, `setenv`, `dowry add` -- and the acts of the bakes and the guests to
`sh` (or `sudo sh`), the display terminals to `cat`. So a command acts
when typed:

    vm-bake template add freebsd
    vm-bake template bake chroot freebsd
    vm-bake template add freebsd-15.1 freebsd
    vm-bake template base release freebsd-15.1 amd64 15.1-RELEASE
    vm-bake template show freebsd-15.1

To see what a command would do before it does it, pin it to `cat` for the
moment. A batch pinned to `cat` prints its lines and runs none of them; an
act pinned to `cat` prints its shell:

    vm-bake setintp image_make_freebsd_from cat
    vm-bake image make freebsd freebsd-15.1 v1
    vm-bake unsetintp image_make_freebsd_from
    vm-bake setintp image_disk_create cat
    vm-bake image disk create img:freebsd-15.1:v1 20G
    vm-bake unsetintp image_disk_create

The first `image make` prints eight lines of `"$VM_BAKE_CONTEXT_SCRIPT"
image ...`, the steps of the bake; nothing happened. A pin is a variable
`VM_BAKE_INTERPRETER_<function>` in `.env/local`; `setintp` writes it,
`getintp` reads it, `unsetintp` takes it back and the profile's pin
applies again. `vm-bake help intp image_disk_create` says what that pin is
and why. The function name is the command's words joined by underscores,
without the arity: `image make freebsd from` is `image_make_freebsd_from`.

## Help

    vm-bake help
    vm-bake help template
    vm-bake help image make freebsd
    vm-bake help environment
    vm-bake help env VM_BAKE_IMAGE_DIR

`help` with a group lists the group, with a command shows its summary,
with a variable its template. `help environment` is the concept text on
pins, the three layers of the environment and the logs. The manual
(`vm-bake.8`) is the same corpus rendered by `make manpage`, published at
<https://enk-ode.github.io/vm-bake/>.

## Traces

Every call writes what it generated and what the interpreter answered
under `~/.vm-bake/db/.log/<date>/`, one file per anchor:

    ls ~/.vm-bake/db/.log/$(date +%Y%m%d)/ | tail
    less ~/.vm-bake/db/.log/$(date +%Y%m%d)/*image_make_freebsd*.trace

A bake that went wrong is read there first: the trace shows the resolved
interpreter, the exact text handed to it, and its output. Nothing is
re-run to find out what happened.

## Where to go next

- `TUTORIAL_FREEBSD.md` -- the chroot way: pkgbase, the builder guest, the
  first image and the first guest.
- `TUTORIAL_LINUX.md` -- the cloud-init way: a Debian cloud image, apt
  sources with their keys, files from dowries.
- `TUTORIAL_OPENBSD.md` -- the autoinstall way: the install ISO, the
  response file and the site set, the console driver.
- `TUTORIAL_ALPINE.md` -- the apkovl way: the live ISO and an overlay on a
  second CD.
- `TUTORIAL_VIEW.md` -- one home: the view, home lines, the dowry, the
  guest's repositories.
- `WALKTHROUGH.md` -- the whole chain for a FreeBSD development guest,
  from the template to the session, with dump, export and the rebuild.
