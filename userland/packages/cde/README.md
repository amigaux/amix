# cde — the Common Desktop Environment 2.5.3 for Amix

CDE 2.5.3 (cdesktopenv), built from the upstream release against X11R6.3 and Motif 2.3.8:
- `dtlogin`, the graphical login, and `dtsession`, the session manager;
- `dtwm`, the window manager, with the front panel and workspaces;
- `dtterm`, `dtfile`, `dtpad`, `dtcalc`, `dtcm` (calendar, with `rpc.cmsd`), `dtmail`, `dticon`,
  `dtstyle`, `dthelpview`, `dtprintinfo`, `dtscreen` and the other desktop programs;
- ToolTalk (`ttsession`, `rpc.ttdbserver`, the `tt*` commands, `tt_type_comp`, the message
  viewer `ttsnoop`) and its types database;
- the App Builder, `dtbuilder`, with its code generator `dtcodegen`;
- the action and data-type databases, the app-defaults, the C locale's message catalogues, the
  backdrops, palettes and icons.

    sh build/pkg/pkgbuild.sh userland/packages/cde     # in the build container: make -C build recipes/cde

Package: `cde`, category `x11`, set `extra`. It depends on `x11r6.3` (the server, its fonts and
`lib/X11`); it builds against x11r6.3, motif, libjpeg and regex (`BUILD_DEPENDS`). Built with GCC 14
(`-m68020-60 -mno-strict-align -O2`).

**Licence.** CDE is LGPL, version 2 or any later version, and its media files (images, icons,
documentation) are CC BY-SA 3.0, attributed to The Open Group (`COPYING`). The programs are linked
statically, so they also contain X11R6.3's libraries (X Consortium licence), Motif (LGPL), libjpeg
(IJG), regex (Henry Spencer's licence) and this recipe's compatibility library (MIT, `compat/`):
`LGPL-2.0-or-later AND CC-BY-SA-3.0 AND X11 AND IJG AND Spencer-94 AND MIT`. CDE's own licence is
`/usr/dt/COPYING`; the texts of the libraries linked in are in `/opt/amix/dt/doc`, one directory
each (`x11r6.3`, `motif`, `libjpeg`, `regex`, `compat`).

**Two variants.** The package is the static build; `VARIANT=shared` builds the shared variant,
version `2.5.3-<PKGREV>.s`, with CDE's libraries shared (*The shared variant* below). A machine has
one or the other.

## Layout

- Everything CDE installs is under **`/opt/amix/dt`**, and **`/usr/dt` is a link to it**: CDE
  compiles `/usr/dt` into its programs and files (its installation top), and keeps doing so.
- Configuration under **`/etc/dt`**, CDE's configuration top, as on every CDE system; logs under
  `/var/dt`.
- **Manual pages.** The commands' pages, sections 1 and 1m (89 pages: `dtterm`, `dtwm`,
  `ttsession`, `rpc.ttdbserver` and the rest), are in `/opt/amix/man` with `whatis.d/cde`, as every
  package's, so `man dtterm` and `man -k` find them. The reference sections stay whole in CDE's own
  tree under upstream's names, as Motif's section 3 does: section 3 (419 pages of the Dt and
  ToolTalk interfaces), 4 (file formats, the action and data-type databases) and 5 (the widgets,
  fonts, actions and headers), in `/usr/dt/share/man/man3`, `man4` and `man5`; `/usr/dt/man` is
  CDE's own link to that directory, the one its `dtsearchpath` names in a desktop session. Many of
  their names are longer than s5's 14 bytes (`DtActionInvoke`, `dtsessionaction`), the limit of the
  shared tree. Read one with `/usr/ucb/nroff -man /usr/dt/man/man3/DtActionLink.3 | more`.
- **Help volumes**, in `/usr/dt/appconfig/help/C` (8.6 MB with their graphics), are **not
  compressed**: compressed, the help compiler runs each topic through the build host's `compress`,
  a tool whose output the box would read. The 17 volumes take 5.1 MB as they are; compressed they
  would take about 1 to 1.5 MB. The help viewer reads them directly.
