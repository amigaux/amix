# build.sh -- cde hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.

# the libraries CDE builds against, as their recipes built them
# (BUILD_DEPENDS): X11R6.3 and Motif under /opt/amix/X11R6, libjpeg and
# regex under /opt/amix
# the variant pkgbuild builds: static, or shared (prototype.shared)
CDE_VARIANT=${VARIANT:-static}
G14TOOLS=${AMIX_GCC14_PREFIX:+$AMIX_GCC14_PREFIX/../../tools}
XROOT="$AMIX_BUILD_ROOT/x11r6.3/dest/opt/amix/X11R6"
MROOT="$AMIX_BUILD_ROOT/motif/dest/opt/amix/X11R6"
if [ "$CDE_VARIANT" = shared ]; then
	XROOT="$AMIX_BUILD_ROOT/x11r6.3-shared/dest/opt/amix/X11R6"
	MROOT="$AMIX_BUILD_ROOT/motif-shared/dest/opt/amix/X11R6"
fi
JROOT="$AMIX_BUILD_ROOT/libjpeg/dest/opt/amix"
RROOT="$AMIX_BUILD_ROOT/regex/dest/opt/amix"

# the compatibility layer (compat/, ours): prototyped copies of Amix's K&R
# headers and the calls CDE uses that Amix's libc lacks; built under $BUILD,
# which the harness sets after this file is read (cde_vars)
cde_vars() {
	COMPAT="$BUILD/compat"
	CDE_CPPFLAGS="-I$COMPAT -I$XROOT/include -I$MROOT/include -I$JROOT/include -I$RROOT/include"
	# the static build links libjpeg, regex and the C++ runtime from their
	# archives: a directory holding only those comes first, as libjpeg, regex and
	# the toolchain (libstdc++.so.6, since gcc14-cross-amix 276ef49) also have
	# shared ones
	ALIB="$BUILD/alib"
	CDE_LDFLAGS="-L$ALIB -L$XROOT/lib -L$MROOT/lib -L$JROOT/lib -L$RROOT/lib -L$COMPAT/lib"
	# the shared variant: CDE's libraries shared too, linked against the shared X,
	# Motif, libjpeg and regex through one directory of links (the staged .so links
	# name the box's paths), with the box's paths as the run-time search path
	CDE_LIBKIND="--disable-shared --enable-static"
	CDE_PIC=
	CDE_XLIBDIR="$XROOT/lib"
	if [ "$CDE_VARIANT" = shared ]; then
		SHLIB="$BUILD/shlib"
		CDE_XLIBDIR="$SHLIB"
		CDE_LIBKIND="--enable-shared --disable-static"
		CDE_PIC=-fPIC
		# with every program's own _XtInherit, ahead of libXt's (x11r6.3-shared's
		# libXtInherit.a): a stopgap for the stock runtime linker
		CDE_LDFLAGS="-L$SHLIB -L$COMPAT/lib -Wl,-rpath-link,$SHLIB -Wl,-rpath,$PREFIX/lib:/opt/amix/X11R6/lib:/opt/amix/lib -Wl,-u,_XtInherit -lXtInherit"
		# libtool's SVR4 vendor table lacks `cbm': pass_all, as for the vendors it
		# knows, keeps each library's dependency libraries in its link
		CDE_SEEDS="$CDE_SEEDS lt_cv_deplibs_check_method=pass_all lt_cv_archive_cmds_need_lc=no"
		# compat ahead of libgen: its PIC basename, not libgen's non-PIC one
		# (libtool keeps a repeated library's last place, so libgen moves to the end)
		CDE_LIBS="$(echo "$CDE_LIBS" | sed 's/ -lgen / /') -lgen"
	else
		# libtt is C++, and the C programs that link it need its runtime
		# (__gxx_personality_v0, the type_info vtables): libtool's C++ probe
		# now finds the shared runtime and records nothing for a static libtt
		CDE_LIBS="$CDE_LIBS -lstdc++ -lm"
	fi
}

# shlib_farm: the shared variant's link directory: every shared library of the
# shared X, Motif, libjpeg and regex under its own name and its libfoo.so name
shlib_farm() {
	rm -rf -- "${SHLIB:?}"; mkdir -p "$SHLIB"
	for d in "$XROOT/lib" "$MROOT/lib" "$JROOT/lib" "$RROOT/lib"; do
		for f in "$d"/lib*.so.*; do
			[ -f "$f" ] && [ ! -L "$f" ] || continue
			b=$(basename "$f")
			ln -sf "$f" "$SHLIB/$b"
			ln -sf "$f" "$SHLIB/${b%%.so.*}.so"
		done
	done
	# X11R6.3's static-only libraries (Xau, Xdmcp, FS): for programs, which may
	# link an archive (a shared library may not: no PIC code in them)
	for f in "$XROOT"/lib/lib*.a; do
		b=$(basename "$f" .a)
		ls "$XROOT/lib/$b".so.* > /dev/null 2>&1 || ln -sf "$f" "$SHLIB/$b.a"
	done
	# GCC 14's shared C++ runtime (package cxxrt), which the driver finds only
	# for g++, as libcxxrt.so: for the libraries linked with libDtSvc (their
	# LIBADD; NEEDED names its soname, libstdc++.so.6)
	_cxs=$AMIX_GCC14_PREFIX/m68k-elf/lib/cxxrt/libstdc++.so.6
	[ -f "$_cxs" ] || { echo "[FAIL] no $_cxs" >&2; exit 1; }
	ln -sf "$_cxs" "$SHLIB/libstdc++.so.6"
	ln -sf "$_cxs" "$SHLIB/libcxxrt.so"
	for l in X11 Xt Xm Xext Xmu SM ICE Xp jpeg regex cxxrt; do
		[ -e "$SHLIB/lib$l.so" ] || { echo "[FAIL] no shared lib$l for the shared variant" >&2; exit 1; }
	done
}

