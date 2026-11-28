# ugate: the user-path release gate

A release candidate passes this gate when released, installed systems take it with the commands their users
type, and come up working. ugate runs that test in the emulator: one row per starting system, in parallel.

For each row it:
1. serves the candidate repository (a `make dist` `release/<ver>` tree, read-only) to the boxes;
2. boots a copy of the row's starting disk;
3. runs the row's commands at a root prompt, exactly as written;
4. power-cycles, boots again and runs the row's session check (a CDE login, say);
5. reports each command's exit status and output, the kernel on each boot, `pkgchk -n` before and after, and the
   bus errors.

Nothing on the box is prepared by hand: no package upgraded first, no catalog edited, no file laid. A gate that
prepares its boxes can pass a candidate its users cannot install. A missing dependency floor, for one, is hidden
by a hand-upgraded package. The only changes ugate makes are:
- `/etc/apkg.conf`'s `repo=` line points at the candidate for the commands, and is put back after them;
- each slot's copy of the disk claims that slot's network address.

## Running it for a release candidate

```
python3 tools/ugate/ugate.py run --conf ~/ugate.conf \
    --tree <dist>/release/1.1 --rows tools/ugate/rows/1.1.3.rows --out <scratch>/ugate-1.1.3
```

- **`--conf`** is this host's emulator set-up: see `ugate.conf.example`. It names:
  - the row runner (kerntools' `rig-run`), the slots, the address the boxes reach the host on;
  - the starting disks, the session check.
  
  Keep it outside the repository.
- **`--tree`** is the candidate. It is served as it is; nothing is written inside it.
- **`--rows`** names the rows. **`--out`** must be a new or empty directory; `--only id,id` runs some rows.
- **The result:** `OUT/report.md`, a table and then each row's commands with what apkg printed. `OUT/report.tsv`
  has one line per row. Exit 0 means every row passed; 1 means a row failed, named on stderr and in the report.
- **`ugate.py check`** prints the plan and checks the conf, disks and tree without running anything.
- **`ugate.py judge --rows .. --out ..`** judges a finished run again.

A row passes when all of these hold:
- every command exits as the row expects (0, or `=N`);
- the box script finished;
- `pkgchk -n` shows no error it did not show before;
- there was no bus error on any boot;
- the session check passed;
- the runner raised no reason other than those in `UGATE_IGNORE_CHECKS`. The default is `display-rtg`, the RTG
  frame still on screen at halt, which the emulator always reports on an X row.

The disk copies are deleted when their row ends (`--keep-disks` keeps them); the evidence stays under `OUT/rows/`.

## The session check

The conf's `UGATE_SESSION_HOOK` names the session check, which comes from outside this directory. Keep it an
unchanged copy of its source, and set everything a gate needs through its environment in that one conf line:
- **It installs nothing.** A check that installs a missing session is a hand-prepared box, and a missing
  dependency floor goes unseen. A row whose session is not installed must fail at once.
- **The source commit goes in a comment beside the conf line.**
- **To refresh it:**
  1. copy the tools whole at the new commit (`git archive`);
  2. compare each file's sha256 with the source's list;
  3. carry the conf line's environment over, and run every rows file once;
  4. run one row the check must fail: a session with one of its programs broken on purpose, in a rows file of its
     own outside `rows/` (it is not a user path). A check that never fails proves nothing.

  The copy is not patched: a change the gate needs goes to the source first.

## Adding a row

A rows file has one block per row:

```
row <id> <line> <disk> [session=<name>] [boots=<n>]
	apkg update
	=5 apkg install cde
```

- **`<line>`** is `k30` or `k46`.
- **`<disk>`** is a starting disk, `$UGATE_DISKS/<disk>.hdf`.
  - It must be a released image or install as a user has it: installed, first-booted, nothing else.
  - A new starting disk is made from released media, never by hand from an older disk.
- **The commands** are indented, one per line, run in order with `sh -c` after `/etc/profile`. Write each exactly
  as a user types it. `=N` marks a command expected to exit N: an old apkg refusing a catalog it cannot read is
  part of the path too.
- **`session=<name>`** runs the session check on the second boot. **`boots=<n>`** is the boots per row, default 2.
  The second boot is the power cycle a kernel or module upgrade asks for.

Keep one rows file per release (`rows/<ver>.rows`) and say at its top why each row exists.

## The pieces

| file | what it does |
|---|---|
| `ugate.py` | the command: plan, serve, slots and disk copies, the runner per row, the judge and the report |
| `ugate-serve.py` | serves one tree read-only at `/<ver>/` (GET/HEAD; nothing outside the tree) |
| `ugate-hook.sh` | the runner's per-boot host hook: kernel per boot, the box script on boot 1, the session check after |
| `box/ugate-box.sh` | on the box: state before, the commands, state after (Bourne shell of 1992) |
| `rows/*.rows` | the rows of each release |
| `ugate.conf.example` | what the host's conf holds |

`python3 ugate.py --selftest` and `python3 ugate-serve.py --selftest` test the parser, the judge and the server
on the host. `tools/test-all.sh` runs them.
