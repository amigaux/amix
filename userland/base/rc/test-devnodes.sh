#!/bin/sh
# test-devnodes.sh -- host tests of the devnodes boot step against a scratch
# contents database, a fake ls (the nodes "there"), a fake kbootset and a
# fake mknod.
#
#   sh userland/base/rc/test-devnodes.sh [shell]     (default sh)
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-devnodes.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { # same <name> <want> <got>
	[ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"
}
expect() { # expect <name> <want-substring> <got>
	case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac
}

R=$T/root
mkdir -p "$T/bin" "$R/dev"
# kbootset as C2-4 section 15 gives it
cat > "$T/bin/kbootset" <<'EOF'
#!/bin/sh
[ "$1" = major ] || exit 2
case "$2" in
z3660eth) echo "c 51" ;;
monsw) echo "c 52" ;;
ramdisk) echo "b 20" ;;
*) echo "kbootset: no major is registered to $2" >&2; exit 1 ;;
esac
EOF
# mknod: record the call, make a plain file (a real node needs root)
printf '#!/bin/sh\necho "$*" >> "%s/mknod.log"\n: > "$1"\n' "$T" > "$T/bin/mknod"
# ls -ld <path> ...: the nodes "there" are the lines of $T/nodes
# ("<path> <type> <major> <minor>"); any other path is absent
cat > "$T/bin/ls" <<EOF
#!/bin/sh
shift
for p
do
	l=\`grep "^\$p " "$T/nodes"\`
	if [ -n "\$l" ]
	then
		set -- \$l
		echo "\${2}rw-rw-rw-   1 root     sys       \$3,  \$4 Oct 31 12:00 \$1"
	else
		echo "\$p: No such file or directory" >&2
	fi
done
EOF
chmod +x "$T/bin/"*

db() { cat > "$T/contents"; }
there() { cat > "$T/nodes"; }
run() { # run <kbootset>: the step, its log in rc.log
	: > "$T/rc.log"
	: > "$T/mknod.log"
	env RC_SUBR="$here/rc.subr" RC_LOG="$T/rc.log" RC_KBOOTSET="$1" \
	    DEVNODES_DB="$T/contents" DEVNODES_ROOT="$R" PATH="$T/bin:$PATH" \
	    $SH "$here/devnodes" start 2>&1
}
K=$T/bin/kbootset

# the stock system's records and a driver package's, all there and right
db <<'EOF'
/dev d none 0755 root sys core
/dev/null c none 2 2 0666 root sys core
/dev/dsk/c6d0s0 b none 0 48 0600 root sys core
/dev/zen0 c z3660eth 51 0 0600 root sys zethdrv
/dev/console=/dev/syscon l none core
/etc/inittab f none 0664 root sys 1444 54673 690829200 core
/dev/ram0 b ramdisk 20 0 0600 root sys ramdisk
EOF
there <<EOF
$R/dev/null c 2 2
$R/dev/dsk/c6d0s0 b 0 48
$R/dev/zen0 c 51 0
$R/dev/ram0 b 20 0
EOF
o=$(run "$K")
same "all there: no output" "" "$o"
same "all there: nothing made" "" "$(cat "$T/mknod.log")"
same "all there: nothing logged" "" "$(cat "$T/rc.log")"

# a stock node missing: its record's major, minor and mode; its directory made
there <<EOF
$R/dev/null c 2 2
$R/dev/zen0 c 51 0
$R/dev/ram0 b 20 0
EOF
run "$K" > /dev/null
same "stock missing: made from the record" "$R/dev/dsk/c6d0s0 b 0 48" "$(cat "$T/mknod.log")"
[ -d "$R/dev/dsk" ] && ok || bad "the node's directory was not made"
expect "stock missing: logged" "mknod: made $R/dev/dsk/c6d0s0 b 0 48" "$(cat "$T/rc.log")"
expect "stock missing: counted" "devnodes: 1 node(s) made, 0 failed" "$(cat "$T/rc.log")"
same "stock missing: the record's mode" "600" "$(stat -c %a "$R/dev/dsk/c6d0s0")"

# a module's node missing: the registry's major, here equal to the record's
there <<EOF
$R/dev/null c 2 2
$R/dev/dsk/c6d0s0 b 0 48
$R/dev/ram0 b 20 0
EOF
run "$K" > /dev/null
same "module missing: made at the registry's major" "$R/dev/zen0 c 51 0" "$(cat "$T/mknod.log")"

# the record disagrees with the registry: the registry wins, said as an error
db <<'EOF'
/dev/monsw c monsw 50 0 0666 root sys monsw
EOF
there < /dev/null
o=$(run "$K")
same "registry wins" "$R/dev/monsw c 52 0" "$(cat "$T/mknod.log")"
expect "registry wins: packaging error logged" "packaging error: $R/dev/monsw: given major 50" "$(cat "$T/rc.log")"
expect "registry wins: on the console too" "registry says 52" "$o"

# a module's node there at another major: made again at the registry's
db <<'EOF'
/dev/zen0 c z3660eth 51 0 0600 root sys zethdrv
EOF
there <<EOF
$R/dev/zen0 c 49 0
EOF
run "$K" > /dev/null
same "module node wrong: made again" "$R/dev/zen0 c 51 0" "$(cat "$T/mknod.log")"

# a stock node there but different: left, and logged
db <<'EOF'
/dev/null c none 2 2 0666 root sys core
EOF
there <<EOF
$R/dev/null c 2 3
EOF
run "$K" > /dev/null
same "stock differs: left" "" "$(cat "$T/mknod.log")"
expect "stock differs: logged" "devnodes: /dev/null is not c 2 2 as recorded; left" "$(cat "$T/rc.log")"

# a module the registry does not know: the record's major
db <<'EOF'
/dev/zz0 c z3660rtg 49 0 0600 root sys rtg
EOF
there < /dev/null
run "$K" > /dev/null
same "unknown module: the record's major" "$R/dev/zz0 c 49 0" "$(cat "$T/mknod.log")"

# a block node of a module
db <<'EOF'
/dev/ram0 b ramdisk 20 0 0600 root sys ramdisk
EOF
run "$K" > /dev/null
same "block node from the registry" "$R/dev/ram0 b 20 0" "$(cat "$T/mknod.log")"

# several missing at once, in record order
db <<'EOF'
/dev/null c none 2 2 0666 root sys core
/dev/zen0 c z3660eth 51 0 0600 root sys zethdrv
/dev/zen1 c z3660eth 51 1 0600 root sys zethdrv
EOF
run "$K" > /dev/null
same "several" "$R/dev/null c 2 2
$R/dev/zen0 c 51 0
$R/dev/zen1 c 51 1" "$(cat "$T/mknod.log")"
expect "several: counted" "3 node(s) made, 0 failed" "$(cat "$T/rc.log")"

# stock pkgadd records a number 0 as "?" (zen0's minor): "?" is 0, both to
# compare with the node there and to make a missing one; a "?" mode is 0600
db <<'EOF'
/dev/zen0 c z3660eth 51 ? 0600 root sys zeth30
/dev/q0 c none ? 1 ? root sys q
EOF
there <<EOF
$R/dev/zen0 c 51 0
$R/dev/q0 c 0 1
EOF
run "$K" > /dev/null
same "?: matches 0, nothing made" "" "$(cat "$T/mknod.log")$(cat "$T/rc.log")"
there < /dev/null
run "$K" > /dev/null
same "?: missing ones made with 0" "$R/dev/zen0 c 51 0
$R/dev/q0 c 0 1" "$(cat "$T/mknod.log")"
same "?: a ? mode is 0600" "600" "$(stat -c %a "$R/dev/q0")"
there <<EOF
$R/dev/zen0 c 51 3
EOF
db <<'EOF'
/dev/zen0 c z3660eth 51 ? 0600 root sys zeth30
EOF
run "$K" > /dev/null
same "?: a node at another minor is made again at 0" "$R/dev/zen0 c 51 0" "$(cat "$T/mknod.log")"

# no database, no records: nothing at all
rm -f "$T/contents"
o=$(run "$K")
same "no database" "" "$o$(cat "$T/mknod.log")$(cat "$T/rc.log")"
db <<'EOF'
/etc/inittab f none 0664 root sys 1444 54673 690829200 core
EOF
o=$(run "$K")
same "no device records" "" "$o$(cat "$T/mknod.log")$(cat "$T/rc.log")"

# stop does nothing; anything else is a usage error
same "stop" "0" "$(env RC_SUBR="$here/rc.subr" $SH "$here/devnodes" stop; echo $?)"
same "usage" "1" "$(env RC_SUBR="$here/rc.subr" $SH "$here/devnodes" 2>/dev/null; echo $?)"

echo "test-devnodes: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