# the 64-bit printf gate: the only "conversions" it finds are the action
# database's default host list "%DatabaseHost%,%LocalHost%" (Dt/ActionDb.h,
# split by DtSvc's own strncmp in ActionFind.c) and dtlogin's message token
# "%LocalHost%" (replaced by strstr in vgmain.c); neither is a printf format
AMIX_LL_PRINTF_REVIEWED="the %L hits are CDE's %DatabaseHost%/%LocalHost% tokens (ActionFind.c, vgmain.c), never printf formats; no ll conversion in CDE"

# the dtterm.ti that terminfo/d/dtterm was compiled from (README)
DTTERM_TI_SHA256=0417dea650c744c5ffe35f37d999d8eb4f4e0506658592da9f5c3c89828a224f

# the build host's compilers, for the tools the build runs, compiled from
# this tree
HOSTCC="gcc -std=gnu99 -w"
HOSTCXX="g++ -std=gnu++11 -fpermissive -w"

# configure: the X, Motif and other libraries are static, so configure's
# link tests are answered for it; GENCAT runs ours in its one-file format;
# the programs CDE's scripts and programs run on the box are given as the
# box's paths, not the build host's: cpp (tt_type_comp), ksh (the scripts),
# xrdb and sessreg (dtsession, dtlogin's Xstartup and Xreset, from
# x11r6.3); tic is not run (dtterm's terminfo is for the box, not the
# build host);
# the build itself runs sym2num and the documentation scripts with the
# build container's ksh (KSH_FOR_BUILD)
CDE_SEEDS="ac_cv_lib_Xext_XextFindDisplay=yes ac_cv_lib_Xt_XtInitialize=yes \
	ac_cv_lib_Xmu_XmuMakeAtom=yes ac_cv_lib_SM_SmcOpenConnection=yes \
	ac_cv_lib_Xm_XmTextSetString=yes ac_cv_prog_ONSGMLS=false LEX=flex \
	ac_cv_path_CPP_PROGRAM=/usr/ccs/lib/cpp ac_cv_path_KSH=/usr/bin/ksh KSH=/usr/bin/ksh \
	ac_cv_path_XRDB=/opt/amix/X11R6/bin/xrdb ac_cv_prog_SESSREG=/opt/amix/X11R6/bin/sessreg \
	ac_cv_prog_TIC=: KSH_FOR_BUILD=ksh"
CDE_LIBS="-lXp -lSM -lICE -lXext -lX11 -lgen -lsocket -lnsl -lelf -lamixcompat-cde -lregex"

# make: configure's CPPFLAGS (the compat headers first) plus the house
# declarations; rpcgen's output (lib/csa) also needs amix-rpcgen.h
# the documentation runs the configured dtdocbook2man and dtdocbook2sdl
# with the build host's instant, the tree's own SGML, Tcl and tpt files,
# and the build host's dthelp_htag2; the help volumes uncompressed (-u):
# compressed, each topic is run through the build host's compress
# DTCODEGEN: the App Builder's code as the target dtcodegen wrote it (dtcodegen/replay.sh);
# MRESOURCELIB, which dtbuilder links after -lUil and configure never sets: Motif's libMrm,
# which the static libUil calls
make_cde() {	# make_cde [make args]
	dtdcbk_libexecdir="$BUILD/hostdocbook" dtdcbk_libdir="$TREE/programs/dtdocbook" \
	dtdcbk_datarootdir="$TREE/programs/dtdocbook" \
	make CPPFLAGS="$(sed -n 's/^CPPFLAGS = //p' Makefile) -include $AMIX_GCC14_DECLS" \
		TT_TYPE_COMP="$BUILD/hosttt/tt_type_comp" DTHELP_HTAG2="$BUILD/hosthelp/dthelp_htag2" \
		DTCODEGEN="sh $HERE/dtcodegen/replay.sh" \
		MRESOURCELIB=-lMrm \
		DTDOCBOOK="$TREE/programs/dtdocbook/dtdocbook2sdl -u" "$@"
}