- **dtterm's terminfo entry**, `/usr/share/lib/terminfo/d/dtterm`, so curses programs run in
  `dtterm` (`TERM=dtterm`). Its bytes are in the recipe, `terminfo/d/dtterm` (1593 bytes): the
  output of the stock `tic` (package core) on AMIX 2.1c, run on the emulator over the `dtterm.ti`
  this build makes (sha256 `0417dea6…a224f`, `DTTERM_TI_SHA256` in `build.sh`). No build-host
  `tic` writes the same bytes: ncurses' `tic` leaves out the capabilities an entry does not set,
  where the stock one writes every slot. The build fails if `dtterm.ti` changes. To make the
  entry again, install the package's `dtterm.ti` (`/usr/dt/config/dtterm.ti`) on a box and run
  `TERMINFO=/tmp/ti /usr/bin/tic /usr/dt/config/dtterm.ti`; `/tmp/ti/d/dtterm` is the new
  `terminfo/d/dtterm`, and its source's sha256 the new `DTTERM_TI_SHA256`. The smoke test compiles
  it on the box and compares.
- **Network services are off as installed.** CDE's two RPC servers, `rpc.ttdbserver` (ToolTalk's
  database server) and `rpc.cmsd` (the calendar server, which `dtcm` needs), are started by
  `/etc/init.d/cde-rpc` (`rc2.d/S78cde-rpc`, `K38cde-rpc` in rc0 and rc1) only when
  `/etc/rc.conf` says `ttdbserver=yes` or `cmsd=yes`; see cde-rpc(1M). `dtspcd`, the subprocess
  control daemon for running actions from other machines, gets no inetd line: cde-rpc(1M) gives the
  two lines to add by hand. No stock file (`inetd.conf`, `services`, `rpc`) is changed.
- **The login.** CDE ships no boot script. A line `start dtlogin` in `/etc/display` (amix-base,
  display(4)) makes the boot start `dtlogin` on the card's X server; without it the box keeps its
  text logins, and a user can still start a session with `xinit /usr/dt/bin/Xsession`.

## Not built yet: the 1.1.3 to-do list

This revision builds CDE for measurement and testing. If CDE ships in 1.1.3, every part below is
built first: the release gate is that no CDE component is left out.

| Part | Why it is not built yet | To do |
|---|---|---|
| `dtksh` (the desktop Korn shell) | its ksh93 is built by AST's own system, which compiles and runs hundreds of feature probes on the build machine | run the probes once on the emulator, commit Amix's answers as a reviewed file, cross-build ksh93 from them |
| `dtinfo` (the information library browser), with `DtMmdb` | needs LMDB, whose 0.9 locking needs process-shared POSIX mutexes or semaphores, which Amix lacks | LMDB 0.9 with upstream's System V semaphore locking backported |
| `dtdocbook` (`instant`, `dtdocbook2sdl`, `dtdocbook2man`) and the information library tools | they need Tcl and OpenSP on the box | Tcl and OpenSP ported as Amix packages |

Until then the scripts that run under `dtksh` are installed but do not work: `dterror` (dtfile's
error dialogs), `dtlp` (printing from the desktop), `dthelpgen` and `dthelpprint`. The manual
pages, help volumes and catalogues of the parts not built are left out with them (patch 29).

## Known limits

- **Single-byte characters only.** Amix has no wide-character library; `compat/` gives CDE the
  calls it needs (`wcslen`, `wcwidth`, `fgetwc` and the rest) for single-byte locales. Multibyte
  locales do not work.
- **iconv converts nothing.** Amix has no iconv; `compat/iconv.h` provides one that passes text
  through unchanged, which is right for the C locale only.
- **Nine long texts are not in the catalogues.** A System V catalogue message holds at most 1024
  bytes, and nine of CDE's usage and help texts are longer (dtpad's, dtfile's and tt_type_comp's
  usage, dtlogin's two help screens, two of DtSearch's). The C catalogues leave them out, and the
  programs print their built-in text, the same English. A translation could not carry them while
  the limit stands; only the C locale is built.
- **ToolTalk types on the box need the C development set.** `tt_type_comp` runs the types source
  through `/usr/ccs/lib/cpp`, which comes with Cdev; without it, it warns and reads the source
  as it is, without `#include` and `#define`.

## Patches

