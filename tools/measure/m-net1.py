#!/usr/bin/env python3
# m-net1.py -- M-NET1a/b: netinstall miniroot size, raw and deflate-compressed,
# per kernel line, from today's binaries; plus the floppy kernels' deflate size
# as the kernel estimate.  Host-side, read-only.  See
# docs/measurements/2026-10-25-m-net1.md for what is counted and why.
#
# usage: m-net1.py <workspace> <netdir> [<outdir>]
#   <workspace>  the Amix project workspace (holds amix-installng/)
#   <netdir>     a directory holding the network userland extracted from the
#                stock distribution tape (file 02: usr/sbin/slink,
#                usr/sbin/ifconfig, usr/lib/{libsocket.so,libnsl.so,libc.so.1},
#                etc/inet/strcf; file 07: usr/sbin/route,
#                usr/sbin/ping, usr/bin/ftp) and a stripped apkg 0.2.3 as
#                <netdir>/apkg
#   <outdir>     optional: also write each miniroot archive there as
#                miniroot-<line>-<full|trim>.tar (the M-FP1 input, S1-24)
import io, json, os, struct, subprocess, sys, tarfile, zlib

WS, NET = sys.argv[1], sys.argv[2]
OUT = sys.argv[3] if len(sys.argv) > 3 else None
sys.path.insert(0, os.path.join(WS, 'amix-installng/tools/lib'))
import s5, ufs  # noqa: E402  (amix-installng's own readers)

BUDGET = 2 * 890880   # two DD volumes at the budget of record (P-28 D37)


def s5_files(img):
    out, seen = {}, {}

    def blocks(addrs, size):
        def ind(b, lvl):
            if b == 0:
                return [0] * (256 ** lvl)
            nums = struct.unpack('>256I', img[b * 1024:(b + 1) * 1024])
            if lvl == 1:
                return list(nums)
            return [x for n in nums for x in ind(n, lvl - 1)]
        need = (size + 1023) // 1024
        bl = list(addrs[:10])
        if need > 10:
            bl += ind(addrs[10], 1)
        if need > 266:
            bl += ind(addrs[11], 2)
        return bl[:need]

    def walk(ino, prefix):
        for cino, name in s5.read_dir(img, ino):
            if name in ('.', '..'):
                continue
            mode, _, _, _, size, addrs = s5.read_inode(img, cino)
            t, p = mode & 0xF000, prefix + '/' + name
            if t == 0x4000:
                walk(cino, p)
            elif t in (0x8000, 0xA000):
                if cino in seen:
                    out[p] = ('link', seen[cino])
                    continue
                data = b''.join(img[b * 1024:(b + 1) * 1024] if b else b'\0' * 1024
                                for b in blocks(addrs, size))[:size]
                seen[cino] = p
                out[p] = ('file', data)
    walk(2, '')
    return out


def ufs_files(img):
    sb = ufs.parse_super(img)
    return {p: ('file', ufs.read_data(img, sb, d))
            for p, d in ufs.walk(img, 0, sb) if d.type in (0x8000, 0xA000)}


def tree(root, dirs):
    out = {}
    for d in dirs:
        p = os.path.join(root, d)
        for r, _, fs in (os.walk(p) if os.path.isdir(p) else [(root, [], [d])]):
            for f in fs:
                fp = os.path.join(r, f)
                out['/install/' + os.path.relpath(fp, root)] = ('file', open(fp, 'rb').read())
    return out


def total(files):
    return sum(len(v) for k, v in files.values() if k != 'link')


def tar_deflate(files, save=None):
    bio = io.BytesIO()
    with tarfile.open(fileobj=bio, mode='w', format=tarfile.USTAR_FORMAT) as t:
        for p, (k, v) in sorted(files.items()):
            if k == 'link':
                continue
            ti = tarfile.TarInfo(p.lstrip('/'))
            ti.size, ti.mtime = len(v), 0
            t.addfile(ti, io.BytesIO(v))
    raw = bio.getvalue()
    if save:
        with open(save, 'wb') as f:
            f.write(raw)
    return len(raw), len(zlib.compress(raw, 9))


def floppy_kernel(adf):
    a = open(adf, 'rb').read()
    for i in range(0x400, 0x2800, 512):
        if a[i:i + 4] == b'IBLK':
            size, full = struct.unpack('>II', a[i + 8:i + 16])
            if full and a[i + 512:i + 514] == b'\x1f\x9d':
                raw = subprocess.run(['gzip', '-dc'], input=a[i + 512:i + 512 + size],
                                     capture_output=True, check=True).stdout
                return {'lzw': size, 'raw': len(raw), 'deflate9': len(zlib.compress(raw, 9))}
    raise SystemExit('no compressed kernel IBLK in ' + adf)


IN = os.path.join(WS, 'amix-installng')
FB = os.path.join(IN, 'floppies/build')
base = {'k30': s5_files(open(os.path.join(FB, 'amix_21_root-ng.adf'), 'rb').read()),
        'k46': ufs_files(open(os.path.join(FB, 'amix_21_root-ufs060.adf'), 'rb').read())}
stage = os.path.join(IN, 'work/iso-stage-r7-public060-sd')
inst = tree(stage, ['bin', 'admin', 'firstboot', 'fpfix', 'order', 'order.minimal', 'profiles',
                    'sets', 'setclk', 'stand', 'syslog', 'tz', 'zenmac'])
trim_out = {'/install/bin/pkgchk', '/install/bin/pkgtrans', '/install/bin/pkginfo', '/install/bin/apkg'}
inst_trim = {k: v for k, v in inst.items() if k not in trim_out}
net = {'/' + r: ('file', open(os.path.join(NET, r), 'rb').read()) for r in
       ['usr/sbin/slink', 'usr/sbin/ifconfig', 'usr/sbin/route', 'usr/sbin/ping',
        'usr/lib/libsocket.so', 'usr/lib/libnsl.so', 'usr/lib/libc.so.1',
        'etc/inet/strcf']}
net['/usr/apkg/bin/apkg'] = ('file', open(os.path.join(NET, 'apkg'), 'rb').read())
kern = {'k30': floppy_kernel(os.path.join(FB, 'amix_21_boot-universal-r7.adf')),
        'k46': floppy_kernel(os.path.join(FB, 'boot040-kd060fd.adf'))}
res = {}
for line in ('k30', 'k46'):
    r = {'kernel': kern[line], 'base': {'files': sum(1 for k, _ in base[line].values() if k != 'link'),
         'raw': total(base[line]), 'tar_deflate': tar_deflate(base[line])},
         'installer_full': {'raw': total(inst), 'tar_deflate': tar_deflate(inst)},
         'installer_trim': {'raw': total(inst_trim), 'tar_deflate': tar_deflate(inst_trim)},
         'net': {'raw': total(net), 'tar_deflate': tar_deflate(net),
                 'already_in_base': sorted(p for p in net if p in base[line])}}
    for name, ins in (('full', inst), ('trim', inst_trim)):
        u = dict(base[line]); u.update(ins); u.update(net)
        raw, z = tar_deflate(u, OUT and os.path.join(OUT, 'miniroot-%s-%s.tar' % (line, name)))
        t = z + kern[line]['deflate9']
        r['miniroot_' + name] = {'raw': total(u), 'tar': raw, 'deflate': z,
                                 'with_kernel': t, 'margin': BUDGET - t,
                                 'margin_pct': round(100.0 * (BUDGET - t) / BUDGET, 1)}
    res[line] = r
print(json.dumps(res, indent=1))
