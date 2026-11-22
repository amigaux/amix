#!/usr/bin/env python3
"""textrel-report.py READELF NM LIB... -- the text relocations (DT_TEXTREL) of
shared libraries, for the shared variant's build log and README: per library,
the number of dynamic relocations that land in .text, and the functions they
land in grouped by the static archive they come from, with those functions'
bytes.  Each group's functions are named by the exported symbol at or before
the relocation (a library keeps only its dynamic symbols).  Prints a report;
exits 0 (the shared variant names its text relocations, it does not hide them).
MIT licence, see LICENSE in userland/packages."""
import bisect, re, subprocess, sys

READELF, NM = sys.argv[1:3]
GROUPS = (
    ("GCC's C++ runtime (libsupc++, static, non-PIC)",
     re.compile(r"^(_Z.*(cxxabiv|__gnu_cxx|St[0-9]|_ZSt|_Zd|_Zn).*|_Z[dn].*|__cxa_.*|__gxx_.*)$")),
    ("Amix's libm (static only)",
     re.compile(r"^(sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh|exp|log|log10|pow|sqrt|"
                r"floor|ceil|fmod|ldexp|frexp|modf|hypot|_reduce|round)$")),
)

def run(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout

def report(lib):
    dyn = run(READELF, "-d", lib)
    if "TEXTREL" not in dyn:
        return None
    text = [l.split() for l in run(READELF, "-S", "-W", lib).splitlines() if " .text " in l][0]
    i = text.index(".text")
    lo = int(text[i + 2], 16); hi = lo + int(text[i + 4], 16)
    syms = []
    for l in run(NM, "-n", "-S", "-D", "--defined-only", lib).splitlines():
        f = l.split()
        if len(f) == 4 and f[2] in "tTwW":
            syms.append((int(f[0], 16), int(f[1], 16), f[3]))
    keys = [s[0] for s in syms]
    funcs, n = {}, 0
    for l in run(READELF, "-r", "-W", lib).splitlines():
        f = l.split()
        if len(f) >= 3 and len(f[0]) == 8 and all(c in "0123456789abcdef" for c in f[0]):
            o = int(f[0], 16)
            if lo <= o < hi:
                n += 1
                k = bisect.bisect_right(keys, o) - 1
                if k >= 0:
                    funcs[syms[k][2]] = syms[k][1]
    out = ["  TEXTREL %s: %d relocations in .text" % (lib.rsplit("/", 1)[-1], n)]
    left = dict(funcs)
    for name, pat in GROUPS:
        g = {s: b for s, b in left.items() if pat.match(s)}
        if g:
            out.append("    %s: %d functions, %d bytes" % (name, len(g), sum(g.values())))
            for s in g:
                del left[s]
    if left:
        out.append("    other: %d bytes in %s" % (sum(left.values()), " ".join(sorted(left))))
    return "\n".join(out)

for lib in sys.argv[3:]:
    r = report(lib)
    if r:
        print(r)
