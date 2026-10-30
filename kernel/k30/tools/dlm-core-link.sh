#!/bin/bash
# dlm-core-link.sh -- the module core spliced into a finished 030 ET_REL kernel (kernel/dlm
# docs/plan/stage-3-kernel-brief.md §3, S3-21): the kernel-build steps that need nothing kernel/dlm still owes.
#
#   tools/dlm-core-link.sh ETREL OUT --dlm DIR [--line k30] [--kabi k30.1.0] [--pin PIN]
#                          [--stub-providers]
#
# ETREL is the linked kernel before elf2brel (build-cross-kernel.sh's $BUILD/unix, with --kinfo's cdevsw row).
# OUT is a work directory; OUT/unix is the spliced ET_REL, OUT/steps.tsv one line per step (step, PASS|FAIL|OWED,
# what). The steps, as the brief numbers them:
#   1  stage: DIR/core/upstream copied, DIR/core/series applied with patch -p1
#   2  mkoffs: the 19 layouts measured with the kernel compiler (m68k-cbm-sysv4-gcc $AMIX_KERNEL_CFLAGS)
#   3  mkreg: the major registry from DIR/abi/registry/majors
#   4  the core objects: every dlm*.c with -DDLM_KABI/-DDLM_PIN, every dlm_*.s (not dlmksym.s),
#      DIR/loader/common sha256.c/crc32.c and core/plat/amiga.c + core/plat/<line>/*.c at the loader's flags
#      (OWED while DIR has no core/plat/<line>); no warning beyond the stock headers' own. DLM_CORE_CFLAGS in the
#      environment is added to the dlm*.c compiles (a measurement build, e.g. -DDLM_U1; never a kernel of record)
#   5  DIR/tools/mkident.py --asm (OWED while DIR has no mkident.py); with a mkident that takes ROOT (C4-4 v4), the
#      base's built-in root controllers (the sidecar's root= list) as dlm_static_root
#   6  mkksym -k KABI -a from DIR/abi/<line>/{ddi,core}.list (lines up to the claim's minor, C3-2 v2), assembled
#   7  the splice (m68k-elf-objcopy, gcc14-cross-amix): every name the core defines that the base defines too
#      (dmainit, execsw, fmodsw, scrcon_put, aciabintr) weakened in the base, and every __amix_<name> the core refers to added
#      as an alias of the base's <name> (the stock body or table it calls or copies); then ld -r base + core + ksym
#      (+ ident)
#      --stub-providers: every listed name still undefined after the splice gets an `rts`/`.long 0` stub, as
#      kernel/dlm's `make core` does -- a dry run only, never a kernel to boot (a stub crashes the first caller)
#   7h the halt hook (S4-21, core patch 0030): when dlm.o defines dlm_halt, tools/dlm-halt030.s joins the ld -r and
#      tools/patch-dlm-halt030.py retargets mdboot's jsr haltsys / jsr rtnfirm to its shims (dlm_halt first);
#      a core without dlm_halt links as before; and when dlm.o defines dlm_marc_root (S4-23, core patch 0034),
#      rth1_mountroot's call of the empty rth1_nomarc (tools/rth1-nomarc030.s) is retargeted to it by the port's
#      patch_dlm_call.py beside rth1.c (--rth1-dir); a core with the hook and a base without the call FAILs
#   9  mkksym -f (the sizes; fails on a listed name undefined or of the other kind); mkident --fill (OWED)
#   9b DIR/tools/mkabi.py --check DIR/abi/<line>/abi-<kabi>.txt on the final ET_REL (C3-3 §4): OUT/abi.txt holds
#      its abi= line, or what moved (FAIL); OWED while DIR has no mkabi.py
#  10  the gate: DIR/tools/ksymgate.py with the loader's relocator (DIR/tests/host/axrel.c), on the ET_REL
#   8  is the kernel tree's and comes in with the base: rth1.c -DRTH1_DLM (dlm_marc_post after vfs_mountroot) and
#      kinfo030.c -DKINFO_DLM (the module list, kabi k30.1.0), build-cross-kernel.sh --dlm. Exit 0 when no step FAILs (OWED steps are not failures), 1 otherwise.
set -uo pipefail
KT="$(cd "$(dirname "$0")/.." && pwd)"
ETREL="${1:?ETREL}"; OUT="${2:?OUT}"; shift 2
DLM="$KT/../dlm"; LINE=k30; KABI=k30.1.0; PIN=gcc-2.7.2.3-8949028; STUB=0
while [ $# -gt 0 ]; do case "$1" in
	--dlm) DLM="$2"; shift 2;; --line) LINE="$2"; shift 2;; --kabi) KABI="$2"; shift 2;; --pin) PIN="$2"; shift 2;;
	--stub-providers) STUB=1; shift;; --rth1-dir) RTH1_DIR="$2"; shift 2;;
	*) echo "dlm-core-link: unknown option $1" >&2; exit 2;; esac; done