# a make variable's value as make hands it to the shell
mvar() {	# mvar DIR VAR
	printf '$(info $(%s))\np:\n\t@:\n' "$2" | make -s -C "$1" -f Makefile -f - p
}

build_compat() {
	rm -rf -- "${COMPAT:?}"
	cp -R "$HERE/compat" "$COMPAT"
	$CC $AMIX_CFLAGS $CDE_PIC -Wall -I"$COMPAT" -include "$AMIX_GCC14_DECLS" -fno-builtin-round \
		-c -o "$COMPAT/lib/amix-compat.o" "$COMPAT/lib/amix-compat.c" || exit 1
	# basename in a member of its own: only a link that puts compat ahead of
	# libgen (the shared variant) takes it
	$CC $AMIX_CFLAGS $CDE_PIC -Wall -I"$COMPAT" -include "$AMIX_GCC14_DECLS" \
		-c -o "$COMPAT/lib/basename.o" "$COMPAT/lib/basename.c" || exit 1
	_co="$COMPAT/lib/amix-compat.o $COMPAT/lib/basename.o"
	# the shared variant: sysinfo too (sysinfo.S: libc.so.1 does not export it)
	if [ "$CDE_VARIANT" = shared ]; then
		$CC $AMIX_CFLAGS -c -o "$COMPAT/lib/sysinfo.o" "$COMPAT/lib/sysinfo.S" || exit 1
		_co="$_co $COMPAT/lib/sysinfo.o"
	fi
	$AR rc "$COMPAT/lib/libamixcompat-cde.a" $_co || exit 1
	$RANLIB "$COMPAT/lib/libamixcompat-cde.a"
}

# the build host's tools: programs the build runs that are built in this tree
host_tools() {
	# tradcpp preprocesses the configuration files and scripts for the box:
	# its predefined macros are Amix's (patch 32's __AMIX__), not the build
	# host's (__linux__, __x86_64__), so the files take Amix's branches
	make -C util/tradcpp CC="$HOSTCC" AR=ar RANLIB=ranlib CFLAGS= LDFLAGS= LIBS= \
		CPPFLAGS='-DCONFIG_OS=\"__AMIX__\" -DCONFIG_OS_2=\"__unix__\" -DCONFIG_CPU=\"__m68k__\" -DCONFIG_SIZE=\"__ILP32__\" -DCONFIG_BINFMT=\"__ELF__\"' \
		tradcpp || exit 1
	echo '__AMIX__ __linux__ __x86_64__ __m68k__' | util/tradcpp/tradcpp -P | grep -x '1 __linux__ __x86_64__ 1' > /dev/null || {
		echo "[FAIL] tradcpp does not predefine Amix's macros" >&2; exit 1; }
	for t in lib/DtTerm/util:lineToData \
		programs/fontaliases:mk_fonts_alias programs/localized/util:merge \
		programs/localized/util:mkcatdefs; do
		make -C "${t%%:*}" CC="$HOSTCC" AR=ar RANLIB=ranlib CFLAGS= CPPFLAGS= LDFLAGS= LIBS= "${t#*:}" || exit 1
	done
}

# dthelp's three HelpTag parser chains: their generators (context, fclndir,
# build, eltdef) run on the build host; the installed dthelp_htag1, htag2
# and ctag1 link libutil.a too, so it is rebuilt for the target, and every
# generator, stamp and generated file is dated in make's order, so the
# target make finds them current and never runs a generator again
host_dthelp() {
	hm() { _hd=$1; shift; make -C "$_hd" CC="$HOSTCC" AR=ar RANLIB=ranlib CFLAGS= CPPFLAGS= LDFLAGS= LIBS= "$@"; }
	for c in pass1 canon1 pass2; do
		d=$TREE/programs/dthelp/parser/$c
		h=helptag; [ $c = pass2 ] && h=
		hm "$d/util" libutil.a context fclndir || exit 1
		hm "$d/build" CDONE || exit 1
		hm "$d/build" BDONE || exit 1
		hm "$d/eltdef" CDONE || exit 1
		hm "$d/eltdef" EDONE || exit 1
		hm "$d/parser" CDONE || exit 1
		[ -z "$h" ] || hm "$d/$h" XDONE || exit 1
		objs=$(mvar "$d/util" am_libutil_a_OBJECTS)
		( cd "$d/util" && rm -f -- libutil.a $objs )
		make -C "$d/util" CPPFLAGS="$(sed -n 's/^CPPFLAGS = //p' Makefile) -include $AMIX_GCC14_DECLS" \
			libutil.a || exit 1
		# one second apart from now on, newer than everything before (the
		# configure header among it); then wait until the clock is past
		# the last, so whatever the target make writes is newer still
		T=$(date +%s)
		tick() { T=$((T + 1)); touch -d "@$T" "$@"; }
		tick $(for o in $objs; do echo "$d/util/$o"; done)
		tick "$d/util/libutil.a"
		tick "$d/util/context.o"
		tick "$d/util/context" "$d/util/fclndir"
		for s in build eltdef; do
			tick "$d/$s/CDONE"
			tick $(cd "$d/$s" && for f in $(mvar . CPRODS) $(mvar . CTRASH); do [ -e "$f" ] && echo "$d/$s/$f"; done)
			tick "$d/$s/$s"-*.o
			tick "$d/$s/$s"
			case $s in build) st=BDONE p=BPRODS;; *) st=EDONE p=EPRODS;; esac
			tick "$d/$s/$st"
			tick $(cd "$d/$s" && for f in $(mvar . $p) $(mvar . TRASH); do [ -e "$f" ] && echo "$d/$s/$f"; done)
		done
		tick "$d/parser/CDONE"
		tick $(cd "$d/parser" && for f in $(mvar . CPRODS) $(mvar . CTRASH); do [ -e "$f" ] && echo "$d/parser/$f"; done)
		[ -z "$h" ] || tick "$d/$h/XDONE"
		while [ "$(date +%s)" -le "$T" ]; do sleep 1; done
	done
}

