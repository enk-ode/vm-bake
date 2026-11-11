% VM_BAKE(8) vm-bake | System Manager's Manual
% Dr. Johannes Brügmann
% November 11, 2026

# NAME

vm-bake - bake images and guest configurations for vm-bhyve

# SYNOPSIS

**vm-bake** *command* [*arguments*]

**vm-bake help** [*command* | *group* | *topic*]

# DESCRIPTION

**vm-bake** turns a declared template into an image, a guest and the
host-side plumbing around it, reproducibly. A *template* is the build
recipe: operating system base, packages, configuration, users, the host
services a guest may use, resources, lifetime; templates inherit from a
parent down to the root `empty`. An *image* is what baking a template
yields, a *guest* a clone of an image with its rendered vm.conf, a
*session* the client script that brings one application of the guest onto
the host desktop. There is one home, the host's: a guest whose template
says `service files view` mounts a *view* of it over virtio-9p, sees of the
rest what the template's home lines allow, and works in its own clones of
the host's repositories. Starting and stopping guests stays with vm-bhyve.

Four ways bake an image, chosen by the template's `bake` word: `chroot`
(FreeBSD: pkgbase into the mounted disk, on the host or in a builder
guest, no first boot), `cloud-init` (Linux: a cloud image and a seed CD,
one first boot), `autoinstall` (OpenBSD: the install ISO with a response
file and a site set on a second CD, the console driven) and `apkovl`
(Alpine: the live ISO and an overlay on a second CD, unattended). Every
way ends with the first boot reporting its packages on the console; a
missing package ends the bake with an error naming it.

Every command GENERATES shell text; an interpreter the user pins decides
whether that text is displayed (the default, `cat`) or executed. The
bookkeeping of the templates is pinned to act; the bake, once there, shows
its shell first. All records live in a database (`~/.vm-bake/db` by
default) that dumps and restores as replay lines.

# SOURCES

<https://github.com/enk-ode/vm-bake> (BSD-2-Clause).

# COMMANDS

Every command, grouped as `vm-bake help` groups it. `vm-bake help <command>` shows parameters, environment and examples.

## Without a database

The commands that run before a database exists: bootstrap creates one,
help and the manual read the shipped corpus, complete serves the shell.
Start here.

**bootstrap \<name\> \<profile\>**
:   Create the database ~/.vm-bake/\<name\> (under VM_BAKE_ROOT) with the named profile and point the active-DB symlink db at it. \<name\> is a plain name, not a path: a slash is refused, db is reserved

**help [\<command\|group\|topic\>]**
:   Show the grouped overview, or detail for a command, group or topic

**help environment**
:   The concept topic: the environment system and the safety-first design (interpreters, pins, the three-layer cascade, profiles, logs) -- template/manual/topic-environment.md

**help manual**
:   Emit the complete manual as Pandoc Markdown, part by part: the title block, the prose building blocks from template/manual/, COMMANDS from the help corpus, ENVIRONMENT from the variable templates -- one truth per content kind (make man renders vm-bake.8 from it)

**help manual title**
:   The Pandoc title block of the manual: name, section, author, today's date

**help manual commands**
:   The COMMANDS section of the manual, generated from the help corpus and grouped as 'vm-bake help' groups it

**help manual environment**
:   The ENVIRONMENT section of the manual: one entry per shipped variable template, its @summary as the body -- the templates ARE the corpus (help env reads the same files)

**complete [\<words\>]**
:   Print completion candidates for a partially typed command line (bash-completion back-end): the words typed so far, the last one being the word under the cursor

**Inspect-by-default**
:   
    Every anchor runs under a pin. The bookkeeping (template add/drop/mask,
    setenv, dowry add) and the acts of the bakes and the guests are pinned
    to sh in the profile (sudo sh where zfs, md or vm-bhyve are involved,
    ssh into the builder when VM_BAKE_BAKE_IN says so), the display
    terminals (list, show, find) to cat; the class default
    VM_BAKE_TERMINAL_INTERPRETER=cat catches a terminal without a pin, so
    it prints instead of acting. A command therefore acts when typed; to
    see first what it would do, pin it to cat for the moment:
    vm-bake setintp image_make_freebsd_from cat   (the plan of the batch)
    vm-bake setintp image_disk_create cat         (the shell of one act)
    vm-bake unsetintp image_disk_create           (the profile's pin again)
    A batch pinned to cat prints its lines and runs none of them, setenv
    and unsetenv included. Every call leaves its trace under
    \<db\>/.log/\<date\>/ with the resolved interpreter, the text handed to it
    and its answer -- read that before running anything again.

## Configuration

The database's environment: the profile installed and re-synced
(environment init), the cache, the freeze; variables and interpreter
pins read and changed (setenv, getenv, unsetenv, setintp, getintp).

**environment init [\<profile\>]**
:   Install a profile's template variables into .env/default -- a line of init, and the step after an update of vm-bake: a variable new in template/environment reaches a database only this way (the cache is dropped with it). Without an argument the profile is the database's own, read from .env/default/VM_BAKE_PROFILE_\<PROFILE\> (profile show): rewrite to 'environment init \<profile\>'; no profile installed, or more than one, is an error

**profile show**
:   The database's profile: the name from .env/default/VM_BAKE_PROFILE_\<PROFILE\>, how many variables that list names, how many of them .env/default holds, and how many the shipped list of the same profile names now -- a shipped count above the installed one says 'environment init' is due

**environment cache [on\|off\|status]**
:   Manage the cached-environment optimisation

**environment cache on**
:   Build the environment cache, the pattern of stage site mk: 'environment cache render' redirected into .env/local/VM_BAKE_CACHE_ENV_ARGS.new (a fresh scan of .env/), then 'environment cache place' moves it into place (0600) and says how many variables. The scan happens when the lines run, not when this command generates: a compiled script carries them, and they see the setenv acts before them. A database whose cache predates this version knows no pin for 'place' and only displays it: re-sync first (environment init \<profile\>), it drops the cache

**environment refresh**
:   The environment as a new call finds it: at generation time VM_BAKE_CACHE_ENV_ARGS and VM_BAKE_CONTEXT_BOOTSTRAPPED are unset; the lines are 'environment cache off' and 'environment cache on' -- the cache rebuilt from .env/ when they run, the calls after them look their pins up afresh. A dump places it after the setenv lines of its prologue and of its epilogue

**environment cache off**
:   Remove the environment cache; later invocations read the layered store again

**environment cache status**
:   Is the environment cache on, how many variables does it hold, and is the environment frozen (environment freeze)?

**environment freeze \<name\>**
:   Freeze the interpreter environment of this database, with no way back: the name IS the confirmation (as destroy), a warning says what goes, then every machine override that weakens a combinator or batch pin is removed (environment freeze pins), the terminal default becomes sh (acts run), the marker .env/frozen is written, the cache rebuilt. Frozen, setenv and unsetenv refuse those pins. The shipped defaults are the only interpreters that read ONE line reliably (head -n1 \| xargs ... for a combinator, the batch runner for a batch): a pin of sh or cat there works until two lines stand on stdin. A pin that must deviate is a decision taken BEFORE the freeze, in the template that ships it, never a machine override afterwards. Assumes: the database is provisioned and about to be trusted with acts; there is no thaw

**setenv \<VAR\> \<value\>**
:   Set a machine override: the name is a variable name, a frozen database allows it (environment frozen allows: no combinator or batch pin after environment freeze), the value is written to .env/local/\<VAR\> (0640, owner of the database when possible), the environment cache refreshed when one is on. Effective with the next command

**getenv \<VAR\>**
:   Show the effective value of a variable and the layer that answers (.env/local override, .env/default, the shipped template): the variable resolves: rewrite to 'getenv read \<VAR\> \<layer\> \<path\>', else an error line

**unsetenv \<VAR\>**
:   Remove the machine override .env/local/\<VAR\> when there is one (else say so) -- a frozen database allows it first (environment frozen allows) -- and refresh the environment cache when one is on

**printenv [\<VAR\>]**
:   Show all effective environment variables, or just one

**help env [\<name\> [\<location\>]]**
:   Text terminal: the documented variables (templates, and the copies under .env); show one with 'help env \<name\>' -- the name resolves literal, then VM_BAKE_\<name\>, then VM_BAKE_INTERPRETER_\<name\>

**setintp \<function\> \<interpreter\>**
:   Pin a function's interpreter: rewrite to 'setenv VM_BAKE_INTERPRETER_\<function\> \<interpreter\>' -- sugar for the pin's name, nothing more; a class default is set with setenv by its own name

**getintp \<function\>**
:   Show a function's pinned interpreter: rewrite to 'getenv VM_BAKE_INTERPRETER_\<function\>'

**unsetintp \<function\>**
:   Drop a function's local interpreter pin: rewrite to 'unsetenv VM_BAKE_INTERPRETER_\<function\>'; the default of the profile applies again

**help intp \<function\> [\<location\>]**
:   Show the documentation of a function's interpreter pin: rewrite to 'help env VM_BAKE_INTERPRETER_\<function\>'

## Database lifecycle

Back up, restore and batch-drive the database itself.

**dump env prologue**
:   Emit the prologue of a dump: the SOURCE's .env/local overrides that the restore itself depends on (the PROLOGUE profile's list -- deliberately WITHOUT function-specific interpreter pins, which could deactivate replayed commands), then 'environment refresh' so the pins hold for the lines after it

**dump env epilogue**
:   Emit the epilogue of a dump: EVERY .env/local override of the source, including function-specific interpreter pins -- restored at the very end, when the replay is done

