# EXAMPLES

A database, a chain of templates, the resolved view:

    vm-bake bootstrap production minimal
    vm-bake template add freebsd
    vm-bake template bake chroot freebsd
    vm-bake template firmware uefi freebsd
    vm-bake template add freebsd-15.1 freebsd
    vm-bake template base release freebsd-15.1 amd64 15.1-RELEASE
    vm-bake template add freebsd-dev freebsd-15.1
    vm-bake template resource freebsd-dev 8 32G 64G
    vm-bake template package add freebsd-dev vscode
    vm-bake template show freebsd-dev

A record is immutable: drop it, then add; an inherited list entry is
masked in the child, not dropped:

    vm-bake template base drop freebsd-15.1
    vm-bake template package mask freebsd-dev emacs

The dump is the replay, parents before children:

    vm-bake dump > templates.dump
    vm-bake restore templates.dump
