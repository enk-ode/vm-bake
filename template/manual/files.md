# FILES

`~/.vm-bake/db`
:   the active database (a symlink to `~/.vm-bake/<name>`)

`.env/local`, `.env/default`
:   the layered variable store: overrides (setenv), the installed profile

`template/<name>`, `.templates/<id>`
:   the template records: the name symlink, the record with its leaves

`.tmp`, `.log`
:   scratch of the batch runner, traces and logs (retention in days)
