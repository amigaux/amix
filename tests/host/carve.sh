#!/bin/sh
# carve.sh -- tools/carve.py on the stock k30 objects (S5-04): the core
# tier it computes is abi/k30/core.list exactly, and each of ufs and s5,
# wrapped, builds with the k30 kit and passes modcheck as a core-tier boot
# module carrying fs= and the build id.  Inputs are not part of this
# repository: AX_STOCK (the stock usr/sys tree), AX_NAMELIST (a k30
# kernel's namelist, unix.sym).  Skipped when unset; the module build is
# skipped when the cross tools are not on PATH.
set -e
B=${B:-build}
[ -n "$AX_STOCK" ] && [ -n "$AX_NAMELIST" ] || { echo "carve: AX_STOCK/AX_NAMELIST unset, skipped"; exit 0; }
T=$B/carve; rm -rf "${T:?}"; mkdir -p $T
python3 -I tools/carve.py corelist --ddi abi/k30/ddi.list --namelist "$AX_NAMELIST" --tree "$AX_STOCK" \
	"$AX_STOCK/fs/ufs/exp" "$AX_STOCK/fs/s5/exp" > $T/core.list 2> $T/corelist.out
sed 's/#.*//' abi/k30/core.list | awk 'NF' | cmp -s - $T/core.list ||
	{ echo "carve: abi/k30/core.list differs from the carve's core tier" >&2; diff $T/core.list abi/k30/core.list >&2; exit 1; }
grep -q "^rootvp data 2$" $T/core.list	# the one COMMON the rest of the tree shares
! grep -q "^\(ihead\|hinode\|inode\|updlock\) " $T/core.list	# private: they go with the modules
echo "carve: $(cat $T/corelist.out | sed 's/^carve: //')"
command -v m68k-cbm-sysv4-gcc >/dev/null || { echo "carve: no cross tools on PATH, module build skipped"; exit 0; }
[ -d $B/kit/k30 ] || { echo "carve: no $B/kit/k30 (make kit), module build skipped"; exit 0; }
for fs in ufs s5; do
	python3 -I tools/carve.py wrap --fs $fs --obj "$AX_STOCK/fs/$fs/exp" --filesys "$AX_STOCK/master.d/filesys.o" \
		--build 68030-261101-01 $T/$fs > /dev/null
	make -s -C $T/$fs KIT=$PWD/$B/kit/k30 > $T/$fs.out 2>&1 || { cat $T/$fs.out >&2; exit 1; }
	grep -q "modcheck: $fs: ok (k30.1.2, boot, " $T/$fs.out
	for k in tier=core build=68030-261101-01 fs=$fs match=always unload=never class=boot; do
		strings -a $T/$fs/build/k30/mod.d/$fs | grep -qx "$k" || { echo "carve: $fs: no $k in .moddata" >&2; exit 1; }
	done
	echo "carve: $fs wrapped: $(sed -n "s/^modcheck: $fs: ok (k30.1.2, boot, \(.*\))/\1/p" $T/$fs.out)"
done
