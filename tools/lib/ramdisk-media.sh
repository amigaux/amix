# ramdisk-media.sh -- sourced by tools/build-ramdisk-cd.sh and tools/build-ramdisk-floppy.sh:
# the staging roots the RAM-disk media's generations are composed from (amix-dlm C4-3).
#
# Per line, a staging root gets the loader, the kernel and the line's modules from the
# medium's kernel-space catalog (work/l11/kpkg, tools/build-l11-inputs.sh), installed by the
# host apkg of that build through a pkgadd that only unpacks (device nodes are not needed to
# compose). The caller then runs `kbootset -R stage-LINE media --cd|--floppy ... --ramdisk`.
#   k46: ramdisk, z3660scsi and a4091 (root class: the disc sits on an A4091 in the rigs),
#        cdfs (boot class, from the image's /stand/gen/1/mod); rootfs ufs, 32 MiB assumed
#   k30: ramdisk and a4091, cdfs (boot class; kern30m links no static cdfs since -17);
#        rootfs s5, 64 MiB assumed (the k30 kernel is held to 64 MiB)
# K46_MODS / K30_MODS override the module lists. The caller defines die().

# rd_init WORKDIR -- the inputs checked, the unpacking pkgadd and the admin file written
rd_init() {
	W="$1"
	L11="${L11_IN:-$repo/work/l11}"
	B="$L11/dlm/build"; APKG="$L11/apkg/apkg-host"
	local f
	for f in "$B/kbootset" "$B/mkstore" "$B/lsstore" "$B/amix-cdboot" "$B/boot1.img" "$B/boot2.bin" \
	         "$APKG" "$L11/kpkg/catalog"; do
		[ -e "$f" ] || die "$f missing (tools/build-l11-inputs.sh --set tools/l11-set.conf)"
	done
	PKGTRANS="$ws/amix-packagemanager/heirloom/build-host/bin/pkgtrans"
	[ -x "$PKGTRANS" ] || die "no host pkgtrans at $PKGTRANS"
	K46_MODS="${K46_MODS:-ramdisk-k46 cdfs-k46 z3660scsi-k46 a4091-k46}"
	K30_MODS="${K30_MODS:-ramdisk-k30 cdfs-k30 a4091-k30}"
	mkdir -p "$W/bin"
	# the unpacking pkgadd apkg calls: files and directories into -R, the contents file kept
	cat > "$W/bin/pkgadd" <<P
#!/bin/bash
T=; F=; I=
while [ \$# -gt 0 ]; do case "\$1" in -R) T=\$2; shift 2;; -d) F=\$2; shift 2;; -a) shift 2;; -n) shift;; *) I=\$1; shift;; esac; done
U=\$(mktemp -d "$W/unpack.XXXXXX")
"$PKGTRANS" "\$F" "\$U" "\$I" >/dev/null 2>&1 || exit 1
C=\$T/var/sadm/install/contents; mkdir -p "\$(dirname "\$C")"; touch "\$C"
mkdir -p "\$T/var/sadm/pkg/\$I"; cp "\$U/\$I/pkginfo" "\$T/var/sadm/pkg/\$I/pkginfo"
while read -r part type class path mode owner group size cks mtime; do
	case "\$type" in
	d) mkdir -p "\$T\$path"; echo "\$path d \$class \$mode \$owner \$group \$I" >> "\$C" ;;
	f) mkdir -p "\$(dirname "\$T\$path")"; cp "\$U/\$I/root\$path" "\$T\$path"; chmod "\$mode" "\$T\$path"
	   echo "\$path f \$class \$mode \$owner \$group \$size \$cks \$mtime \$I" >> "\$C" ;;
	esac
done < "\$U/\$I/pkgmap"
rm -rf "\$U"
P
	chmod 0755 "$W/bin/pkgadd"
	printf 'mail=\ninstance=overwrite\naction=nocheck\n' > "$W/admin"
}

# rd_facts LINE -- FS and MEM for the line (see the header)
rd_facts() {
	case "$1" in
		k46) FS=ufs; MEM=33554432; MODS="$K46_MODS" ;;
		k30) FS=s5;  MEM=67108864; MODS="$K30_MODS" ;;
		*)   die "no line $1" ;;
	esac
}

# rd_stage LINE -- $W/stage-LINE: the loader, the line's kernel and modules
rd_stage() {
	local l=$1 t="$W/stage-$1"
	rd_facts "$l"
	rm -rf "$t" "$W/cache-$l"
	mkdir -p "$t/etc/default" "$t/var/apkg" "$t/var/kbootset" "$t/stand"
	printf 'bootset=manual\n' > "$t/etc/default/bootset"
	cat > "$W/apkg-$l.conf" <<C
repo=file://$L11/kpkg
cachedir=$W/cache-$l
admin=$W/admin
pkgadd=$W/bin/pkgadd
pkgrm=/bin/false
kbootset=$B/kbootset
C
	"$APKG" -c "$W/apkg-$l.conf" update > "$W/apkg-$l.log" 2>&1
	# shellcheck disable=SC2086
	"$APKG" -c "$W/apkg-$l.conf" -R "$t" install loader-amix "kernel-$l-m" $MODS >> "$W/apkg-$l.log" 2>&1 \
		|| { tail -5 "$W/apkg-$l.log" >&2; die "$l: apkg could not stage $MODS"; }
}

# rd_summary LINE SPEC -- one line: the kernel build, the rootfs and the modules with their class
rd_summary() {
	echo "$1: $(grep -E '^kernel-build' "$2"), rootfs $FS, modules:" \
	     "$(grep -E '^module ' "$2" | awk '{print $2 "(" $3 ")"}' | tr '\n' ' ')"
}
