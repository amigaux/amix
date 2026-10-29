# kernel/drivers

Hardware drivers, one directory each. Each driver is built as a loadable
module and ships in the kernel-space catalog.

Drivers kept here as source, with the package recipe beside the code:

| Directory | Hardware |
|-----------|----------|
| `a4091/` | A4091 Zorro III SCSI (NCR 53C710), with the A4000T onboard 53C710 variant (`a4kt710`) |
| `z3660scsi/` | Z3660 accelerator SCSI |
| `z3660eth/` | Z3660 accelerator ethernet |

Drivers that other developers lead stay forks of their own repositories. Their
directory holds only a README and a pin file, `<name>/<name>.pin`, naming the
fork and the exact commit the build uses:

| Directory | Hardware | Upstream |
|-----------|----------|----------|
| `z3660rtg/` | Z3660 accelerator RTG graphics | Ignacio Soriano's zz9000-amix |
| `paula/` | Paula audio | Ignacio Soriano's paula-amix |
| `gayle-ide/` | A4000 Gayle IDE | Emre Bastuz's amix-gayle-ide |

A pin file is one line, `<git URL> <full commit hash>`; the build fetches that
exact commit.

Each source driver moves in with its own history, and a pinned one can move in
later with its history too; until then its directory does not exist.