# ToolTalk's tt_type_comp for the build host, which compiles the types
# database (programs/tttypes) the box's ttsession reads: libtt from this
# tree (mini_isam, api/c, api/dnd, db, mp, util, slib) with the build
# container's TI-RPC, mp_desktop.C replaced by host/mp_desktop_nox.C (no
# Xlib on the build host; X11R6.3's headers for the rest), and its cpp
# our amix-xcpp, the box cpp's
# predefines; into $BUILD/hosttt, the target objects untouched
host_tooltalk() {
	O=$BUILD/hosttt; T=$TREE/lib/tt
	rm -rf -- "${O:?}"; mkdir -p "$O/include"
	# configure's header with the build host's sizes, and without the
	# target's rpc_inline_t (TI-RPC has its own)
	sed -e 's/^#define SIZEOF_LONG 4$/#define SIZEOF_LONG 8/' \
		-e 's/^#define SIZEOF_TIME_T 4$/#define SIZEOF_TIME_T 8/' \
		-e '/^#define rpc_inline_t /d' "$TREE/include/cde_config.h" > "$O/include/cde_config.h"
	# <X11/Xos_r.h> (tt_db_client, tt_host, tt_log, ...): X11R6.3's, as the
	# build host need have no X headers (the build container has none)
	common="-DHAVE_CONFIG_H -I$O/include -I$TREE/include -I/usr/include/tirpc -I$XROOT/include"
	make -C "$T/bin/tt_type_comp" mp_types_gram.h || exit 1
	for x in mini_isam:libisam_a lib/api/c:libapi_la lib/api/dnd:libdnd_la \
		lib/db:libdb_la lib/mp:libmp_la lib/util:libutil_la slib:libstt_a; do
		d=${x%%:*} v=${x#*:} objs=
		mkdir -p "$O/$d"
		cx=$(mvar "$T/$d" ${v}_CXXFLAGS); cc=$(mvar "$T/$d" ${v}_CFLAGS)
		for f in $(mvar "$T/$d" ${v}_SOURCES); do
			case $f in *.h|*.hh) continue;; esac
			o=$O/$d/$(echo "${f%.*}" | tr / _).o
			src=$f
			[ "$d/$f" = lib/mp/mp_desktop.C ] && src=$HERE/host/mp_desktop_nox.C
			case $f in
			*.c) ( cd "$T/$d" && eval "$HOSTCC $common -I. $cc -c -o \"$o\" \"$src\"" ) || exit 1;;
			*) ( cd "$T/$d" && eval "$HOSTCXX $common -I. $cx -c -o \"$o\" \"$src\"" ) || exit 1;;
			esac
			objs="$objs $o"
		done
		rm -f -- "$O/$d/lib.a"; ar rcs "$O/$d/lib.a" $objs || exit 1
	done
	d=bin/tt_type_comp objs=
	mkdir -p "$O/$d"
	cx=$(mvar "$T/$d" tt_type_comp_CXXFLAGS | sed 's|-DCPP_PROGRAM=[^ ]*||')
	for f in $(mvar "$T/$d" tt_type_comp_SOURCES); do
		o=$O/$d/${f%.*}.o
		( cd "$T/$d" && eval "$HOSTCXX $common -I. $cx \"-DCPP_PROGRAM=\\\"$(command -v amix-xcpp)\\\"\" -c -o \"$o\" \"$f\"" ) || exit 1
		objs="$objs $o"
	done
	L=$O
	g++ -o "$O/tt_type_comp" $objs $L/slib/lib.a $L/lib/api/c/lib.a $L/lib/db/lib.a \
		$L/lib/mp/lib.a $L/lib/util/lib.a $L/lib/api/dnd/lib.a $L/mini_isam/lib.a \
		$L/slib/lib.a $L/lib/mp/lib.a $L/lib/db/lib.a $L/lib/util/lib.a $L/lib/api/c/lib.a \
		-ltirpc || exit 1
	"$O/tt_type_comp" -v
}

