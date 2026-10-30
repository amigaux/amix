# altroot-repro — the `pkgadd -R` crash, root-caused on the box

Companion to `../host-altroot/` (which established the crash is host-
**un**reproducible) and to `AMIX-PORT.md` open follow-up **item 0**.
This directory holds the **box-side** harnesses that reproduced the
failure on metal, localized it to a single function, and root-caused it.

## Verdict (2026-07-20)

`pkgadd -R <altroot>` on Amix crashes because of a **toolchain
codegen defect**, not a pkgtools source bug:

> `libpkg/nhash.c` `HASH()` does `return (hv % hsz)`.  gcc 2.7.2.3
> emits the correct SGS remainder-divide `tdivs.l 12(%fp),%d2:%d1`
> (remainder→d2, quotient→d1) followed by `mov.l %d2,%d0`.  GNU as
> 2.8.1 **mis-assembles it, dropping the remainder register**: the
> object holds `divs.l 12(%fp),%d1` (quotient only), so the function
> returns the stale/garbage `%d2`.  `HASH` therefore returns a value
> unrelated to the key — often **negative** — and `add_cache()`
> indexes `cp->bp[negative]`, a wild `Bucket *` outside the bucket
> array, then stores through it → SIGSEGV.

This is the **third** gcc-2.7.2.3 / binutils-2.8.1 anomaly on this
target, after the `.swbeg` switch-dispatch bug and the `fcmp`/reg-reg
float bugs (see `AMIX-PORT.md`).  It is opt-level-independent: `%` is
wrong at both `-O0` and `-O`; `/` is wrong at `-O0` and correct at
`-O`.  Forcing `nhash.c`/`ncgrpw.c`/`verify.c` to `-O0` (MERGPATH_OPT)
was a mis-diagnosis — it never could fix a defect that lives in the
assembler, not the optimizer.

The v15–v17 focus on `clgrnam`/`dup_gr_ent` was chasing the wrong
function: the crash reproduces on an **empty** alt-root (no
`<root>/etc/group`), where `clgrnam()` returns NULL immediately and is
never entered.  The real path is `averify → cgrnam → (cache miss,
resolve via getgrnam) → add_cache → HASH`.

## The end-to-end proof (`mod_prog.c`)

Cross-compiled with `m68k-cbm-sysv4-gcc`, run on the box:

```
-O0:  351 % 151 = -2147408448   (expect 49)     100 % 7 = -2147408448 (2)
      351 / 151 = 351           (expect 2)
-O :  351 % 151 = 53            (expect 49)      100 % 7 = 28           (2)
      351 / 151 = 2             (correct)
```

`adb mod_prog_O0` / `adb mod_prog_O` on `mymod` show `divs.l …,%d1`
(single register) where `gcc.real -S` emitted `tdivs.l …,%d2:%d1` /
`…,%d0:%d1`.  The remainder register is gone.

## Task-0: what the failing `-R` target contained

`task0a.sh` (empty alt-root battery, `<root>` has **no** etc/group or
etc/passwd — only the dirs pkginstall itself creates):

| config | rc | out bytes | core |
|---|---|---|---|
| plain | 1 | 0 | 1 MB dropped at `<root>/var/sadm/install/core` |
| `DS_DEBUG=1` | 0 | 14266 | none |
| `DS_DEBUG=0` | 0 | 14266 | none (presence check, not value) |
| `ZZQQ=1` (unrelated env) | 1 | 0 | 1 MB |
| no `-R` (install to `/`) | 0 | 217 | — |

`ZZQQ` (a same-shape unrelated variable) does **not** suppress, so the
suppression is the DS_DEBUG instrumentation *code path executing*, not
the size/layout of the environment block.  The "silent, no core"
earlier report was wrong: the core is dropped inside the alt-root at
`<root>/var/sadm/install/core` (pkginstall's cwd), not in `/tmp`.
A **seeded** alt-root (etc/group+passwd present) crashes identically.

## Task-1: which instrumentation region suppresses it (`rtest5.sh`)

Apply `per-region-dsdebug.patch` (splits the single `getenv("DS_DEBUG")`
gate into per-region env vars `DBG_DS/ESYS/MAIN/MNT/LOCK/MERG/CGR`, all
still lit by `DS_DEBUG`; a lazy `dsreg()` caches the env before
pkginstall's `environ=NULL` reset), rebuild `build-amix.sh`, deploy the
**unstripped** `pkgcmds/{pkginstall,pkgadd}/*` (adb needs symbols), then
run `rtest5.sh` (4 runs each):

| config | rc ×4 | suppresses? |
|---|---|---|
| plain | 1 | — (baseline crash) |
| `DS_DEBUG` (all) | 0 | yes |
| `DBG_MAIN` | 1 | no |
| `DBG_MNT` | 1 | no |
| `DBG_LOCK` | 1 | no |
| `DBG_MERG` | 1 | no |
| `DBG_ESYS` | 1 | no |
| **`DBG_CGR`** | **0** | **YES — sole suppressor** |
| `DBG_DS` | 1 | no |

`DBG_CGR` (the cgrnam family in `ncgrpw.c` + averify in `verify.c`) is
the only region whose mere presence flips rc=1→0 — the same region that
calls `cgrnam → add_cache → HASH`.  Its trace `fprintf`/`malloc` right
around the cache build perturbs the heap/register state at the wild
`add_cache` store so it lands on mapped memory.  The bisection and the
core dump independently converge on the same function.

## Files

- `task0a.sh` — empty-root battery + `ZZQQ` env-vs-code control.
- `rtest.sh`, `rtest2.sh`, `rtest3.sh`, `rtest4.sh` — the original A/B
  harnesses (etc/group A/B, order-vs-flag, devnull/DS_DEBUG=0, ZZQQ).
- `rtest5.sh` — the per-region bisection (needs `per-region-dsdebug.patch`).
- `per-region-dsdebug.patch` — the diagnostic split; `git apply` from
  the repo root, rebuild, deploy unstripped, run `rtest5.sh`, then
  revert (`git checkout`).  Behaviour-preserving for `DS_DEBUG`/plain.
- `mod_prog.c` — the minimal modulo/division miscompile demonstrator.
- `adb-crashsite.txt` — the adb scripts that named `add_cache` and
  dumped `HASH`.

## Staging on the box

`APKG-0.1.pkg` → `/tmp/APKG-0.1.pkg`; a standard admin file (mail=,
instance=overwrite, everything nocheck, basedir=default) → `/tmp/adm`.
Box `/tmp` is wiped on reboot; re-push both before re-running.

## The fix (next wave, out of scope here)

Belongs in the toolchain, not this tree: teach `amix-cc` / the
`m68k-cbm-sysv4-gcc` wrapper to rewrite the SGS `tdivs.l ea,Dr:Dq` /
`tdivu.l ea,Dr:Dq` remainder-divide into a form GNU as 2.8.1 encodes
with the remainder register intact (same class as the shipped `.swbeg`
and `fcmp` fixups).  A tree-local stopgap is to avoid variable-divisor
`%`/`/` on the hot paths (e.g. hand-code `HASH`'s reduction), but the
real defect is every variable-divisor modulo in the codebase.
