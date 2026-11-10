# licensing_gpl_text GPL2-WHERE GPL3-WHERE FILE -- the GPL part of a medium's /LICENSING: where the kernels'
# libgcc helpers and the zz9ksvc module come from, and where the licence texts are on that medium.
licensing_gpl_text() {
	cat >> "$3" <<EOF

The kernels (kern30m, kern46m) include helper routines from the libgcc of GCC 2.7.2.3 (libgcc2.c
and longlong.h), under the GNU General Public License, version 2 or later, with that library's
exception. Their source is GCC 2.7.2.3, sha256
16166e0f0f2064bb3114716650569065ef3855ae2331d7a29b85d4b9aa73773c, at
https://github.com/amigaux/amix-distfiles/releases/download/gcc-2.7.2.3/gcc-2.7.2.3.tar.gz
and the original at https://ftp.gnu.org/gnu/gcc/gcc-2.7.2.3.tar.gz. The compiler's patches, which
change neither file, are at https://github.com/jusii/gcc-cross-amix, commit
33ebadcf6976ee65dbd1e25a586f59da55e5942d. The licence text is $1.

The zz9ksvc kernel module is under the GNU General Public License, version 3 or later. Its source
is at https://github.com/amigaux/amix, in kernel/modules/zz9ksvc and the directories its notice
names, at each release's revision of that repository. The licence text is $2.
EOF
}
