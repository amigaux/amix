#!/bin/bash
#
# make-archives.sh -- the archives box.sh extracts, made on the build host
# with GNU tar, and their expected contents.
#
#     bash make-archives.sh <out dir>
#
# <out>/src: a small tree (regular files from 0 bytes to 600 KB, a long
# name, a symbolic and a hard link, an empty directory), made from a fixed
# seed so every run gives the same bytes.  <out>/*.tar: the tree in each
# format and owner case:
#   v7                 old format: numbers only (0/3); without the long
#                      name, which v7 cannot hold
#   {ustar,gnu}-named  owner bin:1, group bin:1 -- names this system has,
#                      with Linux's numbers (here bin is 2/2)
#   {ustar,gnu}-absent owner jdoe:1234, group users:5678 -- names it lacks
#   {ustar,gnu}-empty  empty names, numbers 1234/5678 (--numeric-owner)
#   pax                pax headers (stock tar does not read them)
# <out>/expect: one line per regular file, `<path> <sum -r>', the BSD sum
# that the box's sum -r prints too.
# MIT, this repository.

set -eu
O=$(mkdir -p "${1:?usage: make-archives.sh <out dir>}" && cd "$1" && pwd)
S=$O/src
rm -rf -- "${S:?}"
mkdir -p "$S/d/sub" "$S/empty"
gen() { python3 -c "import random,sys; r=random.Random(int(sys.argv[2])); sys.stdout.buffer.write(bytes(r.getrandbits(8) for _ in range(int(sys.argv[1]))))" "$1" "$2"; }
: > "$S/zero"
printf 'hello, amix\n' > "$S/hello"
gen 511 1 > "$S/d/b511"
gen 512 2 > "$S/d/b512"
gen 513 3 > "$S/d/b513"
gen 70000 4 > "$S/d/sub/k70"
gen 600000 5 > "$S/d/m6"
L=d/sub/a-name-longer-than-one-hundred-bytes-so-that-ustar-needs-its-prefix-and-gnu-its-longlink-entry.txt
printf 'long\n' > "$S/$L"
ln -s hello "$S/link-to-hello"
ln "$S/hello" "$S/hard-to-hello"
chmod 0644 $(find "$S" -type f); chmod 0755 $(find "$S" -type d)
chmod 0750 "$S/d/sub"; chmod 0600 "$S/d/b511"
find "$S" -exec touch -h -d @1793491200 {} +
cd "$S"
T="tar --sort=name --mtime=@1793491200 -cf"
$T "$O/v7.tar" --format=v7 --owner=0 --group=3 --numeric-owner --exclude="./$L" .
for f in ustar gnu; do
	$T "$O/$f-named.tar" --format=$f --owner=bin:1 --group=bin:1 .
	$T "$O/$f-absent.tar" --format=$f --owner=jdoe:1234 --group=users:5678 .
	$T "$O/$f-empty.tar" --format=$f --owner=1234 --group=5678 --numeric-owner .
done
$T "$O/pax.tar" --format=pax --pax-option=delete=atime,delete=ctime --owner=bin:1 --group=bin:1 .
find . -type f | LC_ALL=C sort | while read -r f; do echo "$f $(sum -r "$f" | awk '{print $1 + 0}')"; done > "$O/expect"
ls -l "$O"/*.tar | awk '{print $5, $NF}'
