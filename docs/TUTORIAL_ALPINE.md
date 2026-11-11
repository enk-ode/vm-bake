# Tutorial: the apkovl way -- an Alpine image from the live ISO

One topic: baking an Alpine Linux image unattended. Alpine's live ISO
boots into RAM and looks, before any service starts, on every block
device that carries a filesystem for a file `*.apkovl.tar.gz` in its root
directory -- an overlay it unpacks over itself. vm-bake renders that
overlay from the template and puts it on a second CD: an answer file for
`setup-alpine`, a hook that runs the installer and powers off, and the
script of the first boot from the disk, which adds the packages, makes
the users, locks root and reports on the console. Nothing is typed; the
host reads the console and seals the disk.

This is the newest of the four ways. Its first bake on real hardware is
the test of two assumptions: that the live ISO speaks on the serial
console under UEFI, and that `setup-disk` carries `/etc/local.d` onto
the disk the way `lbu package` does.

Prerequisites: `TUTORIAL_QUICKSTART.md`; `VM_BAKE_CONSOLE` set to
vm-bhyve's console kind (`nmdm` or `tmux`); the live ISO on the host --
the `virt` flavor carries the kernel with the virtio and 9p drivers.

## The chain

The base is the live ISO by path and sha256, its name `alpine-*.iso`;
the bake is `apkovl`:

    vm-bake template add alpine
    vm-bake template bake apkovl alpine
    vm-bake template add alpine-3.22 alpine
    vm-bake template base iso alpine-3.22 amd64 /data/iso/alpine-virt-3.22.1-x86_64.iso <sha256>
    vm-bake template add alpine-dev alpine-3.22
    vm-bake template resource alpine-dev 2 2G 20G
    vm-bake template package add alpine-dev git
    vm-bake template package add alpine-dev doas
    vm-bake template env add alpine-dev EDITOR vi
    vm-bake template user add alpine-dev brj host
    vm-bake template show alpine-dev

`doas` is a package on Alpine; the first boot adds it and writes the
rule `permit nopass keepenv brj as root` for every user of the template.
Packages come from the repositories `setup-apkrepos` picks (the first
mirror of the list, main and community); `source` lines are apt's and
get a note.

## What the template becomes

`image overlay write` renders the overlay aspect by aspect into
`overlay.d/etc`, and only into `etc`: `setup-disk` carries the live
system's `/etc` onto the disk (`lbu package`) and nothing else. Readable
under `cat`:

    vm-bake image record write alpine-dev img:alpine-dev:v1
    vm-bake setintp image_overlay_answer_write cat
    vm-bake image overlay answer write img:alpine-dev:v1
    vm-bake unsetintp image_overlay_answer_write
    vm-bake image drop img:alpine-dev:v1

- `etc/vm-bake/answerfile`: the answers of `setup-alpine -f` -- hostname
  of the bake, eth0 static on `VM_BAKE_FIRSTBOOT_ADDRESS`, gateway and
  nameserver `VM_BAKE_GUEST_GATEWAY`, the host's timezone, no user (the
  first boot makes them with their host uids), openssh, chrony, the whole
  disk `vda` in the `sys` mode.
- `etc/local.d/vm-bake-install.start`: run by the live system's local
  service. It removes itself (what stays in `etc` travels onto the disk),
  names `vda` in `ERASE_DISKS` so that `setup-disk` does not ask, runs
  `setup-alpine -e -f` and reports `# vm-bake install: complete, powering
  off` or `# vm-bake install: failed` on the console.
- `etc/local.d/vm-bake-firstboot.start`: travels onto the disk and does
  nothing on the live system, whose root is a tmpfs. At the first boot
  from the disk it removes itself, adds the packages and checks each
  against `apk info`, writes sshd on `VM_BAKE_SSH_PORT` without root and
  without passwords, makes the users (the shadow field `*`, so that sshd
  takes the key), the doas rule, the env lines as
  `/etc/profile.d/vm-bake.sh`, the template's files, the modules and the
  view's fstab lines, locks root, installs the seed hook as the up
  command of eth0, reports `# vm-bake firstboot: packages complete` or
  `missing <packages>`, and powers off.
- `etc/runlevels/default/local`: the link that starts the local service
  on the live system.
- `etc/.default_boot_services`: the marker that keeps the default services
  of the live init (devfs, mdev, hwdrivers, modloop). An apkovl is meant
  to bring its own runlevels; without the marker the live system has no
  kernel modules, and `setup-disk` cannot mount the filesystems it made.

The template's `file` lines go into `etc/vm-bake/files` (`image overlay
files place`); the first boot installs each at its path and removes the
staging. `image overlay pack` packs the files and links of `overlay.d` as
`vmbake.apkovl.tar.gz` and that one file as `overlay.iso`.

## The bake

    vm-bake image make alpine alpine-dev v1

`image create apkovl` makes the record and an empty disk; `image install
apkovl` renders and packs the overlay, hangs disk and overlay.iso on the
throwaway guest, starts it from the live ISO with `vm install` and watches
the console: the installer's report line, the power-off, `vm start` from
the disk (vm-bhyve would boot the live ISO again otherwise), the first
boot's report line. `image close iso` takes the digest, `image seal` the
snapshot. A wait that runs out prints the last screen, powers the guest
off and ends the bake; the watcher's trace under
`~/.vm-bake/db/.log/<date>/` holds what the guest printed.

The root acts are pinned to `sudo sh` as in the OpenBSD way; one sudo
over the whole batch pins `image_install_apkovl` the way `vm-bake help
image install` describes, with the ten acts of `image overlay write`,
`image_overlay_files_place`, `image_overlay_pack`,
`image_firstboot_conf_write` and `image_firstboot_conf_drop` on `sudo -u
<user> sh`.

## The guest

An Alpine guest reads the same seed CD as an OpenBSD guest (`guest seed
write autoinstall`): the hook `/usr/local/libexec/vm-bake-seed`, the up
command of eth0, looks on `sr0` and `sr1` for the marker `vm-bake-seed`,
takes hostname, address, netmask, gateway, resolv.conf and the ssh host
key, and configures eth0 and the default route; without a seed the bake's
address holds.

    vm-bake guest make img:alpine-dev:v1 dacia 172.16.100.104/24
    vm-bake guest start dacia
    ssh -p 2222 brj@dacia.local
    ssh -p 2222 brj@dacia.local cat /etc/vm-bake/packages

A template that says `service files view` gets the 9p modules and the
fstab lines of the view at the first boot; see `TUTORIAL_VIEW.md`.