| Patch | What |
|---|---|
| `01-xinerama-optional` | configure: X11R6.3 predates Xinerama; build without it, one screen |
| `02-dtinfo-dtdocbook-optional` | `--disable-dtinfo`, `--disable-dtdocbook`; LMDB and Tcl checked only for them; their catalogues, app-defaults, actions and ToolTalk types only with them |
| `03-build-time-tools-fail` | the localized and tttypes rules went on after their tool failed; now they stop the build |
| `04-svr4-host` | configure chose the build machine's system branch; now the target's, with an SVR4 branch (`-DSVR4`) |
| `05-dtksh-dtappbuilder-optional` | `--disable-dtksh`, `--disable-dtappbuilder` (with ttsnoop); this build uses the first only |
| `06-tooltalk-svr4` | ToolTalk's SVR4 options: TLI, sysinfo, the SVR4 mount table; signal handler types; vsyslog |
| `07-tt-type-comp-no-cpp` | tt_type_comp says so when cpp is missing |
| `08-dtsvc-svr4` | DtSvc's headers on SVR4 (dirent.h, MAXNAMELEN) |
| `09-sundthelp-not-svr4` | DtSvc's dlopen fallback for libDtHelp is left out on SVR4 |
| `10-dtsearch-svr4` | DtSearch: no `-D_POSIX_SOURCE` on SVR4; LONG is int where int is 32 bits |
| `11-dtwidget-dtterm-svr4` | dtterm's STREAMS ptys and utmpx on SVR4 |
| `12-calendar-svr4` | csa's XDR time_t; SVR4's svcudp_create |
| `13-dtmail-svr4` | dtmail's signal handler types, SVR4 mailx's mailrc |
| `14-dtprintinfo-svr4` | dtprintinfo's SVR4 print-service parser, and its spool path buffers fixed |
| `15-dtlogin-no-anonymous-mmap` | dtlogin's shared page from /dev/zero |
| `16-dthelp-parser-svr4` | the HelpTag parsers' diagnostics buffer |
| `17-dtsearchpath-svr4-manpath` | dtsearchpath's default MANPATH on SVR4 |
| `18-dttypes-posix-regex` | dttypes uses POSIX regex on SVR4 |
| `19-fontaliases-x11r63` | the font alias directory made with X11R6.3's tools; test program under `make check` |
| `20-merge-reads-gencat-m` | the app-defaults merger reads its scratch catalogues itself |
| `21-dtimsstart-help-two-messages` | one over-long help message in two, same output |
| `22`–`26` `*-msg-long-message(s)` | the nine texts over the catalogue limit left out (above) |
| `27-install-hooks-destdir` | the install hooks' owners, set-id modes and tic run only for a direct install; under DESTDIR the package sets them |
| `28-ksh-for-build` | the scripts the build runs on the build machine take `KSH_FOR_BUILD`, not the box's `/usr/bin/ksh` |
| `29-docs-follow-switches` | the documentation follows the configure switches: no pages, help or guides for the parts not built |
| `30-man-name-lines` | the manual pages' NAME lines in the form `man -k` and whatis read |
| `31-dtlogin-waitpid-any-child` | dtlogin waits for any child: SVR4's `waitpid(0)` sees only its own process group |
| `32-amix-config-files` | Amix branches in the files the build preprocesses (dtlogin's Xsetup, Xsession, Xservers, Xconfig, Xfailsafe): Amix's paths and server |
| `33-dtlogin-svr4-shadow` | dtlogin reads the password from the shadow file on SVR4, as on Linux |
| `34-tooltalk-tli-negotiate-reply` | ToolTalk takes TLI's answer to `T_NEGOTIATE` as a success (no "t_optmgmt: No Error" per connection) |
| `35-dtlogin-close-unopened-catalog` | the greeter closes its message catalogue only when it opened one (a null descriptor read address 0) |
| `36-dtdbcache-no-arguments` | dtdbcache looks at `argv[1]` only when there is one (ToolTalk starts it with no arguments, and it read through the null pointer that ends `argv`) |
| `37-libabil-parser-prefix` | the App Builder's BIL parser under the prefix `abil_yy`: dtbuilder also links Motif's UIL compiler, another yacc parser, and statically both defined `yyparse`, `yylval`, `yychar`, `yynerrs` |
| `38-ttsnoop-own-sigset-static` | ttsnoop's own copy of libtt's `_tt_sigset` is static, so the static link with libtt has one definition (also an input of the App Builder's code: the record was made from the patched file) |
| `39-dtbuilder-man-name-line` | dtbuilder(1)'s NAME line in the form whatis reads, as patch 30 gives the other pages |
| `40-dates-from-source-date-epoch` | instant (docbook-to-man) and the help compilers' generator eltdef take their date from `SOURCE_DATE_EPOCH` (UTC) when it is set, not from the clock: the manual pages, help volumes and help compilers no longer carry the time of the build, so a rebuild gives the same bytes |
| `41-libtt-print-without-wide-printf` | libtt prints a message's strings (tt_message_print, the ToolTalk trace, ttsnoop's log) with each character's own bytes: it used printf's `%C`, a wide character, which the C library here does not know, and printed a C for every character but the last few |
| `42-ttsnoop-svr4-tail` | ttsnoop's panes run `tail +1f file`, the form the SVR4 tail takes (it opened `+0` from `tail -n +0 -f` and said "cannot open input"), and a log named with `-o` or `-O` is made first, since tail opens it before ttsnoop writes it (also an input of the App Builder's code: the record was made from the patched file) |
| `43-dtterm-svr4-pty-modules` | DtTerm (dtterm, and ttsnoop's panes) pushes `ptem` and `ldterm` on its pty slave, each unless `I_FIND` finds it: configure builds the `-pts` variant everywhere but Solaris, whose setup does nothing, and an SVR4 pty slave is a bare stream until its opener pushes them, so dtterm's shell found no terminal (no prompt, no echo) and output lines were not returned to the left margin |

Each patch has a header that says what and why.

## The App Builder's code

The user interfaces of `dtbuilder` and `ttsnoop` are C that `dtcodegen` writes at build time from
their `.bil` files, and `dtcodegen` is a program for the target, built in the same tree. The build
cannot run it, so its output is kept here, in `dtcodegen/`, from a run on Amix:

- `dtcodegen/ab` (dtbuilder) and `dtcodegen/tt` (ttsnoop) hold one record per dtcodegen run, in the
  order make runs them (36 and 11): its arguments, what it created (`after/`), what it rewrote with
  other contents (`diffs/`, unified diffs: the callbacks files and the message file it merges into),
  and in `before.sha256` the sums of the run's `.bip` and `.bil` and of the earlier contents of
  every file it rewrote.
- In the build, make's `DTCODEGEN` is `dtcodegen/replay.sh`. Each time make runs dtcodegen, replay
  finds the record with the same arguments, checks that the directory is as it was on Amix (the
  sums, and that no file the run created is there already), and writes what the run wrote. make's
  own steps around dtcodegen (copying the callbacks templates, ttsnoop's `sed` edits) run as
  upstream wrote them. Any change of input or order stops the build.
- **To make the record again** (a new CDE release, or a patch to a `.bil` file): build CDE, which
  installs `dtcodegen` and its catalogue; write the box scripts from make's dry run with
  `dtcodegen/regen/mkgen.py` (`make -n` in `programs/dtappbuilder/src/ab` and `programs/ttsnoop` of
  the configured tree, so the directories are as patched); on Amix, put `dtcodegen`, `dtcodegen.cat`, `regen/gen-lib.sh`,
  `regen/run.sh`, the two scripts and copies of the two directories under `/var/pk` as `run.sh`
  describes, and run `sh run.sh`; then `regen/collect.py out.tar <the two directories> dtcodegen`
  writes the records. Review the difference before committing it.
- dtcodegen's own log, `.dtcodegen.log` (times of day; only dtcodegen reads it), is not kept.

## Build notes

- **libjpeg, regex and the C++ runtime are linked from their archives**: both packages also
  ship a shared library, and GCC 14 has `libstdc++.so.6` since gcc14-cross-amix 276ef49, so the
  build puts a directory holding only `libjpeg.a`, `libregex.a` and `libstdc++.a` first on the
  link path, and fails if any program NEEDs a shared `libjpeg`, `libregex` or `libstdc++`.
  `-lstdc++` ends every link: ToolTalk's `libtt` is C++, and libtool records no runtime for the
  static library now that its C++ probe finds the shared one.
- **dtbuilder links Motif's `libMrm`** after `libUil`, which calls it: the link line's
  `$(MRESOURCELIB)`, which configure never sets, is given as `-lMrm`.
- **Manual pages for every program**: upstream's `dtbuilder.1` and ToolTalk's `ttauth.man`, which
  make install leaves out, and ours in `man/` for the programs upstream has none for (`Xsession`,
  `dtdbcache`, `dtdspmsg`, `dterror.ds`, `dtlpsetup`, `dtopen` with its four names, `dtprintegrate`,
  `dtsrclean`, `dtsrdelete`, `dtcodegen`, `ttsnoop`). Upstream's `ttsnoop.6` is left out: it is the
  page of the TeleUse ttsnoop this one replaced, with options this ttsnoop does not have. `dthelpgen.dtsh`, `dthelpprint.sh` and
  `rpc.ttdbserver` get alias pages to upstream's `dthelpgen`, `dthelpprint` and `ttdbserver`.
- **The build machine's tools are built from this tree**: `tradcpp`, `lineToData`,
  `mk_fonts_alias`, `merge`, `mkcatdefs`, the dthelp parsers' generators, and ToolTalk's
  `tt_type_comp` (with the build container's TI-RPC; `host/mp_desktop_nox.C` stands in for the one
  ToolTalk file that needs Xlib, which the build container does not have). The types database is
  compiled with the host `tt_type_comp`, through `amix-xcpp`, which has the box cpp's predefines.
- **Message catalogues** are written by our `gencat` in its one-file format (`gencat -m`), the
  format Amix's `catgets` reads.
- **`compat/`**: prototyped copies of Amix's K&R headers (RPC, TLI, sockets, netdb, the X11R6.3
  headers that lack prototypes) and the calls Amix's libc lacks (`mkstemp`, `strtok_r`, the
  wide-character calls, `vasprintf`, `posix_openpt`, `getdomainname`, `madvise`, `fnmatch`,
  `strnlen`, `round`), in `libamixcompat-cde.a`, linked into every program.
