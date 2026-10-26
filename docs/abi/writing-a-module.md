# Writing an Amix kernel module

A module is one ELF relocatable object that the module core loads into a
running Amix kernel of one line: `k30` (68030) or `k46` (68040/68060). It
is built with the ABI kit of that line. The kit is a directory with the
headers, the tools and a make fragment. No Amix installation is needed
beside it. The rules a module meets are three contracts, shipped in the
kit's `docs/contracts/`:
- C3-1: the object and its `.moddata`;
- C3-2: the kernel names it may use;
- C3-6: what a driver changes to become a module.

## 1. What you need

- The pinned cross compiler, gcc-cross-amix (`m68k-cbm-sysv4-gcc` 2.7.2.3,
  binutils 2.8.1), on `PATH`.
- The kit for the line: `kit-k30` or `kit-k46` (`make kit` in amix-dlm).
- Python 3, for the checker.
- For `LOCALIZE` only, a newer objcopy (`m68k-elf-objcopy`, as
  gcc14-cross-amix has).

One module source gives one object per line: build it once with each
kit. The two objects are two packages, because their kabi tags differ.

## 2. The smallest module

The kit's `sample/hello` is the template:

```
hello.c      the code
Master       its .moddata keys and its definition line
Makefile     KIT, MODULE, OBJS, then include $(KIT)/mk/module.mk
```

```c
#include "sys/types.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int printf();

static int
hello_load(params)
	char *params;		/* "name=value ..." from the manifest, or 0 */
{
	printf("hello: loaded\n");
	return 0;		/* or ENXIO: no hardware, the module is not kept */
}

static int
hello_unload()
{
	printf("hello: goodbye\n");
	return 0;
}

MOD_MISC_WRAPPER(hello, hello_load, hello_unload, "the ABI kit's sample module");
```

```
$modtype misc
$class demand
$cpu 68020
$unload allowed
$param greeting:str:hello
hello	hello
```

Run `make`. The module is `build/mod.d/hello`: compiled against the kit's
headers, linked, its `.moddata` written by `mkmod`, and checked by
`modfix` and `modcheck.py`. The checker names each rule a module breaks.
The module core makes the same refusals at load time.

## 3. The Master file

One `$key value` line per `.moddata` key (C3-1 §3), then the definition
line `name prefix`. The module's name is its file name: 1–14 characters
of `[a-z0-9_-]`. The prefix is the one the wrapper macro uses
(`<prefix>_wrapper`).

| Line | Value |
|---|---|
| `$modtype` | `misc`, `drv` or `str`: the wrapper macro you use |
| `$class` | `boot` (loaded after the root is mounted) or `demand` (at the first open of one of its majors) |
| `$cpu` | the lowest CPU it runs on: `68020`, `68030`, `68040`, `68060` |
| `$majors` | `c:<n>` per character major, each registered to this module's name in the kit's `registry/majors` |
| `$match` | for a boot module that needs a board: `zorro:MMMM:PP`, `mobo:<probe>` or `always`, comma-separated |
| `$depend` | modules whose globals it uses (one line per name) |
| `$unload` | `never` (the default) or `allowed` |
| `$param` | `<name>:<type>:<default>[:<min>:<max>]`, one line each: types `int`, `hex`, `bool`, `str` |
| `$desc` | one line |

`kabi` and `cc` come from the kit (`kit.conf`). Never write them yourself.

**Parameter values** reach `_load` as one string, `name=value`
separated by spaces, or 0. They come from the generation's manifest
(`param <module>.<name>=<value>`): the module's defaults, then the
package's `modreg.d`, then the administrator's `modreg.local.d`. The
string is valid only during `_load`, so copy what you keep. A value is
in C3-1 §3's form:
- `int`: decimal;
- `hex`: `0x…`;
- `bool`: `0` or `1`;
- `str`: one word.

## 4. A driver

A character driver uses `MOD_DRV_WRAPPER(prefix, load, unload, halt,
desc)`, and defines `prefix_drvdata[]` with its `cdevsw` row and
`drv_cmajor`:

```c
#include "sys/types.h"
#include "sys/conf.h"
#include "sys/moddefs.h"

struct mod_drv_data mydrv_drvdata[] = {
	{ { 0 }, 0, 0,
	  { mydrvopen, mydrvclose, mydrvread, mydrvwrite, mydrvioctl },
	  52, 1 }
};
MOD_DRV_WRAPPER(mydrv, mydrv_load, mydrv_unload, mydrv_halt, "my driver");
```

`52, 1` are its major and the count of consecutive majors. The major must
be registered to the module's name: 52 is monsw's, so this sketch builds
only as `monsw`. A STREAMS driver's row is zeros except `d_str`. The core reads a zero
entry as `nodev`. What changes from a static driver, in short (C3-6 §1
has it in full):
- `_load` does the init work: find the board, map it, set it up. It
  returns `ENXIO` if there is no board, and leaves nothing behind on an
  error.
- No `cdevsw` edit, no `init_tbl` entry, no `parinit` wrapper: the
  majors come from `.moddata`.
- Interrupts go through `intr_attach`. Polled stays the default. A
  level-6 handler calls no kernel function: it acknowledges, masks and
  flags, and the work runs at level 4 or below.
- The console goes through `cons_hook_set`, never `conputc`.
- Board windows: `phystokv` below `VSECT1`, `sptalloc` or (k46)
  `dev_kvmap` above. Never give a board the address of the module's own
  memory: there is no DMA interface in DDI v1.0.
- `_unload` undoes everything: hooks, handlers, timeouts, mappings,
  registrations with other modules.
- `_halt` (void) stops a board that can interrupt or write memory.

## 5. Kernel names

`docs/ddi.md` lists every name, with its context and contract. A module
may import only those, and the globals of the modules it names in
`depend`. Weak undefined symbols are allowed: they resolve to 0, as the
wrapper's `<prefix>_conf_data` does. Notes on particular names:
- `cputype` is a `long` here; read it as `DDI_CPUTYPE`.
- `displayedscreen` is the kernel's `struct screen *`. Declare it
  yourself.
- A stock header's tentative definition (`int ifnet;`) becomes a private
  copy in your module. The checker warns about each COMMON symbol.

## 6. Linking other objects in

`EXTRA` names objects linked in as they are. `LOCALIZE` names globals
made local after the link, so the module neither exports nor shadows
them. A console-drawing driver links the kit's copy of the stock Sun
font and keeps its name to itself:

```
EXTRA    = $(KIT)/stock/usr/sys/amiga/console/sunfont.o
LOCALIZE = builtinfont
```

## 7. On k46

The kit compiles with `-m68040`. Its `sys/immu.h` and `sys/param.h` are
the port's 4 KiB-page forms, and the checker refuses a shift by 11 of an
address (2 KiB pages). The compiler's wrapper rewrites what the 68060
lacks, and the checker scans for anything left
(`m68k-cbm-sysv4-scan060`).

## 8. Shipping it

The module goes into a package of role `module` as
`/etc/conf/mod.d/<name>`, with `/etc/conf/modreg.d/<name>` for its
defaults (C3-5). `kbootset build` puts it into the next generation and
writes its manifest record. The core loads only modules of the booted
generation's manifest, checked by SHA-256, unless the boot menu's
development load is on.