RTH1_DIR="${RTH1_DIR:-}"
GCA="${GCA:?dlm-core-link: set GCA to gcc-cross-amix's build/ directory (toolchain/README.md)}"; G14="${G14:-}"
. "$GCA/env.sh"; [ -z "$G14" ] || PATH="$PATH:$G14/prefix/bin"; export PATH
rm -rf "$OUT"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"; C="$OUT/core"; O="$OUT/obj"; mkdir -p "$O"
ST="$OUT/steps.tsv"; : > "$ST"; fails=0
step() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$ST"; echo "  [$2] step $1: $3"; [ "$2" != FAIL ] || fails=$((fails + 1)); }
KCC="m68k-cbm-sysv4-gcc $AMIX_KERNEL_CFLAGS -Wall -I$C/include -I$C"

# 1
rm -rf "$C"; cp -R "$DLM/core/upstream" "$C"; bad=""
while read -r p; do case "$p" in \#*|"") continue;; esac
	patch -p1 -s -d "$C" < "$DLM/core/patches/$p" > "$OUT/patch.log" 2>&1 || { bad="$p"; break; }; done < "$DLM/core/series"
[ -z "$bad" ] && step 1 PASS "core staged at $(cat "$DLM/core/upstream.pin" 2>/dev/null | head -1 | cut -c1-40), $(grep -vc '^#\|^$' "$DLM/core/series") patches applied" \
	|| { step 1 FAIL "patch $bad: $(head -2 "$OUT/patch.log" | tr '\n' ' ')"; exit 1; }
# 2
if sh "$C/tools/mkoffs" m68k-cbm-sysv4-gcc $AMIX_KERNEL_CFLAGS -I"$C/include" > "$C/dlm_offs.h" 2> "$OUT/mkoffs.log"; then
	step 2 PASS "mkoffs: $(grep -c '^#define' "$C/dlm_offs.h") layout values measured"
else step 2 FAIL "mkoffs: $(head -3 "$OUT/mkoffs.log" | tr '\n' ' ')"; fi
# 3
sh "$C/tools/mkreg" "$DLM/abi/registry/majors" > "$C/dlmreg.c" 2> "$OUT/mkreg.log" \
	&& step 3 PASS "mkreg: dlmreg.c $(wc -l < "$C/dlmreg.c") lines" || step 3 FAIL "mkreg: $(head -2 "$OUT/mkreg.log" | tr '\n' ' ')"
# 4
: > "$OUT/kobj.warn"; objs=""; cfail=""
# every kernel source the staged core has: its dlm*.c (dlmreg.c from step 3; dlm_ddi.c, dlm_intr.c from the
# provider patches) and dlm_*.s -- not dlmksym.s, the empty block step 6 replaces
CSRC=$(cd "$C" && ls dlm*.c | sed 's/\.c$//' | tr '\n' ' ')
ASRC=$(cd "$C" && ls dlm_*.s | sed 's/\.s$//' | tr '\n' ' ')
for f in $CSRC; do
	$KCC ${DLM_CORE_CFLAGS:-} -DDLM_KABI=\"$KABI\" -DDLM_PIN=\"$PIN\" -c "$C/$f.c" -o "$O/$f.o" 2>> "$OUT/kobj.warn" && objs="$objs $O/$f.o" || cfail="$cfail $f"; done
for f in sha256 crc32; do
	m68k-cbm-sysv4-gcc -O2 -m68020 -fno-builtin -fomit-frame-pointer -Wall -I"$DLM/loader/common" \
		-c "$DLM/loader/common/$f.c" -o "$O/$f.o" 2>> "$OUT/kobj.warn" && objs="$objs $O/$f.o" || cfail="$cfail $f"; done
