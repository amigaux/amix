# kernel/drivers

Hardware drivers, one directory each. Each driver is built as a loadable
module and ships in the kernel-space catalog.

Drivers kept here as source, with the package recipe beside the code:

| Directory | Hardware |
|-----------|----------|
| `a4091/` | A4091 Zorro III SCSI (NCR 53C710), with the A4000T onboard 53C710 variant (`a4kt710`) |
| `z3660scsi/` | Z3660 accelerator SCSI |
| `z3660eth/` | Z3660 accelerator ethernet |

Drivers that other developers started are kept as our own forks in the
amigaux organisation. We fix them there, the build takes them by pin, and
changes go back to the original author's repository as pull requests when we
choose to. Their directory holds only a README and a pin file,
`<name>/<name>.pin`, naming our fork and the exact commit the build uses:

| Directory | What | Our fork | Started from |
|-----------|------|----------|--------------|
| `cdfs/` | CD-ROM filesystem, as a module | amigaux/amix-cdfs | Stefan Reinauer's ODFileSystem |
| `gayle-ide/` | A4000 Gayle IDE | amigaux/amix-gayle-ide | Emre Bastuz's amix-gayle-ide |
| `paula/` | Paula audio | amigaux/amix-paula | Ignacio Soriano's paula-amix |
| `z3660rtg/` | Z3660 accelerator RTG graphics | amigaux/amix-z3660rtg | Ignacio Soriano's zz9000-amix |

A pin file is one line, `<git URL> <full commit hash>`. The URL is always our
fork's, never the upstream's, and the build fetches that exact commit.

Each source driver moves in with its own history. A pinned one can move in
later with its history too; until then its directory holds only its README
and its pin.
