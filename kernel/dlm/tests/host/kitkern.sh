#!/bin/sh
# kitkern.sh -- `modcheck.py --kernel KABI`: a kit against a kernel's
# sidecar (C3-3).  A kit with the repository's own abi texts, as mkkit.sh
# copies them, and sidecars written here: the same kabi and abi fits; a
# kit of a lower minor fits without the abi compared; each mismatch (abi
# at the same minor, the kernel's minor below the kit's, another line,
# family or major, another pin, a missing line) fails with its line.
# Run from the repository root.
set -e
B=${B:-build}
T=$B/kitkern
rm -rf $T && mkdir -p $T/kit
MC="python3 abi/tools/modcheck.py -k $T/kit"
cp abi/k46/abi-k46.1.3.txt $T/kit/abi.txt
printf 'LINE=k46\nKABI=k46.1.3\nKABI_MIN=k46.1.2\nPIN=gcc-2.7.2.3-8949028\n' > $T/kit/kit.conf
A3=$(sha256sum abi/k46/abi-k46.1.3.txt | cut -d' ' -f1)
A2=$(sha256sum abi/k46/abi-k46.1.2.txt | cut -d' ' -f1)
[ "$A3" != "$A2" ]
# side NAME KABI ABI [LINE [PIN]]: a sidecar with the lines --kernel reads
side() {
	printf 'kabi=%s\nline=%s\npin=%s\nbuild=68060-%s\nabi=%s\n' \
		"$2" "${4:-k46}" "${5:-gcc-2.7.2.3-8949028}" "$1" "$3" > $T/$1
}
# no NAME PATTERN: --kernel refuses the sidecar NAME, saying PATTERN
no() {
	if $MC --kernel $T/$1 > $T/$1.out 2>&1; then
		echo "kitkern: $1 accepted" >&2; cat $T/$1.out >&2; exit 1
	fi
	grep -q "$2" $T/$1.out || { echo "kitkern: $1 refused otherwise" >&2; cat $T/$1.out >&2; exit 1; }
}

side fits k46.1.3 $A3
$MC --kernel $T/fits | grep -qx "modcheck: kit k46.1.3 fits kernel 68060-fits (kabi k46.1.3, abi ${A3%${A3#????????}}, gcc-2.7.2.3-8949028)"
side newer k46.1.4 $A2
$MC --kernel $T/newer | grep -q "fits kernel 68060-newer (kabi k46.1.4, abi not compared below its minor"
side abi k46.1.3 $A2
no abi "the same kabi, another ABI"
side older k46.1.2 $A2
no older "below the kit's k46.1.3"
side line k46.1.3 $A3 k30
no line "is line k30, the kit k46"
side major k46.2.0 $A3
no major "another family or major"
side fam k30.1.3 $A3
no fam "another family or major"
side pin k46.1.3 $A3 k46 gcc-2.95
no pin "is pinned to gcc-2.95, the kit to gcc-2.7.2.3-8949028"
grep -v '^abi=' $T/fits > $T/short
no short "no abi= line"
echo "kitkern: a fitting kit, a lower minor, and seven mismatches ok"
