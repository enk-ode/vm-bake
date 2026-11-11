# Tutorial: the cloud-init way -- a Debian image from a cloud image

One topic: baking a Linux image from a distribution's cloud image and a
first boot that cloud-init drives. The host never mounts a Linux disk: the
image's disk is the cloud image written and grown, a seed CD carries what
the template decided, a throwaway guest boots once, cloud-init applies it
and powers off, the host seals the disk.

Prerequisites: `TUTORIAL_QUICKSTART.md`. vm-bhyve's console (`console=`
in its system.conf) is `nmdm` or `tmux`; `VM_BAKE_CONSOLE` names the same
word, because the bake reads the throwaway guest's serial console.

## The chain

The base is a cloud image by url and sha256 (`template base image`), the
bake is `cloud-init`:

    vm-bake template add debian
    vm-bake template bake cloud-init debian
    vm-bake template add debian-13 debian
    vm-bake template base image debian-13 amd64 13 https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.raw <sha256>
    vm-bake template add debian-dev debian-13
    vm-bake template resource debian-dev 4 8G 40G
    vm-bake template package add debian-dev git
    vm-bake template package add debian-dev sudo
    vm-bake template env add debian-dev EDITOR vi
    vm-bake template user add debian-dev brj host
    vm-bake template show debian-dev

The sha256 is the publisher's, or your own over a copy you trust; `image
create` fetches the file into `VM_BAKE_IMAGE_CACHE` once and verifies it
at every bake. `sudo` in the package list gives the template's users sudo
without a password (the Linux counterpart of `doas` on the BSDs). `rc`
lines are FreeBSD's; a Linux image notes and ignores them.

## Sources and files

Two list families exist for the Linux way. A `source` line is an apt
repository with the key that signs it: name, url, suite, component, the
url of the key and the key's sha256. The bake fetches the key, verifies
it against the sha256 and puts it into the seed; a key that does not match
ends the bake:

    vm-bake template source add debian-dev docker https://download.docker.com/linux/debian trixie stable https://download.docker.com/linux/debian/gpg 1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570
    vm-bake template package add debian-dev docker-ce

A `file` line puts a dowry -- an object kept in the database -- into the
image at an absolute path with a mode; cloud-init's `write_files` carries
it. The dowry has to be one file:

    vm-bake dowry add docker-daemon-json ~/Setup/docker-host/daemon.json
    vm-bake template file add debian-dev docker-daemon-json /etc/docker/daemon.json 0644
    vm-bake template file show debian-dev

A file the guest changes at runtime does not belong here but into the
home (`template home copy idem`, see `TUTORIAL_VIEW.md`).

A `daemon` line (`template daemon add <template> <name> <user>
'<program>'`, see `TUTORIAL_FREEBSD.md`) becomes a systemd unit
`<name>.service` in `write_files` (User, ExecStart, Restart=always), which
a per-once script enables at the bake's first boot; the daemon first runs
in a guest.

## The bake

    vm-bake image make linux debian-dev v1
    vm-bake image list

Three steps: `image create` (the cloud image fetched, verified, written
to disk0.img and grown to the resource's size), `image firstboot` (the
seed written and packed as seed.iso with the label cidata, the throwaway
guest `VM_BAKE_FIRSTBOOT` configured with the disk and the seed, started,
its console read until the first boot reports its packages, waited for
until it has powered itself off), `image close cloud` (the digest), then
`image seal`. The seed is a NoCloud seed: meta-data with the hostname of
the bake, network-config with `VM_BAKE_FIRSTBOOT_ADDRESS`, user-data with
the packages, the sources, the users (uid, the host key, no password),
sshd on `VM_BAKE_SSH_PORT` without root, the files, the view when the
template says so, and a last `runcmd` that checks every package with
`dpkg-query` and prints `# vm-bake firstboot: packages complete` -- or
`missing <packages>`, which ends the bake with an error naming them. The
pieces are acts of their own, readable under `cat`:

    vm-bake setintp image_seed_user_write cat
    vm-bake image seed user write img:debian-dev:v1
    vm-bake unsetintp image_seed_user_write

## The guest

A Linux guest is never mounted on the host either: `guest make` writes a
seed of its own with the guest's hostname, address, resolver and ssh host
key, and hangs it on as the guest's CD; cloud-init applies it at the first
start.

    vm-bake guest make img:debian-dev:v1 pannonia 172.16.100.105/24
    vm-bake guest start pannonia
    ssh -p 2222 brj@pannonia.local

## When the first boot fails

The console of the throwaway guest is read by `image firstboot report`,
whose trace under `~/.vm-bake/db/.log/<date>/` keeps what the guest
printed. A guest that did not come up within a minute, or did not power
off within an hour, ends the bake with an error; the throwaway guest is
then still there for inspection (`vm list`, `vm console firstboot`), and
the next bake's `image firstboot conf write` overwrites its configuration.
A bake that died with the lock: `vm-bake image lock drop`, then `vm-bake
image drop img:debian-dev:v1`.
