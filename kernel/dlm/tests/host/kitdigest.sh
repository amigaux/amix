#!/bin/sh
# kitdigest.sh -- tools/kitdigest.sh, the kit digests of the release lock
# (P-38 S2.1): on a made-up kit of both lines, the line's fields from
# kit.conf (PORT_REV "-" when absent); the manifest digest equal to one
# computed here independently (python, the dlmkit recipe's rule: "<x|->
# <sha256> <path>" per file, C order); a new KIT_REV changes the manifest
# but not the norev digest; a changed byte or exec bit changes both; -l
# prints the list; a directory without kit.conf is refused.
# Run from the repository root.
set -e
B=${B:-build}
T=$B/kitdigest
rm -rf $T && mkdir -p $T/k46/include/sys $T/k46/tools $T/k30
KD="sh tools/kitdigest.sh"
printf 'LINE=k46\nKABI=k46.1.3\nKIT_REV=abc1234\nPORT_REV=0d37eb1\n' > $T/k46/kit.conf
printf 'LINE=k30\nKABI=k30.1.3\nKIT_REV=abc1234\n' > $T/k30/kit.conf
echo "notice abc1234" > $T/k46/NOTICE
echo "struct mod;" > $T/k46/include/sys/mod.h
echo "#!/bin/sh" > $T/k46/tools/mkmod && chmod 0755 $T/k46/tools/mkmod
echo "B" > $T/k46/B
echo "a" > $T/k46/a
echo "x" > $T/k30/abi.txt

# want KIT EXCLUDE...: the manifest digest, by the recipe's rule, in python
want() {
	python3 - "$@" <<'P'
import hashlib, os, sys
d, ex = sys.argv[1], set("./" + e for e in sys.argv[2:])
fs = []
for r, _, ns in os.walk(d):
    for n in ns:
        fs.append("./" + os.path.relpath(os.path.join(r, n), d))
out = ""
for f in sorted(fs, key=lambda s: s.encode()):
    if f in ex:
        continue
    p = os.path.join(d, f)
    x = "x" if os.access(p, os.X_OK) else "-"
    out += "%s %s %s\n" % (x, hashlib.sha256(open(p, "rb").read()).hexdigest(), f)
print(hashlib.sha256(out.encode()).hexdigest())
P
}
$KD $T/k30 $T/k46 > $T/out
[ "$(wc -l < $T/out)" -eq 2 ]
set -- $(sed -n 2p $T/out)
[ "$1 $2 $3" = "kit k46 k46.1.3" ] && [ "$6 $7" = "KIT_REV=abc1234 PORT_REV=0d37eb1" ]
m=$4 n=$5
[ "$m" = "$(want $T/k46)" ] || { echo "kitdigest: manifest $m, the rule gives $(want $T/k46)" >&2; exit 1; }
[ "$n" = "$(want $T/k46 kit.conf NOTICE)" ]
set -- $(sed -n 1p $T/out)
[ "$1 $2 $3" = "kit k30 k30.1.3" ] && [ "$6 $7" = "KIT_REV=abc1234 PORT_REV=-" ]
# -l: the list, "./B" before "./a" (C order), x on the executable
$KD -l $T/k46 > $T/list
[ "$(sed -n 1p $T/list | cut -c68-)" = "./B" ] && [ "$(sed -n 2p $T/list | cut -c68-)" = "./NOTICE" ]
grep -q '^x [0-9a-f]* ./tools/mkmod$' $T/list && grep -q '^- [0-9a-f]* ./a$' $T/list
# another commit: the manifest moves, norev does not
sed -i 's/abc1234/def5678/' $T/k46/kit.conf $T/k46/NOTICE
set -- $($KD $T/k46)
[ "$4" != "$m" ] && [ "$5" = "$n" ]
# a byte, then an exec bit: both move
m2=$4
echo "struct mod; int x;" > $T/k46/include/sys/mod.h
set -- $($KD $T/k46)
[ "$4" != "$m2" ] && [ "$5" != "$n" ]
n3=$5
chmod 0755 $T/k46/a
set -- $($KD $T/k46)
[ "$5" != "$n3" ]
# no kit.conf: refused
mkdir -p $T/empty
if $KD $T/empty > /dev/null 2>&1; then echo "kitdigest: a dir without kit.conf accepted" >&2; exit 1; fi
echo "kitdigest: fields, the recipe's rule, -l, norev across commits, bytes and modes ok"