for f in $ASRC; do m68k-cbm-sysv4-gcc -c "$C/$f.s" -o "$O/$f.o" && objs="$objs $O/$f.o" || cfail="$cfail $f"; done
owed4=""
# the platform hook, as kernel/dlm's make core builds it: core/plat/amiga.c (both lines) and core/plat/<line>/*.c,
# at the loader's flags against loader/common
if [ -d "$DLM/core/plat/$LINE" ]; then
	for f in "$DLM/core/plat"/*.c "$DLM/core/plat/$LINE"/*.c; do [ -f "$f" ] || continue; b=$(echo "${f#$DLM/core/plat/}" | sed 's#/#-#g; s#\.c$##')
		m68k-cbm-sysv4-gcc -O2 -m68020 -fno-builtin -fomit-frame-pointer -Wall -I"$DLM/loader/common" -c "$f" -o "$O/plat-$b.o" \
			2>> "$OUT/kobj.warn" && objs="$objs $O/plat-$b.o" || cfail="$cfail plat/$b"; done
else owed4="core/plat/$LINE"; fi
other=$(grep -v 'types.h:182\|In file included\|^ *from ' "$OUT/kobj.warn" | grep . || true)
if [ -n "$cfail" ]; then step 4 FAIL "compile failed:$cfail"
elif [ -n "$other" ]; then step 4 FAIL "warnings beyond the stock headers': $(echo "$other" | head -3 | tr '\n' ' ')"
else step 4 PASS "core objects compiled (kabi $KABI, pin $PIN${DLM_CORE_CFLAGS:+, $DLM_CORE_CFLAGS}): $(echo $objs | wc -w) objects, no warnings of their own"; fi
[ -z "$owed4" ] || step 4 OWED "$owed4 is kernel/dlm's (brief §1: cputype, the DMA services, dev_kvmap, plat_dmainit)"
m68k-cbm-sysv4-ld -r -o "$O/dlm.o" $objs && echo "  dlm.o $(m68k-elf-size "$O/dlm.o" | awk 'NR==2{print $1 "+" $2 "+" $3}') text+data+bss"
# 5
IDENT=""
if [ -f "$DLM/tools/mkident.py" ]; then
	# a core whose mkident takes ROOT (C4-4 v4): dlm_static_root names the base's built-in root controllers, the
	# sidecar's root= list (sd.c's scsicard rows), so marc_root skips a root module for any of them
	ROOT=""; grep -q '\[ROOT\]' "$DLM/tools/mkident.py" && ROOT="$(python3 -c "import importlib.util as u
s = u.spec_from_file_location('ks', '$KT/tools/kabi-sidecar030.py'); m = u.module_from_spec(s); s.loader.exec_module(m)
print(','.join(m.root_keys(m.kc.Kernel('$ETREL'))))")" && [ -n "$ROOT" ] || ROOT=""
	python3 "$DLM/tools/mkident.py" --asm "$LINE" "$KABI" 0x60000 ${ROOT:+"$ROOT"} > "$OUT/ident.s" 2> "$OUT/mkident.log" \
		&& m68k-cbm-sysv4-as -o "$O/ident.o" "$OUT/ident.s" && IDENT="$O/ident.o" && step 5 PASS "mkident --asm: ident.o${ROOT:+, dlm_static_root \"$ROOT\"}" \
		|| step 5 FAIL "mkident --asm: $(head -2 "$OUT/mkident.log" | tr '\n' ' ')"
else step 5 OWED "tools/mkident.py is not in kernel/dlm yet (brief §1): no AXK1 record, no arena block"; fi
# 6
HCC="${HOSTCC:-cc} -std=gnu89 -O -Wall -Wno-parentheses -Wno-unused-but-set-variable"
$HCC -DDLM_TOOL -I"$C" -I"$C/include" -o "$OUT/mkksym" "$C/tools/mkksym.c" "$C/dlm_sym.c" > "$OUT/mkksym-build.log" 2>&1 \
	|| { step 6 FAIL "host mkksym: $(head -2 "$OUT/mkksym-build.log" | tr '\n' ' ')"; exit 1; }
L="$DLM/abi/$LINE/ddi.list"; LC="$DLM/abi/$LINE/core.list"
"$OUT/mkksym" -k "$KABI" -a "$L" -a "$LC" > "$OUT/ksym.s" 2> "$OUT/ksym.log" && m68k-cbm-sysv4-as -o "$O/ksym.o" "$OUT/ksym.s" \
	&& step 6 PASS "mkksym -k $KABI -a: $(sed 's/^mkksym: //' "$OUT/ksym.log" | tr '\n' ' ')" || step 6 FAIL "mkksym -a: $(cat "$OUT/ksym.log")"
# 7
sym() { m68k-elf-readelf -sW "$1" | awk -v n="$2" '$8==n && $7!="UND" {print $7, $2; exit}'; }
shndx_name() { m68k-elf-readelf -SW "$1" | awk -v i="$2" '{gsub(/\[ */,"[")} $1=="["i"]" {print $2; exit}'; }
m68k-elf-nm "$ETREL" | awk 'NF==3 && $2 ~ /^[TDB]$/ {print $3}' | sort -u > "$OUT/base.defs"
m68k-elf-nm "$O/dlm.o" | awk 'NF==3 && $2 ~ /^[TDB]$/ {print $3}' | sort -u > "$OUT/core.defs"
weak=$(comm -12 "$OUT/base.defs" "$OUT/core.defs"); add=""; alias=""
for a in $(m68k-elf-nm -u "$O/dlm.o" | awk '$2 ~ /^__amix_/ {print $2}' | sort -u); do
	t=${a#__amix_}; read -r ndx val <<< "$(sym "$ETREL" "$t")"
	[ -n "${ndx:-}" ] || { step 7 FAIL "the core refers to $a but the base has no $t"; exit 1; }
	kind=object; [ "$(shndx_name "$ETREL" "$ndx")" != .text ] || kind=function
	add="$add --add-symbol $a=$(shndx_name "$ETREL" "$ndx"):0x$val,global,$kind"; alias="$alias $a"; done
if m68k-elf-objcopy $(for n in $weak; do echo "--weaken-symbol=$n"; done) $add "$ETREL" "$O/base.o" 2> "$OUT/objcopy.log"; then
	# elf2brel fuses text || rodata || data with no padding (elf2brel.c's layout), and the core brings the first
	# .rodata into a K030 kernel (its loader-flag objects): an odd-sized .rodata would put all of .data, AXK1 and
	# the arena included, at an odd offset. The core's .rodata is folded into .data (the brief's §3a (b)). The
	# K030 base has a .rodata of its own (the kit's freshly compiled objects: 5956 bytes on K030-U r7, 4-aligned
	# by chance), so the last input, a zero-size .rodata aligned to 4, rounds the total; mkident --fill and
	# elf2brel both lay out text, rodata, data.
	m68k-elf-objcopy --rename-section .rodata=.data,alloc,load,data,contents "$O/dlm.o" "$O/dlm-f.o"
	printf '\t.section\t.rodata\n\t.align\t4\n' > "$OUT/rodata-pad.s"; m68k-cbm-sysv4-as -o "$O/rodata-pad.o" "$OUT/rodata-pad.s"
	parts="$O/base.o $O/dlm-f.o $O/ksym.o $IDENT"
	# a core that defines dlm_halt needs the shims: never link it without them (that is a different kernel)
	HALT=""
	if m68k-elf-nm "$O/dlm.o" | awk '$2=="T" && $3=="dlm_halt" {f=1} END{exit !f}'; then
		m68k-cbm-sysv4-as -o "$O/halt.o" "$KT/tools/dlm-halt030.s" && HALT="$O/halt.o" && parts="$parts $HALT" \
			|| { step 7 FAIL "halt hook: dlm.o defines dlm_halt but tools/dlm-halt030.s did not assemble"; exit 1; }
	fi
	parts="$parts $O/rodata-pad.o"
	m68k-cbm-sysv4-ld -r -o "$OUT/unix.pre" $parts 2> "$OUT/ld.log"
	und=$(m68k-elf-nm -u "$OUT/unix.pre" | awk '{print $NF}' | grep -vx 'etext\|edata\|end' || true)
	listed_und=$(awk '!/^#/ && NF {print $1, $2}' "$L" "$LC" | while read -r n k; do m68k-elf-nm "$OUT/unix.pre" | awk -v n="$n" '$NF==n && $(NF-1) ~ /^[A-Za-z]$/ && $(NF-1) !~ /^[Uw]$/ {f=1} END{exit !f}' || echo "$n $k"; done)
	# without mkident the core's weak dlm_ident stays undefined, and the loader's relocator refuses a relocation
	# against an undefined name (axrel error -4): the dry run stands in a zero AXK1 block (C3-3: 64 bytes, .data)
	[ -n "$IDENT" ] || [ "$STUB" = 0 ] || listed_und="$(printf '%s\n%s' "$listed_und" "dlm_ident ident64" | grep .)"
	# and what the core itself needs from the platform half (core/plat/<line>: plat_dmainit, ...) when it is owed
	[ "$STUB" = 0 ] || [ -z "$owed4" ] || listed_und="$(printf '%s\n' "$listed_und"; m68k-elf-nm -u "$OUT/unix.pre" | \
		awk '$1=="U" {print $2}' | grep -vx 'etext\|edata\|end' | while read -r n; do echo "$listed_und" | grep -q "^$n " || echo "$n func"; done)"
	listed_und="$(echo "$listed_und" | grep . || true)"
	if [ -n "$listed_und" ] && [ "$STUB" = 1 ]; then
		echo "$listed_und" | awk '$2=="func" {printf "\t.text\n\t.globl\t%s\n%s:\n\trts\n", $1, $1}
			$2=="data" {printf "\t.data\n\t.globl\t%s\n%s:\n\t.long\t0\n", $1, $1}
			$2=="ident64" {printf "\t.data\n\t.balign\t4\n\t.globl\t%s\n%s:\n\t.space\t64\n", $1, $1}' > "$OUT/stubs.s"
		m68k-cbm-sysv4-as -o "$O/stubs.o" "$OUT/stubs.s"; parts="$parts $O/stubs.o"
		m68k-cbm-sysv4-ld -r -o "$OUT/unix" $parts 2>> "$OUT/ld.log"
		echo "$listed_und" | awk '{print $1}' > "$OUT/stubbed.txt"
	else cp "$OUT/unix.pre" "$OUT/unix"; fi
	if [ -n "$HALT" ]; then
		python3 "$KT/tools/patch-dlm-halt030.py" "$OUT/unix" > "$OUT/halt.log" 2>&1 \
			&& step 7 PASS "halt hook: $(grep -c '\[ok\]   mdboot' "$OUT/halt.log") mdboot call(s) retargeted; $(tail -1 "$OUT/halt.log" | sed 's/^ *\[ok\] *//')" \
			|| step 7 FAIL "halt hook: $(tail -2 "$OUT/halt.log" | tr '\n' ' ')"
	fi
	if m68k-elf-nm "$O/dlm.o" | awk '$2=="T" && $3=="dlm_marc_root" {f=1} END{exit !f}'; then
		if ! m68k-elf-nm "$OUT/unix" | awk '$2=="T" && $3=="rth1_nomarc" {f=1} END{exit !f}'; then
			step 7 FAIL "marc_root: the core has dlm_marc_root but the base has no rth1_nomarc (the port's rth1.c f0a6011 on, -DRTH1_DLM)"
		elif [ ! -f "$RTH1_DIR/patch_dlm_call.py" ]; then
			step 7 FAIL "marc_root: no patch_dlm_call.py beside rth1.c (--rth1-dir '$RTH1_DIR')"
		elif python3 "$RTH1_DIR/patch_dlm_call.py" "$OUT/unix" rth1_mountroot rth1_nomarc dlm_marc_root > "$OUT/marc.log" 2>&1 \
			&& python3 "$RTH1_DIR/patch_dlm_call.py" --check "$OUT/unix" rth1_mountroot rth1_nomarc dlm_marc_root >> "$OUT/marc.log" 2>&1; then
			step 7 PASS "marc_root: rth1_mountroot's rth1_nomarc call -> dlm_marc_root, before rth1_apply ($(tail -1 "$OUT/marc.log" | sed 's/^ *//' | cut -c1-90))"
		else step 7 FAIL "marc_root: $(tail -2 "$OUT/marc.log" | tr '\n' ' ')"; fi
	fi
	und=$(m68k-elf-nm -u "$OUT/unix" | awk '$1=="U" {print $NF}' | grep -vx 'etext\|edata\|end' || true)
	wu=$(m68k-elf-nm -u "$OUT/unix" | awk '$1=="w" {print $NF}' | tr '\n' ' ')
	[ -z "$wu" ] || step 7 FAIL "weak but undefined (the loader's relocator refuses a relocation against them): $wu"
	w=$(m68k-elf-nm "$OUT/unix" | awk '$2=="W" || $2=="V" {print $3}' | tr '\n' ' ')
	if [ -s "$OUT/ld.log" ]; then step 7 FAIL "ld -r: $(head -3 "$OUT/ld.log" | tr '\n' ' ')"
	elif [ -n "$und" ]; then step 7 FAIL "undefined after the splice: $(echo $und)"
	else step 7 PASS "splice: weakened in the base: $(echo $weak); aliased:$alias; ld -r with dlm.o + ksym.o${IDENT:+ + ident.o}; weak left: ${w:-none}"; fi
	# step 8 came in with the base: the core's post call must be bound (rth1.c -DRTH1_DLM)
	if m68k-elf-nm "$ETREL" | awk '$1=="U" && $2=="dlm_marc_post" {f=1} END{exit !f}'; then
		step 8 PASS "the base calls dlm_marc_post (rth1_mountroot, RTH1_DLM) and kinfo lists modules: $(m68k-elf-nm "$ETREL" | awk '$1=="U" && $2=="dlm_kinfo_list" {print "dlm_kinfo_list bound"}')"
	elif [ "$STUB" = 1 ]; then step 8 OWED "the base never calls dlm_marc_post: a static base (rth1.c without -DRTH1_DLM), dry run"
	else step 8 FAIL "the base never calls dlm_marc_post (rth1.c without -DRTH1_DLM?)"; fi
	secsz() { m68k-elf-readelf -SW "$OUT/unix" | awk -v s="$1" '{for (i = 1; i <= NF; i++) if ($i == s) {print strtonum("0x" $(i+4)); exit}}'; }
	ts=$(secsz .text); rs=$(secsz .rodata); ds=$((${ts:-0} + ${rs:-0}))
	[ $((ds % 4)) = 0 ] && step 7 PASS "layout: .text $ts + .rodata ${rs:-0}: .data starts at $ds in elf2brel's image (4-aligned)" \
		|| step 7 FAIL "layout: .data would start at $ds in elf2brel's image, not 4-aligned"
	[ ! -s "$OUT/stubbed.txt" ] || step 7 OWED "stubbed (providers to come): $(tr '\n' ' ' < "$OUT/stubbed.txt")"
	[ -z "$listed_und" ] || [ "$STUB" = 1 ] || step 7 FAIL "listed but undefined (no --stub-providers): $(echo "$listed_und" | awk '{printf "%s ", $1}')"
else step 7 FAIL "objcopy: $(head -2 "$OUT/objcopy.log" | tr '\n' ' ')"; exit 1; fi
# 9
"$OUT/mkksym" -f "$OUT/unix" > "$OUT/fill.log" 2>&1 && step 9 PASS "mkksym -f: $(sed 's#.*: ##' "$OUT/fill.log" | tr '\n' ' ')" \
	|| step 9 FAIL "mkksym -f: $(head -3 "$OUT/fill.log" | tr '\n' ' ')"
[ -n "$IDENT" ] && { python3 "$DLM/tools/mkident.py" --fill "$OUT/unix" > "$OUT/ident-fill.txt" 2>&1 && step 9 PASS "mkident --fill" || step 9 FAIL "mkident --fill: $(head -2 "$OUT/ident-fill.txt")"; } \
	|| step 9 OWED "mkident --fill (tools/mkident.py not in kernel/dlm yet)"
# 9b (after every size-changing step: the fill writes values, not sizes)
if [ -f "$DLM/tools/mkabi.py" ]; then
	if python3 "$DLM/tools/mkabi.py" --check "$DLM/abi/$LINE/abi-$KABI.txt" "$OUT/unix" "$L" "$C/dlm_offs.h" > "$OUT/abi.txt" 2>&1 \
		&& grep -q '^abi=[0-9a-f]\{64\}$' "$OUT/abi.txt"; then step 9 PASS "mkabi --check: $(cat "$OUT/abi.txt")"
	else step 9 FAIL "mkabi --check: $(head -4 "$OUT/abi.txt" | tr '\n' ' ')"; fi
else step 9 OWED "tools/mkabi.py is not in kernel/dlm yet (C3-3 §4): no abi="; fi
# 10
${HOSTCC:-cc} -O2 -I"$DLM/loader/common" -o "$OUT/axrel" "$DLM/tests/host/axrel.c" "$DLM/loader/common/rel.c" > "$OUT/axrel-build.log" 2>&1 \
	|| { step 10 FAIL "host axrel: $(head -2 "$OUT/axrel-build.log")"; exit 1; }
if python3 "$DLM/tools/ksymgate.py" "$OUT/axrel" "$OUT/unix" "$L" "$LC" > "$OUT/gate.log" 2>&1; then
	step 10 PASS "ksymgate: $(grep -c '^PASS' "$OUT/gate.log") checks pass on the ET_REL"
else step 10 FAIL "ksymgate: $(grep '^FAIL' "$OUT/gate.log" | head -3 | tr '\n' ' ')"; fi
echo "dlm-core-link: $(cut -f2 "$ST" | sort | uniq -c | tr '\n' ' ')-> $OUT/unix"
[ $fails = 0 ]