- configure is answered for what a cross build cannot test (the static X and Motif libraries) and
  given the box's paths: `/usr/ccs/lib/cpp` for tt_type_comp, `/usr/bin/ksh` for the scripts.

## The shared variant

`VARIANT=shared` builds CDE with its libraries shared, version `2.5.3-<PKGREV>.s`
(`SHARED_PKGREV`), from `prototype.shared` in the build tree `cde-shared`, against the shared
variants of X11R6.3 and Motif (their build trees `x11r6.3-shared` and `motif-shared`) and the
shared `libjpeg` and `regex`, to compare memory use with the static build. It is the same package
(`cde`, the same paths and configuration files), so a machine has one variant or the other, with
the shared X11R6.3 and Motif. The hooks take the variant from `$VARIANT`; with `VARIANT=static`,
the default, the build and its bytes are as before.

- **CDE's ten libraries** in `/opt/amix/dt/lib` in place of the archives, each the file its
  soname names (`libDtSvc.so.2` and the rest) with a `lib*.so` link beside it, and the programs
  linked against them with `DT_RPATH /opt/amix/dt/lib:/opt/amix/X11R6/lib:/opt/amix/lib`. The
  build links through one directory of links to the shared X11R6.3, Motif, libjpeg and regex
  libraries (`shlib`), so nothing static of theirs is linked in.
