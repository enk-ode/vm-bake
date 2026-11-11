# Tutorial: the autoinstall way -- an OpenBSD image from the install ISO

One topic: baking an OpenBSD image with autoinstall(8). OpenBSD has no
cloud image and the host cannot write its filesystem, so the installer
does the work: a throwaway guest boots the install ISO, vm-bake types the
first answers at its serial console, the installer takes a response file
and a site set from a second CD, installs, reboots; the installed system
adds the packages at its first boot and powers off; the host seals the
disk.

Prerequisites: `TUTORIAL_QUICKSTART.md`; `VM_BAKE_CONSOLE` set to
vm-bhyve's console kind (`nmdm` or `tmux`); the install ISO on the host.

## The chain

The base is an install ISO by path and sha256; its file name tells the
release (`install78.iso` is 7.8) and with it the set directory on both
CDs. The bake is `autoinstall`:

    vm-bake template add openbsd
    vm-bake template bake autoinstall openbsd
    vm-bake template add openbsd-7.8 openbsd
    vm-bake template base iso openbsd-7.8 amd64 /data/iso/install78.iso <sha256>
    vm-bake template add openbsd-dev openbsd-7.8
    vm-bake template resource openbsd-dev 4 4G 40G
    vm-bake template package add openbsd-dev git
    vm-bake template package add openbsd-dev gmake
    vm-bake template package add openbsd-dev openvpn--
    vm-bake template package add openbsd-dev doas
    vm-bake template env add openbsd-dev EDITOR vi
    vm-bake template user add openbsd-dev brj host
    vm-bake template show openbsd-dev

`doas` is base on OpenBSD: the word in the package list gives the users
their doas rule, no package is added. A package with several flavors needs
its flavor spelled out (`openvpn--` is the flavorless one): `pkg_add -I`
skips an ambiguous name without a word, and the first boot's check would
report it missing.

## What the template becomes

`image install` renders two things from the template, both readable
under `cat` before a bake:

    vm-bake image record write openbsd-dev img:openbsd-dev:v1
    vm-bake setintp image_response_write cat
    vm-bake image response write img:openbsd-dev:v1
    vm-bake unsetintp image_response_write

The response file `install.conf` answers the installer: hostname and
static address of the bake, root with a throwaway password (locked again
by the site set), sshd on, no user, com0, the sets from the install CD
and the site set from the site CD, both taken without SHA256.sig. The
site set `site<NN>.tgz` carries `install.site`, which the installer runs
chrooted in the installed system -- written aspect by aspect by `image
site write`: sshd on `VM_BAKE_SSH_PORT` without root and without passwords,
the users with the host key and their doas rule, the env lines, installurl,
root locked, the seed hook as `hostname.vio0`, and `rc.firsttime` with the
packages, their check and the report line. The template's `file` lines
travel in the same set (`image site files place`). The set holds files
only, no directory entry: a bake once packed `.` of a 0700 directory and
came out with `/` unreadable.

    vm-bake setintp image_site_user_write cat
    vm-bake image site user write img:openbsd-dev:v1
    vm-bake unsetintp image_site_user_write
    vm-bake image drop img:openbsd-dev:v1

## The bake

    vm-bake image make openbsd openbsd-dev v1

`image create iso` makes the record and an empty disk of the resource's
size; `image install` renders response file and site set, packs them as
`site.iso`, hangs the disk and the site.iso on the throwaway guest
`VM_BAKE_FIRSTBOOT`, starts it from the install ISO with `vm install` and
drives the console: `set tty com0`, `boot`, the installer's shell for a
moment (the response file gets the CD device names filled in, which the
installer numbers), then `(A)utoinstall`. `CONGRATULATIONS` and the
reboot end the installation; the guest is powered off and started again
from its disk, and the driver waits for `# vm-bake firstboot: packages
complete` -- `missing <packages>` ends the bake naming them. `image close
iso` takes the digest, `image seal` the snapshot.

Every wait has its seconds; a wait that runs out prints the last screen,
powers the guest off and ends the bake. The console driver's trace under
`~/.vm-bake/db/.log/<date>/` holds the dialogue.

## One sudo for the whole bake

The console belongs to root (vm-bhyve runs bhyve and tmux as root), so
`guest link write`, `guest install`, `image console drive` and `guest link
drop` are pinned to `sudo sh`. sudo stamps its ticket when a command
starts; a console drive of ten minutes outlives it, and the next root act
asks again. One sudo over the whole batch instead:

    vm-bake setintp image_install 'sudo -E sh -c "$VM_BAKE_BATCH_COMBINATOR_INTERPRETER"'
    vm-bake setintp image_response_write 'sudo -u brj sh'
    vm-bake setintp image_site_head_write 'sudo -u brj sh'
    vm-bake setintp image_site_user_write 'sudo -u brj sh'
    vm-bake setintp image_site_env_write 'sudo -u brj sh'
    vm-bake setintp image_site_net_write 'sudo -u brj sh'
    vm-bake setintp image_site_firsttime_write 'sudo -u brj sh'
    vm-bake setintp image_site_files_place 'sudo -u brj sh'
    vm-bake setintp image_site_pack 'sudo -u brj sh'
    vm-bake setintp image_firstboot_conf_write 'sudo -u brj sh'
    vm-bake setintp image_firstboot_conf_drop 'sudo -u brj sh'

The batch then runs as root, and the acts that write the image's files
drop back to the invoking user, which root may do without a password.
`vm-bake help image install` has the reasoning (why `sh -c`, why `-E`).

## The guest

An OpenBSD guest is never mounted on the host: `guest make` writes a seed
CD -- the marker `vm-bake-seed`, address, netmask, myname, mygate,
resolv.conf and the guest's ssh host key -- and hangs it on as the guest's
CD. The hook `/usr/local/libexec/vm-bake-seed`, the one line of
`/etc/hostname.vio0`, reads it at every boot before sshd starts:

    vm-bake guest make img:openbsd-dev:v1 achaja 172.16.100.103/24
    vm-bake guest start achaja
    ssh -p 2222 brj@achaja.local
    ssh -p 2222 brj@achaja.local cat /etc/vm-bake/packages
