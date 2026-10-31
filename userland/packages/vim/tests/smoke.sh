#!/bin/sh
#
# smoke.sh -- Vim 9.1 acceptance, ON THE BOX.
#
#     sh tests/smoke.sh [prefix]          (default /opt/amix)
#
# Non-interactive only (ex mode, -u NONE): an edit through vim -es and through
# the ex link, the runtime vim finds, vimdiff's argv[0] dispatch, and an xxd
# round trip.  1992 Bourne shell: backticks, expr, no grep -q, no $(...), no
# `!'.  Result lines start with "RES "; the last is "RES smoke PASS" or
# "RES smoke FAIL <n>".

X=${1:-/opt/amix}
V=$X/bin/vim
fails=0
ok()  { echo "RES ok   $*"; }
bad() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }
eq()  { if [ -z "$3" ]; then bad "$1: nothing to compare (got '$2')"
	elif [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got '$2' want '$3'"; fi; }

rm -rf vimsmoke; mkdir vimsmoke; cd vimsmoke || exit 1

# --- 1. the binary ------------------------------------------------------------------
$V --version > v.out 2>&1
egrep '^VIM - Vi IMproved 9\.1' v.out > /dev/null && ok "vim --version: `sed -n 1p v.out`" || bad "vim --version: `sed -n 1p v.out`"
egrep '\+terminfo' v.out > /dev/null && ok "built with +terminfo" || bad "no +terminfo in --version"

# --- 2. an edit in ex mode, through vim -es and through the ex link -------------------
cat > e1 <<EOT
one
two
three
EOT
$V -es -u NONE -c '%s/two/TWO/' -c 'wq' e1 < /dev/null; rc=$?
eq "vim -es substitute (rc $rc)" "`sed -n 2p e1`" TWO
cat > e2 <<EOT
alpha
beta
EOT
$X/bin/ex -s -u NONE -c '1d' -c 'wq' e2 < /dev/null; rc=$?
eq "ex link deletes line 1 (rc $rc)" "`cat e2`" beta

# --- 3. the runtime it finds --------------------------------------------------------
$V -es -u NONE -c 'redir! > rt.out' -c 'echo $VIMRUNTIME' -c 'redir END' -c 'q' < /dev/null
eq "VIMRUNTIME" "`tr -d '\012' < rt.out`" "$X/share/vim/vim91"
[ -f "$X/share/vim/vim91/syntax/c.vim" ] && [ -f "$X/share/vim/vim91/doc/help.txt" ] &&
	ok "runtime has syntax/c.vim and doc/help.txt" || bad "runtime files missing under $X/share/vim/vim91"

# --- 4. vimdiff is vim in diff mode ----------------------------------------------------
cat > d1 <<EOT
a
b
EOT
cat > d2 <<EOT
a
c
EOT
$X/bin/vimdiff -es -u NONE -c 'redir! > d.out' -c 'echo &diff' -c 'redir END' -c 'qa!' d1 d2 < /dev/null > /dev/null 2>&1
eq "vimdiff sets 'diff'" "`tr -d '\012' < d.out`" 1

# --- 5. xxd: dump and revert ------------------------------------------------------------
cp $V x.bin
$X/bin/xxd x.bin > x.hex && $X/bin/xxd -r x.hex > x.back
cmp x.bin x.back > /dev/null 2>&1 && ok "xxd dump and -r give the same bytes (`wc -c < x.bin | tr -d ' '`)" || bad "xxd round trip differs"

cd ..
if [ $fails -eq 0 ]; then echo "RES smoke PASS"; else echo "RES smoke FAIL $fails"; fi
[ $fails -eq 0 ]