# the documentation's tools for the build host: instant (DocBook to the
# help and man formats, with the build container's Tcl), and dthelp_htag2
# (the help volume compiler) from the pass2 parser chain, whose generated
# sources host_dthelp made; both into $BUILD, the target objects untouched
host_docs() {
	O=$BUILD/hostdocbook/instant
	rm -rf -- "${O:?}"; mkdir -p "$O"
	( cd "$TREE/programs/dtdocbook/instant" &&
		$HOSTCC -I/usr/include/tcl8.6 -I"$TREE/include" -o "$O/instant" \
		$(mvar . instant_SOURCES) -ltcl8.6 -lm ) || exit 1
	O=$BUILD/hosthelp; P=$TREE/programs/dthelp/parser/pass2
	rm -rf -- "${O:?}"; mkdir -p "$O"
	inc="-I$P/util -I$P/build -I$P/eltdef -I$P/htag2 -I$P/parser -I$TREE/include -DHAVE_CONFIG_H"
	for x in util:libutil_a htag2:libhelptag_a parser:dthelp_htag2; do
		d=${x%%:*} v=${x#*:} objs=
		for f in $(mvar "$P/$d" ${v}_SOURCES); do
			case $f in *.h) continue;; esac
			o=$O/$d-$(basename "${f%.c}").o
			( cd "$P/$d" && $HOSTCC -I. $inc -c -o "$o" "$f" ) || exit 1
			objs="$objs $o"
		done
		case $d in parser) pobjs=$objs;; *) rm -f -- "$O/$d.a"; ar rcs "$O/$d.a" $objs || exit 1;; esac
	done
	$HOSTCC -o "$O/dthelp_htag2" $pobjs "$O/htag2.a" "$O/util.a" || exit 1
}