**destroy \<name\>**
:   Remove this database and everything it owns, IRRECOVERABLY, as three steps: the worktrees and their registration in the source repo, the records, the scaffolding (bundle handover area, active-DB symlink, empty root). The name IS the confirmation, checked before a line runs

**destroy records \<name\>**
:   Step 2 of destroy: the name is this database's: rewrite to 'destroy records remove' (the database directory itself, resolved through the active-DB symlink first -- rm -rf on a symlink removes the LINK and orphans the database), else an error line

**destroy scaffold \<name\>**
:   Step 3 of destroy: the name is this database's: rewrite to 'destroy scaffold remove' (the bundle handover area, the active-DB symlink if it points here, the empty scaffolding), else an error line

**version**
:   Print the version of this vm-bake: the dump format it writes and restores (VM_BAKE_FORMAT) and the commit of the checkout it runs from (git; 'unknown' without one) -- what a dump carries in its header and what a report names

**batch \<file\>**
:   Execute a file of vm-bake commands line by line (VM_BAKE_BATCH_KEEP_GOING: 0 = stop at the first failing line, 1 = keep going): the file is readable: rewrite to the runner 'batch \<file\> false' (no cleanup), else an error line

**dump [\<template\>]**
:   The complete dump of this database as replay lines (rewrite to 'dump all'), or one template (rewrite to 'template dump \<template\>')

**dump all**
:   The database as replay lines: the header (generator, format, date, profile, base), the prologue (the overrides the replay depends on), the dowry records and the ssh host key records as witnesses (their objects and keys travel in the bundle), the templates parents first, the image and guest records as witnesses, the epilogue (every override, the pins included)

**restore \<file\>**
:   Replay a dump into this database: rewrite to 'batch \<file\>' -- the replay stops at the first failing line; an existing template is never re-minted, an identical record is a note

## Templates

A template is the build recipe of an image: the base (a release, a
stage, a cloud image, an iso), how it is baked, firmware, resources,
and the lists of packages, rc.conf lines, users, host services the
guest may use, what it must not reach, its data disks, session
protocols and the daemons its init starts. Templates inherit: scalars from the nearest ancestor, lists
as the union of the chain minus the masks. The root 'empty' always
exists and holds nothing.

**template list**
:   List the templates with their derived state (one line each): name, id, parent, own base -- the root 'empty' first

**template add \<template\> [\<parent\>]**
:   Create a template below a parent (the root 'empty' when none is named): rewrite to 'template add \<template\> empty'

**template drop \<template\>**
:   Remove a template: it exists, it is not the root and no template names it as parent; then 'template unlink'

**template show \<template\>**
:   The template resolved over its chain: the head (parent, chain, the scalars with their origin), then every list with the origin of each line

**template base release \<template\> \<arch\> \<version\>**
:   The base is a FreeBSD release from the pkgbase repository (bake: chroot): the template exists, arch and version are valid; then the record 'release \<arch\> \<version\>' (immutable: template base drop first)

**template base stage \<template\> \<arch\> \<stage\>**
:   The base is self-baked: the worktree of an elvboot stage, 'make packages' yields the repository (bake: chroot): the template exists, the arch is valid, the stage is a record name; then the record 'stage \<arch\> \<stage\>'

