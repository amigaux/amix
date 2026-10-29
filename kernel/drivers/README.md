# kernel/drivers

Hardware drivers, one directory each. Each directory holds the driver's
source and its package recipe side by side; the driver is built as a loadable
module and ships in the kernel-space catalog.

| Directory | Hardware |
|-----------|----------|
| `a4091/` | A4091 Zorro III SCSI (NCR 53C710), with the A4000T onboard 53C710 variant (`a4kt710`) |
| `z3660scsi/` | Z3660 accelerator SCSI |
| `z3660eth/` | Z3660 accelerator ethernet |
| `z3660rtg/` | Z3660 accelerator RTG graphics |
| `paula/` | Paula audio |
| `gayle-ide/` | A4000 Gayle IDE |

Each driver moves in with its own history; until then its directory does not exist.