build() {
	cde_vars
	if [ "$CDE_VARIANT" = shared ]; then
		shlib_farm
	else
		for f in "$XROOT/lib/libX11.a" "$MROOT/lib/libXm.a" "$JROOT/lib/libjpeg.a" "$RROOT/lib/libregex.a"; do
			[ -f "$f" ] || { echo "[FAIL] no $f (BUILD_DEPENDS)" >&2; exit 1; }
		done
		rm -rf -- "${ALIB:?}"; mkdir -p "$ALIB"
		_cxa=$($CXX -print-file-name=libstdc++.a)
		[ -f "$_cxa" ] || { echo "[FAIL] no libstdc++.a ($_cxa)" >&2; exit 1; }
		ln -s "$JROOT/lib/libjpeg.a" "$RROOT/lib/libregex.a" "$_cxa" "$ALIB/"
	fi
	command -v amix-xcpp > /dev/null || { echo "[FAIL] no amix-xcpp on PATH (build/hosttools)" >&2; exit 1; }
	build_compat > "$BUILD/compat.log" 2>&1 || { cat "$BUILD/compat.log" >&2; echo "[FAIL] compat" >&2; exit 1; }
	sh ./autogen.sh > "$BUILD/autogen.log" 2>&1 || { tail -30 "$BUILD/autogen.log" >&2; echo "[FAIL] autogen.sh" >&2; exit 1; }
	{
		set -x
		eval env $CDE_SEEDS GENCAT=\"gencat -m\" \
		CC=\"\$CC\" CXX=\"\$CXX\" CFLAGS=\"\$AMIX_CFLAGS\" CXXFLAGS=\"\$AMIX_CFLAGS\" \
		CPPFLAGS=\"\$CDE_CPPFLAGS\" LDFLAGS=\"\$CDE_LDFLAGS\" LIBS=\"\$CDE_LIBS\" \
		./configure --host=\"\$AMIX_HOST_TRIPLET\" --build=\"\$\(./config.guess\)\" \
			--x-includes=\"\$XROOT/include\" --x-libraries=\"\$CDE_XLIBDIR\" \
			$CDE_LIBKIND \
			--disable-dtinfo --disable-dtdocbook --disable-dtksh
	} > "$BUILD/configure.log" 2>&1 || { tail -30 "$BUILD/configure.log" >&2; echo "[FAIL] configure" >&2; exit 1; }
	for v in "CPP_PROGRAM = /usr/ccs/lib/cpp" "KSH = /usr/bin/ksh" \
		"XRDB = /opt/amix/X11R6/bin/xrdb" "SESSREG = /opt/amix/X11R6/bin/sessreg"; do
		grep -qx "$v" Makefile || { echo "[FAIL] configure did not take the box's path: $v" >&2; exit 1; }
	done
	host_tools > "$BUILD/host-tools.log" 2>&1 || { tail -20 "$BUILD/host-tools.log" >&2; echo "[FAIL] host tools" >&2; exit 1; }
	host_dthelp > "$BUILD/host-dthelp.log" 2>&1 || { tail -20 "$BUILD/host-dthelp.log" >&2; echo "[FAIL] dthelp generators" >&2; exit 1; }
	host_tooltalk > "$BUILD/host-tooltalk.log" 2>&1 || { tail -20 "$BUILD/host-tooltalk.log" >&2; echo "[FAIL] host tt_type_comp" >&2; exit 1; }
	host_docs > "$BUILD/host-docs.log" 2>&1 || { tail -20 "$BUILD/host-docs.log" >&2; echo "[FAIL] host documentation tools" >&2; exit 1; }
	# the shared variant: each CDE library records the libraries it calls
	# (DT_NEEDED); upstream's LIBADDs name almost none, as static programs link
	# them all anyway.  libtt first, as libDtSvc now NEEDs it; the additions are
	# given to every make, each variable belonging to one library.  libtt and
	# libDtSvc are partly C++, and each library linked with libDtSvc also links
	# the shared C++ runtime (-lcxxrt), so the unwinder libDtSvc calls
	# (_Unwind_Resume) comes from libstdc++.so.6, not as libgcc.a's non-PIC
	# copy in that library: libtool hands a shared library's own libraries on
	# to programs only
	set --
	if [ "$CDE_VARIANT" = shared ]; then
		set -- libtt_la_LIBADD="$(mvar lib/tt/lib libtt_la_LIBADD) -lXt -lX11 -lsocket -lnsl" \
			libDtSvc_la_LIBADD="$(mvar lib/DtSvc libDtSvc_la_LIBADD) ../tt/lib/libtt.la -lXm -lXt" \
			libDtSearch_la_LIBADD="$(mvar lib/DtSearch libDtSearch_la_LIBADD) ../DtSvc/libDtSvc.la -lcxxrt" \
			libDtWidget_la_LIBADD="$(mvar lib/DtWidget libDtWidget_la_LIBADD) ../DtSvc/libDtSvc.la -lXm -lXt -lcxxrt" \
			libDtHelp_la_LIBADD="$(mvar lib/DtHelp libDtHelp_la_LIBADD) ../DtSvc/libDtSvc.la -lXm -lXt -lcxxrt" \
			libDtPrint_la_LIBADD="$(mvar lib/DtPrint libDtPrint_la_LIBADD) ../DtHelp/libDtHelp.la ../DtSvc/libDtSvc.la -lXm -lXt -lcxxrt" \
			libDtTerm_la_LIBADD="$(mvar lib/DtTerm libDtTerm_la_LIBADD) ../DtHelp/libDtHelp.la ../DtSvc/libDtSvc.la -lXm -lXt -lcxxrt" \
			libcsa_la_LIBADD="$(mvar lib/csa libcsa_la_LIBADD) -lcxxrt" \
			libDtMrm_la_LIBADD="$(mvar lib/DtMrm libDtMrm_la_LIBADD) ../DtTerm/libDtTerm.la ../DtWidget/libDtWidget.la ../DtHelp/libDtHelp.la ../DtPrint/libDtPrint.la -lMrm"
		make_cde -C lib/tt/lib "$@" > "$BUILD/make-libtt.log" 2>&1 || {
			tail -30 "$BUILD/make-libtt.log" >&2; echo "[FAIL] make lib/tt/lib" >&2; exit 1; }
	fi
	# lib/csa's rpcgen output needs amix-rpcgen.h; the rest is one make
	make -C lib/DtSvc CPPFLAGS="$(sed -n 's/^CPPFLAGS = //p' Makefile) -include $AMIX_GCC14_DECLS" "$@" \
		> "$BUILD/make-dtsvc.log" 2>&1 || { tail -30 "$BUILD/make-dtsvc.log" >&2; echo "[FAIL] make lib/DtSvc" >&2; exit 1; }
	make -C lib/csa CPPFLAGS="$(sed -n 's/^CPPFLAGS = //p' Makefile) -include $AMIX_GCC14_DECLS -include $AMIX_GCC14_RPCGEN -Wno-unused-variable" "$@" \
		> "$BUILD/make-csa.log" 2>&1 || { tail -30 "$BUILD/make-csa.log" >&2; echo "[FAIL] make lib/csa" >&2; exit 1; }
	make_cde "$@" > "$BUILD/make.log" 2>&1 || { tail -40 "$BUILD/make.log" >&2; echo "[FAIL] make" >&2; exit 1; }
	# rpc.cmsd's hand-written lexer (lexit.c) without jump tables: the
	# 68060 gate cannot bound its two-level byte-class dispatch; then the
	# program is linked again with that object
	d=programs/dtcm/server
	rm -f -- "$d/rpc_cmsd-lexit.o" "$d/rpc.cmsd"
	{
		make -C "$d" CPPFLAGS="$(sed -n 's/^CPPFLAGS = //p' Makefile) -include $AMIX_GCC14_DECLS" \
			CFLAGS="-fno-jump-tables $AMIX_CFLAGS" rpc_cmsd-lexit.o && make_cde "$@"
	} > "$BUILD/make-lexit.log" 2>&1 || { tail -30 "$BUILD/make-lexit.log" >&2; echo "[FAIL] rpc.cmsd's lexer" >&2; exit 1; }
	# the shared variant: no PIC object may hold sym+N@GOT, which ld links to sym
	# (gcc14-cross-amix tools/check-got-addend.py); libtool keeps them in .libs
	if [ "$CDE_VARIANT" = shared ]; then
		_po=$(find lib -path '*/.libs/*.o' | LC_ALL=C sort)
		[ -n "$_po" ] || { echo "[FAIL] the shared variant built no PIC objects" >&2; exit 1; }
		python3 -I "$G14TOOLS/check-got-addend.py" $_po "$COMPAT"/lib/*.o > "$BUILD/got-addend.log" 2>&1 || {
			tail -20 "$BUILD/got-addend.log" >&2; echo "[FAIL] check-got-addend" >&2; exit 1; }
		echo "  check-got-addend: $(echo "$_po" | wc -l) PIC objects and compat clean"
	fi
}

stage() {
	cde_vars
	make_cde DESTDIR="$DEST" install > "$BUILD/install.log" 2>&1 || {
		tail -40 "$BUILD/install.log" >&2; echo "[FAIL] make install" >&2; exit 1; }
	# CDE installs under /usr/dt (configure's default prefix, and the
	# installation top it compiles in); the package keeps it in /opt/amix/dt,
	# with /usr/dt a link to it
	[ -d "$DEST/usr/dt" ] || { echo "[FAIL] make install wrote no /usr/dt" >&2; exit 1; }
	mkdir -p "$DEST/opt/amix"
	mv -- "$DEST/usr/dt" "$DEST/opt/amix/dt"
	ln -s /opt/amix/dt "$DEST/usr/dt"
	find "$DEST" -name '*.la' -type f -exec rm -f -- {} +
	# the static build: no program NEEDs a shared libjpeg, libregex or libstdc++
	if [ "$CDE_VARIANT" != shared ]; then
		_dl=$(cd "$DEST" && find . -type f -perm -u+x | while read -r _f; do
			"$READELF" -d "$DEST/$_f" 2>/dev/null | grep -q 'NEEDED.*lib\(jpeg\|regex\|stdc++\)' && echo "${_f#.}"; done || :)
		[ -z "$_dl" ] || { echo "[FAIL] the static build NEEDs a shared libjpeg, libregex or libstdc++:" $_dl >&2; exit 1; }
	fi
	if [ "$CDE_VARIANT" = shared ]; then
		_ld=$DEST$PREFIX/lib
		# the SVR4 layout for libtool's libraries: the file a program NEEDs (the
		# soname, libfoo.so.N) is the library and libfoo.so the one link to it
		for _f in $(cd "$_ld" && ls lib*.so.*.* 2>/dev/null); do
			[ -f "$_ld/$_f" ] && [ ! -L "$_ld/$_f" ] || continue
			_sn=$("$READELF" -d "$_ld/$_f" | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p')
			[ -n "$_sn" ] && [ "$_sn" != "$_f" ] || continue
			rm -f -- "${_ld:?}/${_sn:?}"; mv -- "$_ld/$_f" "$_ld/$_sn"
			_b=${_sn%%.so.*}.so; rm -f -- "${_ld:?}/${_b:?}"; ln -s "$PREFIX/lib/$_sn" "$_ld/$_b"
		done
		# libtool's remaining .so links are relative: the stock pkgadd mangles those
		for _l in $(cd "$DEST" && find ".$PREFIX/lib" -type l); do
			_t=$(readlink "$DEST/$_l"); case $_t in /*) continue;; esac
			rm -- "${DEST:?}/${_l:?}" && ln -s "$(dirname "${_l#.}")/$_t" "$DEST/$_l"
		done
		# every shared library and dynamic program: library names first in .dynstr
		# (gcc14-cross-amix tools/check-dynstr-order.py) and no text relocations
		_dy=$(cd "$DEST" && find . -type f \( -name '*.so.*' -o -perm -u+x \) | while read -r _f; do
			"$READELF" -d "$DEST/$_f" 2>/dev/null | grep -q NEEDED && echo "$DEST/$_f"; done | LC_ALL=C sort)
		[ -n "$_dy" ] || { echo "[FAIL] the shared variant staged no dynamic objects" >&2; exit 1; }
		python3 -I "$G14TOOLS/check-dynstr-order.py" $_dy > "$BUILD/dynstr.log" 2>&1 || {
			tail -20 "$BUILD/dynstr.log" >&2; echo "[FAIL] check-dynstr-order" >&2; exit 1; }
		echo "  check-dynstr-order: $(echo "$_dy" | wc -l) dynamic objects clean"
		# text relocations: named, not failed (GCC's static C++ runtime and Amix's
		# static libm have no PIC form; README, Shared variant); anything else fails
		python3 -I "$HERE/textrel-report.py" "$READELF" "$NM" $_dy > "$BUILD/textrel.log" || exit 1
		cat "$BUILD/textrel.log"
		! grep -q "^    other:" "$BUILD/textrel.log" || {
			echo "[FAIL] text relocations from an unexpected source (above)" >&2; exit 1; }
	fi
	# the programs are linked statically: the licence of each library in
	# them ships beside CDE's own COPYING (README, Licence)
	dd=$DEST/opt/amix/dt/doc
	mkdir -p "$dd/x11r6.3" "$dd/motif" "$dd/libjpeg" "$dd/regex" "$dd/compat"
	cp "$XROOT/doc/x11r63/LICENSE" "$XROOT/doc/x11r63/COPYRIGHT" "$dd/x11r6.3/"
	cp "$MROOT/doc/motif/COPYING" "$dd/motif/"
	cp "$JROOT/doc/libjpeg/README" "$dd/libjpeg/"
	cp "$RROOT/doc/regex/COPYRIGHT" "$dd/regex/"
	cp "$HERE/../LICENSE" "$dd/compat/LICENSE"
	chmod 0644 "$dd"/*/*
	# manual pages (README): sections 1 and 1m into /opt/amix/man with
	# whatis.d/cde (docs/man-pages.md); the reference sections 3, 4 and 5
	# stay whole in CDE's tree, share/man, under upstream's names, where
	# CDE's own link /usr/dt/man (its man directory for dtsearchpath) leads
	m=$DEST$PREFIX/share/man
	. "$HERE/../tools/manpages.sh"
	for s in 1 1m; do
		for f in "$m/man$s"/*; do
			[ -f "$f" ] || continue
			amix_man "$f" "$s"
			rm -f -- "${f:?}"
		done
		rmdir -- "$m/man$s"
	done
	amix_man "$HERE/man/cde-rpc.1m" 1m
	# upstream's ttsnoop.6 is the page of the TeleUse ttsnoop this one replaced (its
	# one option, -t, is not this ttsnoop's); ttsnoop(1) is ours
	rm -f -- "${m:?}/man6/ttsnoop.6"
	rmdir -- "$m/man6"
	# pages upstream has but does not install, and ours for the programs it
	# has none for (README, Manual pages); one page for dtopen's five names
	amix_man "$TREE/lib/tt/bin/ttauth/ttauth.man" 1 ttauth
	for f in Xsession dtdbcache dtdspmsg dterror.ds dtlpsetup dtopen dtsrclean dtsrdelete; do
		amix_man "$HERE/man/$f.1" 1
	done
	amix_man "$HERE/man/dtprintegrate.1m" 1m
	# App Builder: upstream's page for dtbuilder, ours for its code generator and ttsnoop
	amix_man "$TREE/programs/dtappbuilder/src/ab/dtbuilder.1" 1
	amix_man "$HERE/man/dtcodegen.1" 1
	amix_man "$HERE/man/ttsnoop.1" 1
	for f in dtopen_image dtopen_pdf dtopen_ps dtopen_video; do
		amix_man_alias $f 1 dtopen
	done
	# the scripts installed under a suffixed name, by their pages' names
	amix_man_alias dthelpgen.dtsh 1 dthelpgen
	amix_man_alias dthelpprint.sh 1 dthelpprint
	amix_man_alias rpc.ttdbserver 1m ttdbserver
	amix_man_whatis
	find "$m" -type f -exec chmod 0644 {} +
	# the boot script of the RPC servers, off unless rc.conf turns them on
	# (cde-rpc(1M)): one file under three names, as rc.subr(1M) wants
	mkdir -p "$DEST/etc/init.d" "$DEST/etc/rc0.d" "$DEST/etc/rc1.d" "$DEST/etc/rc2.d"
	cp "$HERE/files/cde-rpc" "$DEST/etc/init.d/cde-rpc"
	ln "$DEST/etc/init.d/cde-rpc" "$DEST/etc/rc2.d/S78cde-rpc"
	ln "$DEST/etc/init.d/cde-rpc" "$DEST/etc/rc0.d/K38cde-rpc"
	ln "$DEST/etc/init.d/cde-rpc" "$DEST/etc/rc1.d/K38cde-rpc"
	chmod 0444 "$DEST/etc/init.d/cde-rpc"
	# dtterm's terminfo entry: the box's own tic's output for this
	# dtterm.ti, kept in terminfo/ (README: where from, how to make it
	# again); a changed dtterm.ti fails here until the entry is remade
	ti=$(sha256sum "$TREE/programs/dtterm/dtterm.ti" | cut -c1-64)
	[ "$ti" = "$DTTERM_TI_SHA256" ] || {
		echo "[FAIL] dtterm.ti changed ($ti, terminfo/d/dtterm is for $DTTERM_TI_SHA256): compile it again with the box's tic" >&2
		exit 1; }
	mkdir -p "$DEST/usr/share/lib/terminfo/d"
	cp "$HERE/terminfo/d/dtterm" "$DEST/usr/share/lib/terminfo/d/dtterm"
	chmod 0644 "$DEST/usr/share/lib/terminfo/d/dtterm"
}