**template base image \<template\> \<arch\> \<version\> \<url\> \<sha256\>**
:   The base is a ready-made image (a FreeBSD VM image, a Linux cloud image): the template exists, arch, version (a word; FreeBSD's \<major\>.\<minor\>-RELEASE gives the ABI), url and digest are valid; then the record 'image \<arch\> \<version\> \<url\> \<sha256\>'

**template base iso \<template\> \<arch\> \<path\> \<sha256\>**
:   The base is an installation medium -- the install ISO of OpenBSD (bake autoinstall), a live ISO of Alpine (bake apkovl), Windows (bake cloud-init via cloudbase-init): the template exists, arch, path and digest are valid; then the record 'iso \<arch\> \<path\> \<sha256\>'

**template base drop \<template\>**
:   Remove the template's own base record: the template exists, a base is set; then 'template leaf erase'

**template bake chroot \<template\>**
:   The image is baked offline: the base installed into the mounted image (mdconfig), packages and configuration via chroot, no first boot: the template exists; then the record

**template bake cloud-init \<template\>**
:   The image is baked by a first boot in a throwaway guest: cloud-init (cloudbase-init on Windows) applies packages and configuration from the rendered user-data, then the disk is sealed: the template exists; then the record

**template bake autoinstall \<template\>**
:   The image is installed by OpenBSD's autoinstall(8) in a throwaway guest: the base is the install ISO (template base iso), the response file and a site set rendered from the template answer the installer, the first boot adds the packages and powers off, then the disk is sealed: the template exists; then the record

**template bake apkovl \<template\>**
:   The image is installed by Alpine's setup-alpine in a throwaway guest: the base is a live ISO of Alpine (template base iso), an overlay rendered from the template (the apkovl the live system takes from a second CD) answers the installer, the first boot adds the packages and powers off, then the disk is sealed: the template exists; then the record

**template bake drop \<template\>**
:   Remove the template's own bake record: the template exists, a bake is set; then 'template leaf erase'

**template firmware uefi \<template\>**
:   The guest boots UEFI (edk2-bhyve): the template exists; then the record

**template firmware bios \<template\>**
:   The guest boots BIOS (grub2-bhyve): the template exists; then the record

**template firmware drop \<template\>**
:   Remove the template's own firmware record: the template exists, a firmware is set; then 'template leaf erase'

**template resource \<template\> \<cpu\> \<memory\> \<disk\>**
:   The guest's resources: cpus, memory and the size of disk0 (the image): the template exists, the count and the sizes are valid; then the record '\<cpu\> \<memory\> \<disk\>'

**template topology \<template\> \<sockets\> \<cores\> \<threads\>**
:   How the guest's cpus are laid out for the guest's own scheduler: sockets, cores per socket, threads per core; the template exists and the three are counts whose product is the cpu count of 'template resource' (checked when the guest's configuration is written, where both are read); then the record '\<sockets\> \<cores\> \<threads\>'. Without a record a guest gets 1 socket of \<cpu\> cores with 1 thread each -- one real core per cpu, which is what bhyve should present unless a guest is meant to see SMT

**template topology drop \<template\>**
:   Remove the template's own topology record: the template exists, a topology is set; then 'template leaf erase' -- its guests fall back to 1 socket of \<cpu\> cores with 1 thread each

**template resource drop \<template\>**
:   Remove the template's own resource record: the template exists, a resource is set; then 'template leaf erase'

**template package add \<template\> \<package\>\|-**
:   Add a package to the template's own list (idempotent); '-' reads names from stdin, one per line, each validated before anything is appended: rewrite to 'template package add stdin \<template\>', else to 'template package add entry \<template\> \<package\>'

**template package drop \<template\> \<package\>**
:   Remove a package from the template's own list: the template exists, the package is listed there; then 'template line remove'

**template package mask \<template\> \<package\>**
:   Hide an inherited package in this template and below (own entries are dropped, not masked): the template exists, the name is a package name; then 'template line mask'

**template package show \<template\>**
:   The packages resolved over the chain, each with its origin: the template exists; then 'template chain table'

**template port add \<template\> \<origin\>**
:   Add a port to build from source in the builder guest (category/name): the template exists, the origin is a port origin; then 'template line append' -- the bake builds it there and installs the package into the image after the packages

**template port drop \<template\> \<origin\>**
:   Remove a port from the template's own list: the template exists, the origin is listed there; then 'template line remove'

**template port mask \<template\> \<origin\>**
:   Hide an inherited port in this template and below: the template exists, the origin is valid; then 'template line mask'

**template port show \<template\>**
:   The ports resolved over the chain, each with its origin template: the template exists; then 'template chain table'

**template pkgfile add \<template\> \<file\>**
:   Add a package file to install from VM_BAKE_PKG_DIR (a .pkg of the same ABI, kept there by you, e.g. from another host's package cache): the template exists, the name is a file name ending in .pkg; then 'template line append' -- the bake stages it into the image and installs it with 'pkg add', dependencies from the repositories

**template pkgfile drop \<template\> \<file\>**
:   Remove a package file from the template's own list: the template exists, the file is listed there; then 'template line remove'

**template pkgfile mask \<template\> \<file\>**
:   Hide an inherited package file in this template and below: the template exists, the name is valid; then 'template line mask'

**template pkgfile show \<template\>**
:   The package files resolved over the chain, each with its origin template: the template exists; then 'template chain table'

**template tag add \<template\> \<key\> \<text\>**
:   Add a tag to the template's own list, a key and a text, inherited like every list (purpose, task, owner, can ... -- the keys are yours): the template exists, the key is a word; then 'template line append'. 'template find' and 'guest find' search them

**template tag drop \<template\> \<key\> \<text\>**
:   Remove a tag from the template's own list: the template exists, the line is listed there; then 'template line remove'

**template tag mask \<template\> \<key\> \<text\>**
:   Hide an inherited tag in this template and below: the template exists, the key is a word; then 'template line mask'

**template tag show \<template\>**
:   The tags resolved over the chain, each with its origin template: the template exists; then 'template chain table'

**template find \<key\> \<pattern\>**
:   Display terminal: every template whose resolved tags (read over its chain) hold the key with a text matching the pattern -- an extended regular expression, case-insensitive, searched in the text alone and not in the names around it ('.' for any text, '^15\.1$' for exactly that value): one line per hit, template, origin of the tag, the tag

**template env add \<template\> \<variable\> \<value\>**
:   Add an environment variable for the sessions of every guest of this template (XCURSOR_THEME, LANG, ...): the template exists, the variable is a name, the value a plain word; then 'template line append' -- the bake writes them into /etc/profile.d/vm-bake.sh of the image, and 'session create x' hands them to the program it runs

**template env drop \<template\> \<variable\> \<value\>**
:   Remove an environment variable from the template's own list: the template exists, the line is listed there; then 'template line remove'

**template env mask \<template\> \<variable\> \<value\>**
:   Hide an inherited environment variable in this template and below: the template exists, the variable is a name; then 'template line mask'

**template env show \<template\>**
:   The environment variables resolved over the chain, each with its origin template: the template exists; then 'template chain table'

**template home add \<template\> \<path\> [\<mode\>]**
:   Add a path of the invoking user's home (its path from the user name, the batch environment carries no HOME; relative, e.g. .themes/NsCDE or .config/gtk-3.0) to the view every guest of this template gets of that home, read-only (ro) unless the mode says rw: rewrite to 'template home add \<template\> \<path\> ro'

**template home drop \<template\> \<path\> [\<mode\>]**
:   Remove a home path from the template's own list, the line being '\<path\> \<mode\>' with ro as the default: rewrite to 'template home drop \<template\> \<path\> ro'

**template home mask \<template\> \<path\> [\<mode\>]**
:   Hide an inherited home line '\<path\> \<mode\>' in this template and below, ro as the default: rewrite to 'template home mask \<template\> \<path\> ro'

**template home show \<template\>**
:   The home paths resolved over the chain, each with its origin template: the template exists; then 'template chain table'

**template home copy idem \<template\> \<dowry\> \<destination\>**
:   Hand a dowry to the home of every guest of this template, where it is missing: the template exists, the dowry is kept in the database, the destination is a plain path relative to the home; then 'template line append' of 'copy idem \<dowry\> \<destination\>'. 'guest start' places it before it hangs the overlays in; what the guest makes of it afterwards stays its own

**template home copy overwrite \<template\> \<dowry\> \<destination\>**
:   Hand a dowry to the home of every guest of this template at every start, replacing what is there: the template exists, the dowry is kept, the destination is plain; then 'template line append' of 'copy overwrite \<dowry\> \<destination\>'. What the guest wrote at that path is gone with the next 'guest start' -- for anything the guest keeps working on, 'idem' is the word

**template home unlink idem \<template\> \<dowry\> \<destination\>**
:   Take the rule back from the template's own list: the template exists, the line 'copy idem \<dowry\> \<destination\>' is listed there; then 'template line remove'. What already lies in a guest's view stays -- it belongs to the guest

**template home unlink overwrite \<template\> \<dowry\> \<destination\>**
:   Take the rule back from the template's own list: the template exists, the line 'copy overwrite \<dowry\> \<destination\>' is listed there; then 'template line remove'

**template home mask idem \<template\> \<dowry\> \<destination\>**
:   Hide an inherited rule 'copy idem \<dowry\> \<destination\>' in this template and below: the template exists, the destination is plain; then 'template line mask'. The guests of this template get that dowry no longer -- the dowry itself stays in the database

**template home mask overwrite \<template\> \<dowry\> \<destination\>**
:   Hide an inherited rule 'copy overwrite \<dowry\> \<destination\>' in this template and below: the template exists, the destination is plain; then 'template line mask'

**template home unmask idem \<template\> \<dowry\> \<destination\>**
:   Take such a mask back: the template exists, the line 'copy idem \<dowry\> \<destination\>' is masked here; then 'template line unmask' -- the inherited rule reaches this template and everything below it again

**template home unmask overwrite \<template\> \<dowry\> \<destination\>**
:   Take such a mask back: the template exists, the line 'copy overwrite \<dowry\> \<destination\>' is masked here; then 'template line unmask'

**template rc add \<template\> \<variable\> \<value\>**
:   Add an rc.conf line '\<variable\>="\<value\>"' to the template's own list: the template exists, the variable is an rc.conf name, the value a plain word; then 'template line append'

**template rc drop \<template\> \<variable\> \<value\>**
:   Remove the rc.conf line from the template's own list: the template exists, the line is listed there; then 'template line remove'

**template rc mask \<template\> \<variable\> \<value\>**
:   Hide an inherited rc.conf line in this template and below: the template exists, the names are valid; then 'template line mask'

**template rc show \<template\>**
:   The rc.conf lines resolved over the chain, each with its origin: the template exists; then 'template chain table'

**template user add \<template\> \<name\> \<uid\>\|host**
:   Add a user of the guest to the template's own list, with a numeric uid or 'host' (the uid the user has on the host, read at bake time): the template exists, name and uid are valid; then 'template line append'

**template user drop \<template\> \<name\> \<uid\>\|host**
:   Remove the user from the template's own list: the template exists, the entry is listed there; then 'template line remove'

**template user mask \<template\> \<name\> \<uid\>\|host**
:   Hide an inherited user in this template and below: the template exists, name and uid are valid; then 'template line mask'

**template user show \<template\>**
:   The users resolved over the chain, each with its origin: the template exists; then 'template chain table'

**template service add \<template\> \<kind\> \<variant\>**
:   Add a host service the guest may use to the template's own list: the template exists, kind and variant are valid (display x\|rdp\|none, audio pulse\|sndio\|none, clipboard broker\|none, files disk\|none, net \<switch\>, token none); then 'template line append'

**template service drop \<template\> \<kind\> \<variant\>**
:   Remove the service from the template's own list: the template exists, the entry is listed there; then 'template line remove'

**template service mask \<template\> \<kind\> \<variant\>**
:   Hide an inherited service in this template and below: the template exists, kind and variant are valid; then 'template line mask'

**template service show \<template\>**
:   The services resolved over the chain, each with its origin: the template exists; then 'template chain table'

**template forbid add \<template\> \<kind\> [\<argument\>]**
:   Add what the guest must not reach to the template's own list -- the list the witness module proves: usb (no device passthrough), net \<cidr\> (the network), switch \<name\> (the vm-bhyve switch): the template exists, kind and argument are valid; then 'template line append'

**template forbid drop \<template\> \<kind\> [\<argument\>]**
:   Remove the entry from the template's own list: the template exists, the entry is listed there; then 'template line remove'

**template forbid mask \<template\> \<kind\> [\<argument\>]**
:   Hide an inherited entry in this template and below: the template exists, kind and argument are valid; then 'template line mask'

**template forbid show \<template\>**
:   The forbidden list resolved over the chain, each with its origin: the template exists; then 'template chain table'

**template data add \<template\> \<name\> \<size\> \<class\>**
:   Add a data disk of the guest (a zvol outside the image, surviving every new image) to the template's own list, with its backup class (the value of enk-ode:backup): the template exists, name, size and class are valid; then 'template line append'

**template data drop \<template\> \<name\> \<size\> \<class\>**
:   Remove the data disk from the template's own list: the template exists, the entry is listed there; then 'template line remove'

**template data mask \<template\> \<name\> \<size\> \<class\>**
:   Hide an inherited data disk in this template and below: the template exists, the entry is valid; then 'template line mask'

**template data show \<template\>**
:   The data disks resolved over the chain, each with its origin: the template exists; then 'template chain table'

**template session add \<template\> \<protocol\>**
:   Add a session protocol the guest offers (rdp, ssh, x) to the template's own list: the template exists, the protocol is valid; then 'template line append'

**template session drop \<template\> \<protocol\>**
:   Remove the protocol from the template's own list: the template exists, the entry is listed there; then 'template line remove'

**template session mask \<template\> \<protocol\>**
:   Hide an inherited protocol in this template and below: the template exists, the protocol is valid; then 'template line mask'

**template session show \<template\>**
:   The protocols resolved over the chain, each with its origin: the template exists; then 'template chain table'

**template package unmask \<template\> \<package\>**
:   Take a mask back: the template exists, the name is a package name, the line is masked here; then 'template line unmask' -- what the chain inherits is visible again

**template port unmask \<template\> \<origin\>**
:   Take a mask back: the template exists, the origin is valid, the line is masked here; then 'template line unmask'

**template pkgfile unmask \<template\> \<file\>**
:   Take a mask back: the template exists, the name is valid, the line is masked here; then 'template line unmask'

**template tag unmask \<template\> \<key\> \<text\>**
:   Take a mask back: the template exists, the key is a word, the line is masked here; then 'template line unmask'

**template env unmask \<template\> \<variable\> \<value\>**
:   Take a mask back: the template exists, the name is a variable name, the line is masked here; then 'template line unmask'

**template rc unmask \<template\> \<variable\> \<value\>**
:   Take a mask back: the template exists, the name is a variable name and the value a word, the line is masked here; then 'template line unmask'

**template user unmask \<template\> \<name\> \<uid\>\|host**
:   Take a mask back: the template exists, name and uid are valid, the line is masked here; then 'template line unmask'

**template home unmask \<template\> \<path\> [\<mode\>]**
:   Take a mask back, the line being '\<path\> \<mode\>' with ro as the default: rewrite to 'template home unmask \<template\> \<path\> ro'

**template service unmask \<template\> \<kind\> \<variant\>**
:   Take a mask back: the template exists, kind and variant are valid, the line is masked here; then 'template line unmask'

**template forbid unmask \<template\> \<kind\> [\<argument\>]**
:   Take a mask back: the template exists, kind and argument are valid, the line is masked here; then 'template line unmask'

**template data unmask \<template\> \<name\> \<size\> \<class\>**
:   Take a mask back: the template exists, the entry is valid, the line is masked here; then 'template line unmask'

**template session unmask \<template\> \<protocol\>**
:   Take a mask back: the template exists, the protocol is valid, the line is masked here; then 'template line unmask'

**template dump \<template\>**
:   The template as replay lines (template add, the scalars, every list entry and mask): the template exists; then 'template dump record'

**template dump all**
:   Every template as replay lines, parents before children (a replay recreates the chain in order)

**template restore \<file\>**
:   Replay a dump of templates (the lines 'template dump' wrote): rewrite to 'batch \<file\>' -- idempotent, an existing template is never re-minted, an identical scalar is a note

**template source add \<template\> \<name\> \<url\> \<suite\> \<component\> \<keyurl\> \<sha256\>**
:   Add a package source beyond the distribution's own to the template's own list: the template exists, name, suite and component are words, url and keyurl are http(s), the digest is the sha256 of the signing key behind keyurl; then 'template line append' of '\<name\> \<url\> \<suite\> \<component\> \<keyurl\> \<sha256\>'. A Linux bake fetches the key once into its cache and verifies it (image key fetch, image key verify), writes it into the seed as apt.sources.\<name\> with the line 'deb [signed-by=$KEY_FILE] \<url\> \<suite\> \<component\>', and the template's packages install from it; the FreeBSD and OpenBSD bakes note the lines and leave them (pkg and pkg_add have their own repositories)

**template source drop \<template\> \<name\> \<url\> \<suite\> \<component\> \<keyurl\> \<sha256\>**
:   Remove the source line from the template's own list: the template exists, the line is listed there (template source show prints it to copy); then 'template line remove'

**template source mask \<template\> \<name\> \<url\> \<suite\> \<component\> \<keyurl\> \<sha256\>**
:   Hide an inherited source line in this template and below: the template exists, the words, urls and digest are valid; then 'template line mask'

**template source unmask \<template\> \<name\> \<url\> \<suite\> \<component\> \<keyurl\> \<sha256\>**
:   Take a mask back: the template exists, the line is masked here; then 'template line unmask'

**template source show \<template\>**
:   The package sources resolved over the chain, each with its origin: the template exists; then 'template chain table'

**template file add \<template\> \<dowry\> \<path\> \<mode\>**
:   Put a dowry into the system of every image of this template, as a file at an absolute path: the template exists, the dowry is kept in the database and is one file, the path is absolute, the mode three or four octal digits; then 'template line append' of '\<dowry\> \<path\> \<mode\>'. The file belongs to root and is written at the bake: by cloud-init's write_files in a Linux image (image seed file write), into the mounted disk of a FreeBSD image (image file write), into the site set of an OpenBSD image (image site files place). A path that a guest changes at runtime belongs into the home instead (template home copy idem)

**template file drop \<template\> \<dowry\> \<path\> \<mode\>**
:   Remove the file line from the template's own list: the template exists, the line is listed there; then 'template line remove'

**template file mask \<template\> \<dowry\> \<path\> \<mode\>**
:   Hide an inherited file line in this template and below: the template exists, path and mode are valid; then 'template line mask'

**template file unmask \<template\> \<dowry\> \<path\> \<mode\>**
:   Take a mask back: the template exists, the line is masked here; then 'template line unmask'

**template file show \<template\>**
:   The file lines resolved over the chain, each with its origin: the template exists; then 'template chain table'

**template daemon add \<template\> \<name\> \<user\> \<program\>**
:   Add a daemon of the guest to the template's own list -- a program the init of every image of this template starts at boot and keeps running, under the user, as the service \<name\>: the template exists, the name is an identifier (a letter or underscore, then letters, digits, underscores: it names the rc.d script, the OpenRC script, the systemd unit and the rc.conf variable \<name\>_enable), the user is a login name (root, or a user of the template's user list -- image check daemons holds it against that list at the bake), the program is one word of command line (letters, digits, single blanks and ._/:=,@+%-, nothing the shell would read); then 'template line append' of '\<name\> \<user\> \<program\>'. The bake renders the line per way: an rc.d script under daemon(8) with restart on FreeBSD (image daemon write), an rc.d script with rc_bg on OpenBSD (image site daemon write), an OpenRC script in the overlay on Alpine (image overlay daemon write), a systemd unit with Restart=always on Debian (image seed daemon write). The daemon runs from the first boot of a guest, never in the bake. A bare program name is looked up in the system's path, /usr/local included; HOME is the user's home; where the init keeps no journal, stdout and stderr go to /var/log/\<name\>.log

**template daemon drop \<template\> \<name\> \<user\> \<program\>**
:   Remove the daemon line from the template's own list: the template exists, the line is listed there (template daemon show prints it to copy); then 'template line remove'

**template daemon mask \<template\> \<name\> \<user\> \<program\>**
:   Hide an inherited daemon line in this template and below: the template exists, name, user and program are valid; then 'template line mask'

**template daemon unmask \<template\> \<name\> \<user\> \<program\>**
:   Take a mask back: the template exists, the line is masked here; then 'template line unmask'

**template daemon show \<template\>**
:   The daemon lines resolved over the chain, each with its origin: the template exists; then 'template chain table'

## Images

An image is a baked disk: the decisions of a template applied to a
FreeBSD base, on a sparse disk (GPT, an EFI system partition labelled
\<image\>-efi and a UFS root labelled \<image\>-root) under
VM_BAKE_IMAGE_DIR/\<image\>, sealed by the ZFS snapshot @image and
readonly. The base is the template's: 'release' installs pkgbase with
'pkg -r' (that needs securelevel -1, so it runs in the builder guest),
'image' writes a FreeBSD VM image fetched from its url and verified
against its sha256 (the host does it; this is how the builder itself is
made). 'image make freebsd \<template\>' names the image
\<template\>-\<yyyymmdd\> and runs create, base, burn, close and seal in
turn; each is a command of its own. VM_BAKE_BAKE_IN says where base,
burn and close act: 'host' (the acts pinned to sudo sh) or 'builder'
(pinned to ssh into the builder guest, which mounts the image's disk
under the same path); 'image builder use' and 'image builder leave'
switch between them, visibly, as setintp lines. One bake at a time:
create takes a lock under .tmp, seal drops it.

**image make freebsd \<template\> \<version\>**
:   Bake a FreeBSD image from the template under the version: the image is img:\<template\>:\<version\>, handed to 'image make freebsd from' -- a version is yours to choose (v1, v2, v20261107); a name that is taken stops at 'image create', and the next version is the answer; two more spellings: the full name alone (image make freebsd img:\<template\>:\<version\>) and a name of its own (image make freebsd \<template\> \<version\> img:\<name\>:\<version\>)

**image create \<template\> \<image\>**
:   Step 1, the disk: by the template's resolved base kind (read at generation time) rewrite to 'image create release' (an empty GPT disk for pkgbase) or 'image create image' (the FreeBSD VM image written and grown); a stage base or none is an error line

**image base \<image\>**
:   Step 2, the operating system: by VM_BAKE_BAKE_IN rewrite to 'image base host' (the disk attached and mounted on the host) or 'image base builder' (the builder guest started with the disk, mounted there); any other value is an error line

**image burn \<image\>**
:   Step 3, the template: the image has a record, every user of the template resolves (a host uid exists, the key file VM_BAKE_HOST_KEY is readable); then the template's packages via 'pkg -r', its package files from VM_BAKE_PKG_DIR staged and added, its ports built and installed in the builder (an error line when ports are listed and VM_BAKE_BAKE_IN is host), its rc.conf lines, its env variables as profile.d, its users with the host key in authorized_keys, the view of the host's home when the template says 'service files view', root locked (pkgbase ships root without a password), doas for them when the template lists doas, and sshd on VM_BAKE_SSH_PORT with keys only and no root -- where VM_BAKE_BAKE_IN says (the pins)

**image close \<image\>**
:   Step 4, the disk closed: by VM_BAKE_BAKE_IN rewrite to 'image close host' or 'image close builder'; any other value is an error line

**image seal \<image\>**
:   Step 5, the seal: the image has a record and a digest, the bake lock is this image's; then the snapshot @image, the dataset readonly, the lock dropped

**image drop \<image\>**
:   Remove an image: it has a record; unmounted and detached on the host if it still is, its dataset destroyed (a guest cloned from it makes zfs refuse), the record removed, the bake lock dropped when it is this image's

**image prune**
:   Drop every image no guest is made from: the image records and the image file of every guest record read at generation time; a sealed image (it has a digest) that no guest names gets its 'image drop' line, an open image (no digest: a bake under way, or one that died with the lock -- image lock drop, then image drop by name) is left with a note; every image in use is a comment

**image builder use**
:   Bake in the builder guest from now on: VM_BAKE_BAKE_IN=builder, and the content terminals (disk mount, keys, pkg base, repo, boot, pkg install, rc, user, view, root lock, doas, ssh, pkg report, disk unmount) pinned to 'ssh -p VM_BAKE_SSH_PORT -i \<key\> VM_BAKE_BUILDER_USER@VM_BAKE_BUILDER_ADDRESS doas sh' -- one setintp line each, so the pins are seen

**image builder leave**
:   Bake on the host again: VM_BAKE_BAKE_IN=host, the content terminals' pins dropped (their profile defaults, sudo sh, apply) -- one unsetintp line each

**image builder start \<image\>**
:   Start the builder guest with the image's disk as its second disk: the builder guest has a record (guest make) and is not running; its configuration written with the disk, 'vm start', then wait until it answers ssh

**image builder stop**
:   Shut the builder guest down over ssh (doas shutdown -p now) and wait until its bhyve process is gone

**image lock drop**
:   Act terminal: remove the bake lock -- the last line of 'image seal', and the way out after a bake that died with the lock held

**image list**
:   List the image records (one line each): name, template, created, digest or 'open' while the bake is not closed

**image dump all**
:   Every image record as replay lines, one 'image dump record' per record, no records a comment -- the dump's witness of what was baked (template, created, digest); the images themselves never travel, 'image make' bakes them anew

**image record restore \<image\> \<template\> \<created\> \<digest\>**
:   A record from a dump, the witness of an image baked elsewhere or before: the name valid; then 'image record compare' -- no record of that name here: placed; the same record: a comment; one that differs: an error. The record stands for an image that is NOT here (its dir is this host's VM_BAKE_IMAGE_DIR/\<image\>, empty until baked): 'image drop \<image\>' lets it go, 'image make \<template\> \<image\>' bakes it anew and the digest here says what it was

**image make linux \<template\> \<version\>**
:   Bake a Linux image from the template under the version: the image is img:\<template\>:\<version\>, handed to 'image make linux from' -- a version is yours to choose (v1, v2, v20261107); two more spellings: the full name alone (image make linux img:\<template\>:\<version\>) and a name of its own (image make linux \<template\> \<version\> img:\<name\>:\<version\>)

**image firstboot \<image\>**
:   Step 2 of the Linux bake, the first boot: the image has a record; then the seed of the bake written (image seed write), the throwaway guest VM_BAKE_FIRSTBOOT configured with the image's disk and the seed, linked where vm-bhyve looks, started, its console read until the first boot reports its packages (image firstboot report: a missing package ends the bake with an error naming it), waited for until its bhyve process is gone (cloud-init powers the guest off when it is done), its link and configuration removed again -- the guest exists for this one boot

**image make openbsd \<template\> \<version\>**
:   Bake an OpenBSD image from the template under the version: the image is img:\<template\>:\<version\>, handed to 'image make openbsd from' -- the same three spellings as 'image make linux' (the full name alone, or a name of its own as third word)

**image install \<image\>**
:   Step 2 of the OpenBSD bake, the installation: the image has a record; then the response file (image response write) and the site set (image site write) rendered from the template and packed as site.iso (image site pack), the throwaway guest VM_BAKE_FIRSTBOOT configured with the image's disk and the site.iso (image firstboot conf), linked where vm-bhyve looks, run from the template's install ISO (guest install: the ISO rides along for this one run), its console typed into autoinstall(8) (image console drive), waited for until bhyve is gone (the installer reboots, the installed system adds the packages and powers off), its link and configuration removed again. The root acts (guest link write, guest install, image console drive, guest link drop) are pinned 'sudo sh'; sudo stamps its ticket when a command starts, so a console drive of ten minutes outlives the ticket and guest link drop asks for the PIN again (a bake on illyria failed there). One sudo for the whole batch instead: pin image_install to 'sudo -E sh -c "$VM_BAKE_BATCH_COMBINATOR_INTERPRETER"' (the engine runs a pin through eval, so the class default's name expands to its text, but a variable's text is split into words and its quotes stay letters -- the bare name broke the first one-sudo bake on illyria with 'Unterminated quoted string'; sh -c hands the text to a shell that parses it; -E keeps the environment vm-bake builds and is allowed because a sudoers ALL implies SETENV) and the acts that write the image's files (image_response_write, the five acts of image site write, image_site_files_place, image_site_pack, image_firstboot_conf_write, image_firstboot_conf_drop) to 'sudo -u \<user\> sh', which root runs without authentication -- one PIN at the start; the engine's traces and logs of that run are then root's

**image make alpine \<template\> \<version\>**
:   Bake an Alpine image from the template under the version: the image is img:\<template\>:\<version\>, handed to 'image make alpine from' -- the same three spellings as 'image make linux' (the full name alone, or a name of its own as third word)

## Dowry

A dowry is an object (a file or a whole directory) kept in the database
under a name: 'dowry add \<dowry\> \<source\>' copies it there, 'dowry list'
names what is kept, 'dowry drop' throws it out. A template hands a dowry
to its guests with 'template home copy idem\|overwrite \<template\> \<dowry\>
\<destination\>' -- 'idem' puts it only where it is missing (the guest
keeps what it has made of it), 'overwrite' replaces it at every start.
'guest start' places them before it hangs the overlays in.

**dowry add \<dowry\> \<source\>**
:   Keep an object in the database under a name: the name is a word, the source is there and readable; then the object copied into the database with its source and the date beside it. An existing dowry of that name is replaced, so this is also how a dowry is refreshed

**dowry drop \<dowry\>**
:   Throw a dowry out of the database: it is kept there; then the record removed. A template that still hands it out keeps its line -- 'guest start' then says the dowry is gone

**dowry list**
:   List the dowry records (one line each): name, size, kind, created, source

**dowry dump all**
:   Every dowry record as replay lines, one 'dowry dump record' per record, no records a comment -- the dump's witness of the dowry (name, source, created); the object itself travels in the export bundle, not in the dump

**dowry record restore \<dowry\> \<source\> \<created\>**
:   A dowry record from a dump, the witness of an object kept elsewhere or before: the name is valid; then 'dowry record compare' -- no record of that name here: placed (the object itself comes with the bundle, 'import place' puts it there); the same record: a comment; one that differs: an error

## Host keys

An ssh host key is a resource kept in the database under a name of its
own: 'hostkey create \<name\>' makes one, 'hostkey add \<name\> \<path\>'
takes an existing one in (a backup, a key from another host), 'hostkey
list' names them with their fingerprint and the guest that carries
them, 'hostkey drop' throws one out. A guest takes one with 'guest
hostkey use \<guest\> \<hostkey\>' -- at most one guest per key, so no two
guests ever answer with the same identity. 'guest make' is content with
a key named after the guest and makes it when it is missing.

**hostkey create \<name\>**
:   Make an ssh host key under a name: the name is a word and free; then the key made with ssh-keygen (ed25519, no passphrase) in the database. The name is the key's, not a guest's -- 'guest hostkey use' hands it to one

**hostkey add \<name\> \<path\>**
:   Take an existing ssh host key into the database under a name: the name is a word and free, the path is an ed25519 private key that is there and readable with its public half beside it; then both copied into the database. This is how a key from a backup or another host keeps its identity here

**hostkey drop \<name\>**
:   Throw an ssh host key out of the database: it is kept there and no guest carries it ('guest hostkey drop \<guest\>' lets go first); then the record removed. A guest built again afterwards answers with a new identity, so every known_hosts that remembered it has to forget it

**hostkey list**
:   List the ssh host keys of the database (one line each): name, fingerprint, created, and the guest that carries it (every guest record read here) or '-' for a free one

**hostkey dump all**
:   Every ssh host key record as replay lines, one 'hostkey dump record' per record, no records a comment -- the dump's witness of the keys (name, created); the keys themselves travel in the export bundle, not in the dump

**hostkey record restore \<name\> \<created\>**
:   An ssh host key record from a dump, the witness of a key kept elsewhere or before: the name is valid; then 'hostkey record compare' -- no record of that name here: placed (the key itself comes with the bundle, 'import place' puts it there); the same record: a comment; one that differs: an error

## Guests

A guest is a sealed image put to work: 'guest make \<image\> \<guest\>
\<address\>' clones the image's snapshot into VM_BAKE_GUEST_DIR/\<guest\>,
renders the vm-bhyve configuration (UEFI, cpu and memory from the
template, virtio disk and network on VM_BAKE_GUEST_SWITCH) and writes
hostname, address and resolver into the clone's rc.conf from the
host, because no one is root inside. The switch is created on the
bridge VM_BAKE_GUEST_BRIDGE when it is missing. 'guest start' and
'guest stop' wrap vm-bhyve; 'guest drop' destroys the clone.
A guest whose template says 'service files view' has a view: the ZFS
dataset VM_BAKE_VIEW_DIR/\<guest\> in the invoking user's home, which
the guest mounts over virtio-9p as its whole home. There is one home,
the host's; the guest writes its own things into its view, sees of the
rest what the template's home lines allow ('guest start' hangs them in
as nullfs overlays, ro or rw), and has its own clones of the host's
repositories ('guest repo add'), which the host fetches back. The view
survives the guest: 'guest drop' keeps it, 'guest view drop' removes it.

**guest make \<image\> \<guest\> \<address\>**
:   Make a guest from a sealed image: the image has a record and a digest, the guest name is a record name and free, the mirrors' directory VM_BAKE_REPO_VIEWS made under the invoking user's home when it is missing (guest repo tree ensure) and every home path of the template there; then the switch ensured, the record, the view of the host's home when the template says so (kept across rebuilds), the clone of @image, the configuration, the network written into the clone, the template's home paths seeded into the users' homes (a guest with a view takes them as overlays at 'guest start' instead), the ssh host key the guest carries installed (a resource of the database under a name of its own, made under the guest's name when the record binds none), the host's unbound told the name