- **Each library records the libraries it calls** (`DT_NEEDED`): upstream's `LIBADD`s name almost
  none, as static programs link everything anyway, and the hooks give each library its own.
- **The C++ runtime is shared** (`libstdc++.so.6`, package `cxxrt`): ToolTalk's `libtt` and part
  of `libDtSvc` are C++. Every library linked with `libDtSvc` links the runtime too, or the
  linker would copy the unwinder `libDtSvc` calls from GCC's static, non-PIC `libgcc.a` into it.
  libtool keeps no `-lstdc++` among a library's own libraries, so the build names the runtime
  `libcxxrt.so`, a link to `libstdc++.so.6`; `NEEDED` names its soname.
- libtool's answers as in Motif's shared variant (`pass_all`, no `-lc`). Compat's `basename` comes
  ahead of `libgen`'s non-PIC one, compat has a `sysinfo` (`sysinfo.S`) for the libraries, as
  `libc.so.1` does not export it, and a position-independent `__fixdfdi` (`fixdfdi.c`) ahead of
  `libgcc.a`'s, whose absolute call to `__fixunsdfdi` would be a text relocation in `libDtSvc` and
  `libDtMrm`; it goes when the toolchain's `libgcc` is position-independent.
- `_XtInherit` from X11R6.3's shared variant's `libXtInherit.a` is linked into every program (its
  README, *The shared variant*), and through the same link flags into each library; the program's
  is the one bound at run time.
- **Text relocations in two libraries, named by the build** (`textrel-report.py`), from code
  that exists on Amix only static and non-PIC: Amix's `libm` (`sin`, `cos`, `tan` in
  `libDtHelp.so.2`; `log`, `log10`, `sqrt` in `libDtSearch.so.2`, with their helpers). Each costs,
  per process, the pages it relocates. A text relocation from any other source fails the build.
- **Gates**: `check-got-addend.py` on the PIC objects and compat, and `check-dynstr-order.py` on
  every library and program.