**guest start \<guest\>**
:   Start the guest: it has a record, it is not running already (vm-bhyve's run.lock -- the check stands first, so a running guest costs neither a mount nor the sudo behind it), the mirrors' directory VM_BAKE_REPO_VIEWS made under the invoking user's home when it is missing (guest repo tree ensure -- the one home path the tool owns, so no hand makes it) and every home path of its template is there; then the dowry of its template placed in its view, the overlays of the template hung in (a guest without a view: a note), the report of what the records say about it written into that view, the fetched mark dropped (it is about to commit again), 'vm start', and 'guest repo ensure' -- the clones its record lists made on its disk once it answers ssh

**guest stop \<guest\>**
:   Stop the guest: it has a record; then 'guest repo hold' (its commits fetched into the host's repositories and the fetched mark written, while it still answers), 'vm stop' (ACPI shutdown), the wait until its bhyve process is gone, the vm instance released if one is left behind, and the overlays of its view let go

**guest drop \<guest\>**
:   Remove the guest: it has a record, is not running (vm-bhyve's run.lock) and its repositories are fetched (the mark of 'guest stop'; 'guest drop unfetched' gives them up); the overlays of its view let go, whatever still holds the clone on the host released (a stale md, a mount), its dataset destroyed (a running guest makes zfs refuse: guest stop first), the record removed with its hostkey binding, unbound told, what the host remembered of its ssh host key forgotten. The ssh host key itself stays in the database and is free again, so the guest built anew under that name takes it back and answers with the same identity; the view stays too -- a new image replaces the guest, not what it wrote ('guest view drop' removes that, 'hostkey drop' the key)

**guest drop unfetched \<guest\>**
:   'guest drop' without the fetched check: the guest's commits that the host never fetched are given up with its disk -- for a guest stopped by other means whose clones hold nothing worth a start and a stop

**guest log rotate ensure**
:   Act terminal (root): VM_BAKE_LOG_ROTATE_FILE written -- the newsyslog entries for the logs of EVERY guest, by shell pattern over VM_BAKE_GUEST_DIR (flag G), so a guest that comes later needs no entry of its own: \<guest\>/bhyve.log (what bhyve says, kept because every guest is configured with debug) and \<guest\>/vm-bhyve.log (what the runner says), root and the invoking user's group, 0640, VM_BAKE_LOG_ROTATE_KEEP generations of VM_BAKE_LOG_ROTATE_SIZE KB, gzipped, no process to signal. Written anew every time: the file belongs to vm-bake, its numbers come from the environment

**guest tag add \<guest\> \<key\> \<text\>**
:   Add a tag to the guest's own list (what belongs to this guest, not its template: owner, note, ...): the guest has a record, the key is a word; then 'guest tag append'. 'guest tag show' lists own and inherited tags, 'guest find' searches both

**guest tag drop \<guest\> \<key\> \<text\>**
:   Remove a tag from the guest's own list: the guest has a record, the line is listed; then 'guest tag remove'

**guest tag show \<guest\>**
:   The guest's own tags and the tags inherited from its image's template, each with its origin: the guest has a record; then 'guest tag table'

**guest find \<key\> \<pattern\>**
:   Display terminal: every guest whose tags, own or inherited from its image's template, hold the key with a text matching the pattern -- an extended regular expression, case-insensitive, searched in the text alone and not in the names around it ('.' for any text, '^8\.0$' for exactly that value): one line per hit, guest, image, origin, the tag -- answered from the records, no guest is started

**guest view tree ensure**
:   Act terminal (root, once per host): the datasets that carry the views -- beside the dataset that carries the invoking user's home, under its parent, the path of VM_BAKE_VIEW_DIR below that home as a dataset path (slash for slash, so the hierarchy reads like the path: \<parent\>/vm-bake/guest for ~/vm-bake/guest); the head of that path gets the mount point, everything below inherits it, and both are handed to the invoking user (the head 0755, the views' directory 0700). Every view 'guest view ensure' makes below it inherits the mount point too and needs no further right. An existing one is a note

**guest dowry place \<guest\>**
:   Put the dowry the image's template hands out into the guest's view, by its policy: 'guest dowry place idem' for the lines that only fill what is missing, then 'guest dowry place overwrite' for the lines that replace what is there. 'guest start' does it before it hangs the overlays in, so an overlay never hides a destination

**guest view drop \<guest\>**
:   Throw the guest's view away: the guest is not running (vm-bhyve's run.lock); then whatever is hung into the view let go and its dataset destroyed. 'guest drop' keeps the view, this removes it -- the dotfiles, the state of the guest's tools and its clones are gone

**guest repo add \<guest\> \<repo\>**
:   Give the guest a clone of one of the invoking user's repositories to commit in: the guest has a record and a view and is running, the path is plain and relative to the home; then the host's bare mirror of it under VM_BAKE_REPO_VIEWS made or refreshed (the template's home line hangs that directory read-only into every view, so the guest pulls from the mirror and can touch nothing of it), the clone made over ssh under VM_BAKE_REPO_LOCAL on the guest's own disk, where git can write its objects -- the view cannot take them, p9fs refuses to create a read-only file for writing -- and only then the repository recorded for the guest: a clone that fails (the view shows no mirror, no home line git/views) leaves no record behind, which 'guest stop' would otherwise try to hold. A second add of the same repository refreshes the mirror and leaves the clone alone

**guest repo fetch \<guest\> \<repo\>**
:   Fetch what the guest committed into the invoking user's own repository: the guest has a record and is running, the path is plain; then its branches fetched over ssh from the clone on the guest's disk into refs/remotes/\<guest\>/* of the host's repository, where 'git log \<guest\>/\<branch\>' reads them and 'git merge --ff-only \<guest\>/\<branch\>' takes them over -- the host signs, the guest never does; the batch ends in a comment that names both commands for the branch the host's repository has checked out (read at generation time), the continuation at hand

**guest repo pull \<guest\> \<repo\>**
:   Fetch and take over in one go: the fetch of 'guest repo fetch', then 'guest repo merge' fast-forwards the branch your repository has checked out onto the guest's -- what the fetch's closing comment asks you to paste, done by the tool

**guest repo drop \<guest\> \<repo\>**
:   Take the repository from the guest: it has a record and is running, the path is plain; then the clone removed from the guest's disk over ssh and the line taken from its record -- what the guest committed and the host has not fetched is gone with it. The mirror under VM_BAKE_REPO_VIEWS stays, the other guests read it

**guest repo ensure \<guest\>**
:   Every repository recorded for the guest has its clone on the guest's disk: the guest has a record; then, when the record lists any (read at generation time), 'guest repo wait' for its sshd and 'guest repo clone' for each -- a clone already there is left alone. 'guest start' ends with it, so a guest on a fresh image gets its clones back; a record without repositories is a comment

**guest repo hold \<guest\>**
:   Hold what the guest committed before it goes: the guest has a record; then, when it is running (vm-bhyve's run.lock, read at generation time), 'guest repo refs' for every recorded repository and 'guest fetched write' once all are in. 'guest stop' does it first, so 'guest drop' can trust the mark; a guest that is not running cannot be read and gets a comment, no mark

**guest repo show \<guest\>**
:   Act terminal (the invoking user, over ssh into the guest): the repositories recorded for the guest, one line each, then the clones on its disk under VM_BAKE_REPO_LOCAL with the branch their HEAD names (the file read, no git run in the guest's clone)

**guest hostkey use \<guest\> \<hostkey\>**
:   Hand an ssh host key of the database to a guest: the guest has a record, the key is kept, and no other guest carries it (a key answers for one guest only); then the binding written into the guest record. The key reaches the guest's /etc/ssh at the next 'guest make' -- a guest that is already built has to be built again to answer with it

**guest hostkey drop \<guest\>**
:   Let go of the ssh host key of a guest: it has a record; then the binding removed from it. The key itself stays in the database and is free for another guest -- 'hostkey drop' throws it out

**guest show \<guest\>**
:   Everything the records say about one guest, as comment lines: its own record (image, address, created, the name and fingerprint of the ssh host key it carries), the template behind its image with the resolved chain and resources, whether it has a view and where, and every list family resolved over the chain with its origin -- the SOLL of this guest, against which it can be checked from inside. 'guest report' is the same text, written into the guest's view

**guest report \<guest\>**
:   Write what 'guest show' says into the guest's own view, as .vm-bake/GUEST.txt beside the records it reads, so the guest can hold its SOLL against what it finds: the guest has a record; then the text rendered into .tmp/report.\<guest\> of the database and put in place by 'guest report place'. A guest without a view has nowhere to put it and gets a comment

**guest list**
:   List the guest records (one line each): name, image, address, created

**guest dump all**
:   Every guest record as replay lines, one 'guest dump record' per record, no records a comment -- the dump's witness of the guests (image, address, created, own tags); the clone never travels, 'guest make' makes it anew, the host key comes with the bundle

**guest record restore \<guest\> \<image\> \<address\> \<created\>**
:   A record from a dump, the witness of a guest made elsewhere or before: the name and the address valid; then 'guest record compare' -- no record of that name here: placed; the same record: a comment; one that differs: an error. The record stands for a clone that is NOT here: 'guest drop \<guest\>' lets it go, 'guest make \<image\> \<guest\> \<address\>' makes it anew; a host key placed by import keeps its identity

## Export and import

'export \<dump\> \<bundle\>' writes the two artifacts: the dump (what
'dump' prints: the environment the replay needs, every template, the
image and guest records as witnesses, every override) to a path you
commit, and the bundle (a tar of export/tree in the database: the guest
host keys, the package files of every template's pkgfile list, the home
seeds of every home list, each hashed in a MANIFEST) to a store of your
own. The seal line at the end of the dump names the bundle by sha256
and size. 'import \<dump\> \<bundle\>' verifies the seal, unpacks into
\<root\>/incoming, checks the MANIFEST, refuses a file that differs from
one already here, places the missing ones and replays the dump. Nothing
is signed or encrypted here: the commit that carries the dump is.

**export \<dump\> \<bundle\>**
:   Write the pair: the DUMP to \<dump\> (a path of your choosing, absolute; commit it), the BUNDLE to \<bundle\> (absolute; keep it where private keys may lie). Both paths absolute, the archiver set; then the dump written, the collection, the tree, the MANIFEST, the bundle packed, the dump sealed with the bundle's hash -- an earlier dump at that path is overwritten, its seal with it

**manifest \<collection\> \<manifest\>**
:   Hash every entry of a collection into a manifest (LC_ALL=C-sorted 'path sha256=hash' lines, a symlink as 'path symlink=target', the collection itself listed last): the collection is readable, the manifest is named MANIFEST (import looks for it by name in the unpacked bundle) and lies in the tree the paths are relative to, every entry is hashable; then 'manifest write'

**bundle \<tree\> \<bundle\>**
:   Pack the tree with VM_BAKE_ARCHIVER into \<bundle\>: the tree's collection readable, the archiver set, the bundle path absolute, the MANIFEST in the tree (a bundle without its tamper detection is not produced); then 'bundle pack'

**seal \<dump\> \<bundle\>**
:   Append the bundle's sha256 and size to the dump as its seal line ('# Bundle: sha256=... bytes=...'): both files readable, the dump not yet sealed (a dump names ONE bundle; export again for a new pair); then 'seal write'

**seal verify \<dump\> \<bundle\>**
:   The dump's seal line names THIS bundle (sha256 and size): both files readable, the dump sealed, the seal matching -- a mismatch fails the command before anything is unpacked

**import \<dump\> \<bundle\>**
:   Replay an exported pair into this database (bootstrap one first: the dump's '# Profile:' header names the profile), checked end to end before a byte lands: the seal (this bundle is the one the dump names), incoming cleared, the bundle unpacked into \<root\>/incoming/\<bundle name\>, its MANIFEST against the unpacked tree, every file of the collection absent here or identical ('import check clear'), the missing ones placed, the dump replayed. Into an EMPTY database by intent: a template already here is never re-minted, a record that differs is refused, a file that differs from the bundle's is refused before anything lands

**extract \<bundle\> \<destination\>**
:   Unpack a bundle into a scratch directory with VM_BAKE_EXTRACTOR: the bundle readable, the extractor set, the destination absolute and empty (or not yet there); then 'extract unpack'

**manifest match \<manifest\> \<tree\>**
:   Does the tree match the manifest? The manifest is readable and lists entries, the tree exists; then 'manifest tree matches' -- every listed file hashes identically, every listed symlink points where recorded (MISSING, CHANGED, RETARGETED fail). Files present but unlisted are not findings: the tree is an extraction directory

## Sessions

A session is a client script, printed by 'session create', that the
user keeps and runs: 'ssh' opens a shell in the guest or runs one
program there (with a pseudo-terminal), 'xterm' does the same in a
window of its own for a launcher without a terminal, and both take the
word 'screen' after the program to put the ssh under screen -dR on the
host (session \<program\>@\<guest\>: closed windows leave it detached,
'screen -r' or the script again take it back); 'x' opens a Xephyr
compartment on the host's display
and runs one program of the guest inside it over ssh -X, so the
program's windows never touch the host's own X server. The guest must
list the service 'display x' in its template, which gives it xauth and
X11Forwarding at bake time. The compartment takes VM_BAKE_XEPHYR_SCREEN
and VM_BAKE_XEPHYR_DPI; its display number is the first free one from
VM_BAKE_XEPHYR_FIRST, read at generation time.

**session create ssh \<guest\> [\<program\>] [\<mux\>]**
:   The terminal session: the guest has a record; then the script that opens ssh to \<guest\>.VM_BAKE_GUEST_DOMAIN on VM_BAKE_SSH_PORT with the host key's private counterpart -- a shell in the guest, or with \<program\> that program under a pseudo-terminal (ssh -t: claude or vi need one, and ssh grants none when handed a command), and with the word screen as \<mux\> the ssh under 'screen -dR -S \<program\>@\<guest\>' on the host (named after the last command of the program line and the target of a leading cd, so 'cd git/Infrastruktur && exec claude' is claude@\<guest\>:Infrastruktur -- one session per guest and repository): an existing session of that name is taken over instead of a second one started, a terminal closed by mistake leaves it detached ('screen -r', or the script again), and 'zombie kr' in ~/.screenrc keeps a window whose ssh failed, r retries. Printed, not run: keep it where you like, ~/bin say

**session create xterm \<guest\> [\<program\>] [\<mux\>]**
:   The window session, for a launcher without a terminal (a window manager's menu): the guest has a record; then the script that opens an xterm of its own, titled after the guest or \<program\>@\<guest\>, with the ssh of 'session create ssh' with the same arguments as its command -- a shell, a program under ssh -t, or with the word screen as \<mux\> the program under 'screen -dR -S \<program\>@\<guest\>'. The window closes with its command; without screen that means a failed ssh vanishes before its message is read, with screen the session is the same one 'session create ssh \<guest\> \<program\> screen' makes: one script in ~/bin for a terminal, one in the launcher for a window, and the program wanders between them

**session create x \<guest\> \<program\>**
:   The compartment session: the guest has a record and its template lists the service 'display x'; the first free display number from VM_BAKE_XEPHYR_FIRST is read at generation time; then the script that starts Xephyr on that display and runs the program in the guest over ssh -X into it (printed, not run)

# ENVIRONMENT

All configuration lives in `VM_BAKE_*` variables, layered as `.env/local` (override, written by `setenv`), `.env/default` (the installed profile) and the shipped templates. Interpreter pins `VM_BAKE_INTERPRETER_<function>` decide per function whether emitted shell is displayed or executed: arity-specific before arity-agnostic before the class default (`VM_BAKE_TERMINAL_INTERPRETER`, default `cat`). Every variable answers `vm-bake help env <VAR>`.

**VM_BAKE_ARCHIVER**
:   The packing template for bundle: $a is the archive, $b the base directory (export/tree), the file list arrives on stdin as the collection wrote it. Byte-stable by construction: no ownership, no gzip timestamp (-n), the member order is the collection order. Alternative: (cd "$b" && zip -q -X "$a" -@)

**VM_BAKE_BAKE_IN**
:   Where image base, burn and close act: host (the content terminals pinned to sudo sh, the disk attached as md on the host) or builder (pinned to ssh into the builder guest, which gets the disk as its second disk). pkgbase cannot be installed with pkg -r on a host at securelevel 1 or higher, so a release base needs the builder. Set by image builder use / image builder leave.

**VM_BAKE_BUILDER**
:   Name of the builder guest (guest make \<image\> bake \<address\>): a FreeBSD guest at securelevel -1 that mounts an image's disk under VM_BAKE_IMAGE_DIR/\<image\>/mnt and runs the content terminals there. Its ssh host key is remembered in .tmp/known_hosts.\<name\>.

**VM_BAKE_BUILDER_ADDRESS**
:   Address of the builder guest (without prefix), the one guest make gave it; ssh goes there on VM_BAKE_SSH_PORT.

**VM_BAKE_BUILDER_USER**
:   User ssh logs in as in the builder; the builder's template lists it and doas, so it escalates without a password (image doas write).

**VM_BAKE_CONSOLE**
:   How vm-bhyve offers the guests' serial console, the word vm-bhyve's console= in VM_BAKE_VM_DIR/.config/system.conf says: nmdm (its default: /dev/nmdm-\<guest\>.1B, what 'vm console' attaches to) or tmux (a tmux session per guest, run by root). An autoinstall bake types into that console (image console drive) and must know which.

**VM_BAKE_DIR**
:   vm-bake's own dataset and directory: the datasets image/ (the sealed images) and guest/ (the clones), and the directory distfiles/ for what comes from outside, by kind: image/ (VM images), pkg/ (package files), later deb/, rpm/, port/. Made once by root and delegated to the invoking user: zfs create \<pool\>/.../vm-bake, chown \<user\> on its mount point, zfs allow \<user\> create,mount,snapshot,clone,destroy,readonly on it, sysctl vfs.usermount=1 -- then every ZFS act of vm-bake runs without root. vm-bhyve keeps its own directory (VM_BAKE_VM_DIR).

**VM_BAKE_DNS_FILE**
:   The unbound include file vm-bake owns: rendered from the guest records by guest dns write (guest make, guest drop), one local-data and one local-data-ptr per guest, then local_unbound reloaded. local_unbound includes conf.d/*.conf.

**VM_BAKE_EXTRACTOR**
:   The unpacking template for extract: $a is the archive, $d the destination. Alternative: unzip -q "$a" -d "$d"

**VM_BAKE_FIRSTBOOT**
:   Name of the throwaway guest a Linux bake boots once (image firstboot): a vm-bhyve configuration under VM_BAKE_GUEST_DIR/\<name\> that points at the image's disk0.img and seed.iso, linked into VM_BAKE_VM_DIR for the boot and removed after it. No record, no dataset, no clone: the guest exists for the minutes cloud-init needs.

**VM_BAKE_FIRSTBOOT_ADDRESS**
:   Address (with prefix length) of the throwaway guest VM_BAKE_FIRSTBOOT during a Linux bake: the seed's network-config sets it static on the MAC 58:9c:fc:\<octets 2-4\>, gateway and nameserver VM_BAKE_GUEST_GATEWAY -- the switch has no DHCP, and apt needs the way out during the first boot. Free in the guests' network, never a guest's own address.

**VM_BAKE_GUEST_BRIDGE**
:   The existing bridge interface the switch attaches to; the host's pf rules and its address on it (VM_BAKE_GUEST_GATEWAY) are the guests' network policy.

**VM_BAKE_GUEST_DIR**
:   Dataset of vm-bake's guests: a guest is the clone VM_BAKE_GUEST_DIR/\<guest\> with disk0.img and \<guest\>.conf inside, linked into vm-bhyve's vm_dir. Created by image tree ensure.

**VM_BAKE_GUEST_DOMAIN**
:   The domain the guests' names live in: a guest \<name\> is \<name\>.\<domain\> for the host and for every guest (their resolver is the host).

**VM_BAKE_GUEST_GATEWAY**
:   The host's address on the bridge: default router and resolver of every guest (guest network write).

**VM_BAKE_GUEST_SWITCH**
:   Name of the vm-bhyve switch the guests hang on; created as a manual switch on VM_BAKE_GUEST_BRIDGE when missing (guest switch ensure).

**VM_BAKE_HOST_KEY**
:   Public key file written into authorized_keys of every user of an image (image user make); a leading ~/ is the invoking user's home. The guests know no password, this key is the only way in. Point it at a key made for the guests (setenv VM_BAKE_HOST_KEY \<path\>) -- a FIDO2 key here means PIN and touch at every login.

**VM_BAKE_IMAGE_CACHE**
:   Directory the FreeBSD VM images of base kind image are fetched into (image fetch), kept across bakes, the invoking user's, made by image tree ensure. Lives under VM_BAKE_DIR/distfiles with the other kinds of files that come from outside (pkg; deb, rpm, port as their families arrive).

**VM_BAKE_IMAGE_DIR**
:   Dataset of the images: VM_BAKE_IMAGE_DIR/\<image\> is the image's own dataset (zfs create under it), holding disk0.img and digest, and the mount point mnt while it bakes. Created by image tree ensure.

**VM_BAKE_INCLUDES**
:   Modules preloaded at startup (engine.sh is always loaded first)

**VM_BAKE_INTERPRETER_dump_env_epilogue**
:   Interpreter for `dump env epilogue` -- dump TEXT

**VM_BAKE_INTERPRETER_dump_env_prologue**
:   Interpreter for `dump env prologue` -- dump TEXT

**VM_BAKE_INTERPRETER_environment_cache_off**
:   Interpreter for `environment cache off` -- removes the cache file

**VM_BAKE_INTERPRETER_environment_cache_status**
:   Interpreter for `environment cache status` -- one report line

**VM_BAKE_INTERPRETER_help_manual_commands**
:   Interpreter for `help manual commands` -- one part of the manual as TEXT

**VM_BAKE_INTERPRETER_help_manual_environment**
:   Interpreter for `help manual environment` -- one part of the manual as TEXT

**VM_BAKE_INTERPRETER_help_manual_title**
:   Interpreter for `help manual title` -- one part of the manual as TEXT

**VM_BAKE_LOG_ROTATE_FILE**
:   The newsyslog include file vm-bake owns (guest log rotate ensure writes it): the rotation of every guest s logs, by shell pattern over VM_BAKE_GUEST_DIR, so a guest that comes later needs no entry. /etc/newsyslog.conf reads this directory by default. The file belongs to vm-bake and is written anew at every guest make -- change the numbers through VM_BAKE_LOG_ROTATE_KEEP and VM_BAKE_LOG_ROTATE_SIZE, not by hand.

**VM_BAKE_LOG_ROTATE_KEEP**
:   How many rotated generations of a guest log newsyslog keeps (guest log rotate ensure). Seven is a week of boots at one rotation a day; the gzipped generations of a quiet guest cost kilobytes.

**VM_BAKE_LOG_ROTATE_SIZE**
:   The size in KB at which newsyslog rotates a guest log (guest log rotate ensure). A guest that says nothing never reaches it; one that repeats a bhyve message (the ps2 mouse line, say) rotates instead of growing without end.

**VM_BAKE_PKG_DIR**
:   Directory of package files a template may list with template pkgfile add: .pkg files of the host's ABI you put there yourself (a package another host fetched from the signed repository, a package you built), the invoking user's, made by image tree ensure. The bake stages them into the image and installs them with pkg add; their dependencies come from the repositories.

**VM_BAKE_PORTS_BRANCH**
:   Branch of the ports tree the builder clones for image port build: main matches the repository branch latest, a quarter (2026Q4) matches quarterly; keep it in step with the host's repository configuration, the packages the ports pull as dependencies come from there.

**VM_BAKE_REPO_LOCAL**
:   The clones' directory under the guest's home: the one place in the view that is NOT the view but the guest's own disk -- the image hangs /var/git there (image view write, a nullfs line in fstab), 'guest view mount' makes the mount point, and 'guest repo add' clones into it over ssh. git writes its objects there, which p9fs cannot take (it refuses to create a read-only file for writing). What lies there goes with the disk: 'guest stop' fetches it first (guest repo hold), 'guest drop' refuses without that mark, and 'guest start' clones what the record lists again (guest repo ensure). A path relative to the home.

**VM_BAKE_REPO_VIEWS**
:   The mirrors' directory under the home, the same path on the host and in every view: 'guest repo add' keeps a bare mirror of each repository a guest gets there (VM_BAKE_REPO_VIEWS/\<name\>, \<name\> the last element of the repository's path), and the template's home line 'template home add \<template\> git/views' hangs it read-only into the views -- the guest clones and pulls from the mirrors and can change nothing in them, not a hook, not a config. A path relative to the home; the host's directory must exist before 'guest start' (guest check homes), 'guest repo add' makes it.

**VM_BAKE_SSH_PORT**
:   Port sshd listens on in every guest baked from here (image ssh write). 2222 because the host's pf passes TCP from the host into the guest network only on its service ports (br0_services in /etc/pf.conf), and 22 is not among them; change it together with pf.

**VM_BAKE_VIEW_DIR**
:   The guests' views of the invoking user's home: VM_BAKE_VIEW_DIR/\<guest\> is one ZFS dataset per guest, which the guest mounts over virtio-9p as the whole home of its host-uid user when its template says 'service files view'. A leading ~/ is the invoking user's home. 'guest view tree ensure' makes the datasets that carry the views, once per host: beside the dataset that carries the home, under its parent, with this path below the home as the dataset path, slash for slash -- \<parent\>/vm-bake/guest for ~/vm-bake/guest; the head of that path carries the mount point, everything below inherits it, and 'guest view ensure' then creates \<parent\>/vm-bake/guest/\<guest\>. A view is a dataset of its own and therefore NOT in the snapshots of the home's dataset: a backup has to take the parent recursively. What the guest writes there (its dotfiles, the state of its tools) lies in the home -- its clones do not, they lie on its disk under VM_BAKE_REPO_LOCAL, because git cannot write its objects on p9fs; what it may see of the rest of the home is the template's home list, hung into the view by 'guest start' as nullfs overlays and let go by 'guest stop'.

**VM_BAKE_VIEW_SLOT**
:   PCI slot of the virtio-9p device a guest with a view carries: 'guest conf write' writes bhyve_options="-s \<slot\>,virtio-9p,home=VM_BAKE_VIEW_DIR/\<guest\>" and vm-bhyve hands that option to bhyve raw. High, so it stays clear of the slots vm-bhyve assigns to disks and interfaces itself. The share is called home on both sides: in this option and in the fstab line of the image (image view write).

**VM_BAKE_VM_DIR**
:   vm-bhyve's vm_dir (rc.conf: vm_dir=zfs:\<dataset\>): its own guests live there; a guest of vm-bake appears there as the link \<name\> -\> VM_BAKE_GUEST_DIR/\<name\> (guest link write), so vm-bhyve finds it and the listing shows who manages what.

**VM_BAKE_XCURSOR_SIZE**
:   Cursor size in a Xephyr compartment, in pixels (Xcursor.size in the compartment's resources, read by GTK and Electron programs of the guest); 48 suits a 240 dpi compartment.

**VM_BAKE_XCURSOR_THEME**
:   Cursor theme the compartment's X server draws (XCURSOR_THEME for Xephyr; themes from the host's xcursor-themes: redglass, whiteglass, handhelds). The guest's programs name their theme through the template's env list (template env add \<t\> XCURSOR_THEME redglass) and the package xcursor-themes in the guest.

**VM_BAKE_XEPHYR_DPI**
:   DPI a Xephyr compartment reports to the guest's program (session create x); raise it for a HiDPI host display.

**VM_BAKE_XEPHYR_FIRST**
:   Lowest X display number a compartment may take; session create x reads /tmp/.X11-unix at generation time and takes the first free number from here.

**VM_BAKE_XEPHYR_SCREEN**
:   Size of a Xephyr compartment (session create x): WIDTHxHEIGHT; the compartment is resizeable afterwards.

**VM_BAKE_XEPHYR_WM**
:   Window manager started inside a Xephyr compartment (session create x), on the host, so the guest's program gets a manager that gives every window the whole compartment; ratpoison does exactly that (host package ratpoison). The word none: no window manager, programs keep their start size.

# FILES

`~/.vm-bake/db`
:   the active database (a symlink to `~/.vm-bake/<name>`)

`.env/local`, `.env/default`
:   the layered variable store: overrides (setenv), the installed profile

`template/<name>`, `.templates/<id>`
:   the template records: the name symlink, the record with its leaves

`.tmp`, `.log`
:   scratch of the batch runner, traces and logs (retention in days)

`~/vm-bake/guest/<guest>`
:   the view: one dataset per guest, the home it sees (VM_BAKE_VIEW_DIR)

`dowry/<name>/object`
:   the dowry: an object a template hands to the homes of its guests

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

# SEE ALSO

vm(8) of vm-bhyve; bhyve(8); zfs(8).

# AUTHORS

Dr. Johannes Brügmann

