#!/usr/bin/env python3
"""public-text-check.py -- no process words in anything public (the list: public-words.txt, beside this tool).

  public-text-check.py --tree [--scope PATH]...  every tracked text file in this working copy
  public-text-check.py --stage DIR               a disc's staged tree: its own text in full, packages for labels
  public-text-check.py --disc FILE...            a whole medium's raw bytes, for labels
  public-text-check.py --selftest

Exit 0 clean, 1 a hit, 2 it could not look: a missing file, an empty medium or tree, an empty list, nothing
scanned. Never a pass without having read something: each line says how much was read.
"""
import fnmatch, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
LIST = os.path.join(HERE, "public-words.txt")
SELF = ("public-words.txt", "public-text-check.py")   # the list has to name the words


class CouldNotLook(Exception):
    pass


def load(path=LIST):
    labels, words, allow, examples = [], [], [], []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            c = line.split("\t")
            if len(c) != 3 or c[0] not in ("label", "word", "allow"):
                raise CouldNotLook("%s:%d: not CLASS<tab>A<tab>B" % (path, n))
            if c[0] == "allow":
                allow.append((c[1], re.compile(c[2])))
                continue
            (labels if c[0] == "label" else words).append(re.compile(c[1]))
            examples.append((re.compile(c[1]), c[2]))
    if not labels or not words:
        raise CouldNotLook("%s: no words: an empty list proves nothing" % path)
    return labels, words, allow, examples


def scan_text(name, data, pats, allow):
    """Hits in one text file, as printable lines."""
    out = []
    text = data.decode("latin-1")
    for n, line in enumerate(text.split("\n"), 1):
        for p in pats:
            m = p.search(line)
            if m and not any(fnmatch.fnmatch(name, g) and r.search(line) for g, r in allow):
                out.append("%s:%d: %s: %s" % (name, n, m.group(0), line.strip()[:110]))
                break
    return out


def tree(scopes, root=None):
    labels, words, allow, _ = load()
    root = root or subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
    r = subprocess.run(["git", "-C", root, "ls-files", "-z", "--"] + (scopes or ["."]), capture_output=True)
    if r.returncode:
        raise CouldNotLook("git ls-files: " + r.stderr.decode("latin-1").strip())
    names = [n.decode("utf-8", "surrogateescape") for n in r.stdout.split(b"\0") if n]
    if not names:
        raise CouldNotLook("no tracked file under %s" % (scopes or ["."]))
    read = links = binary = 0
    hits = []
    for n in names:
        p = os.path.join(root, n)
        if os.path.basename(n) in SELF:
            continue
        if os.path.islink(p):
            links += 1
            continue
        if not os.path.exists(p):
            raise CouldNotLook("tracked but missing: " + n)
        with open(p, "rb") as f:
            d = f.read()
        if b"\0" in d:
            binary += 1
            continue
        read += 1
        hits += scan_text(n, d, labels + words, allow)
    if not read:
        raise CouldNotLook("no text file read under %s" % (scopes or ["."]))
    return hits, "tree: %d text files read, %d links and %d binary files passed over" % (read, links, binary)


def is_package(name, data):
    # not our text: package payloads and programs, whose English may speak of a file's owner
    return name.endswith(".pkg") or b"\0" in data


def stage(top):
    labels, words, allow, _ = load()
    if not os.path.isdir(top):
        raise CouldNotLook("no stage directory: " + top)
    own = other = 0
    hits = []
    for r, ds, fs in os.walk(top):
        for f in fs:
            p = os.path.join(r, f)
            if os.path.islink(p):
                continue
            name = os.path.relpath(p, top)
            with open(p, "rb") as fh:
                d = fh.read()
            if is_package(name, d):
                other += 1
                hits += ["%s@%d: %s" % (name, m.start(), m.group(0).decode("latin-1"))
                         for pat in labels for m in re.compile(pat.pattern.encode()).finditer(d)]
            else:
                own += 1
                hits += scan_text(name, d, labels + words, allow)
    if not own:
        raise CouldNotLook("no text file in the stage: " + top)
    return hits, "stage: %d text files read in full, %d packages and programs for labels" % (own, other)


def disc(paths):
    labels = load()[0]
    pat = re.compile(b"|".join(b"(?:" + p.pattern.encode() + b")" for p in labels))
    if not paths:
        raise CouldNotLook("no medium named")
    hits = []
    total = 0
    for path in paths:
        if not os.path.isfile(path):
            raise CouldNotLook("no medium: " + path)
        size = os.path.getsize(path)
        if not size:
            raise CouldNotLook("empty medium: " + path)
        total += size
        step = 1 << 24
        over = 256     # a word across a read boundary
        with open(path, "rb") as f:
            base, prev = 0, b""
            while True:
                b = f.read(step)
                if not b:
                    break
                buf = prev + b
                for m in pat.finditer(buf):
                    # a hit wholly inside the overlap was reported from the read before
                    if m.end() <= len(prev):
                        continue
                    c = re.sub(rb"[^ -~]", b".", buf[max(0, m.start() - 40):m.end() + 28]).decode()
                    hits.append("%s@%d: %s: %s" % (os.path.basename(path), base - len(prev) + m.start(), m.group(0).decode("latin-1"), c))
                prev = buf[-over:]
                base += len(b)
    return hits, "disc: %d media, %d bytes read" % (len(paths), total)


def selftest():
    bad = 0

    def ok(cond, what):
        nonlocal bad
        if not cond:
            print("  FAIL", what)
            bad += 1

    def stops(fn, what):
        try:
            fn()
        except CouldNotLook:
            return
        ok(False, what + ": no stop")

    labels, words, allow, examples = load()
    for p, ex in examples:
        ok(p.search(ex), "the list's example does not hit: %s %s" % (p.pattern, ex))
    with tempfile.TemporaryDirectory() as d:
        # raw bytes: found in the first read, across the read boundary, and only once
        ex = examples[0][1].encode()
        m = os.path.join(d, "m.iso")
        open(m, "wb").write(b"\0" * 100 + ex + b"\0" * 100)
        h, s = disc([m])
        ok(len(h) == 1 and "bytes read" in s, "a label in a medium: %s" % h)
        open(m, "wb").write(b"\0" * ((1 << 24) - 3) + ex + b"\0" * 100)
        ok(len(disc([m])[0]) == 1, "a label across the read boundary")
        open(m, "wb").write(b"plain text only\n")
        ok(disc([m])[0] == [], "a clean medium")
        # could not look: stop, never clean
        e = os.path.join(d, "empty")
        open(e, "wb").close()
        stops(lambda: disc([e]), "an empty medium")
        stops(lambda: disc([os.path.join(d, "absent")]), "a missing medium")
        stops(lambda: disc([]), "no medium")
        stops(lambda: stage(os.path.join(d, "absent")), "a missing stage")
        st = os.path.join(d, "s")
        os.makedirs(st)
        stops(lambda: stage(st), "an empty stage")
        # a stage: full list on its text, labels only on a package and a program
        open(os.path.join(st, "a.sh"), "w").write("# clean\n")
        ok(stage(st)[0] == [], "a clean stage")
        open(os.path.join(st, "b.pkg"), "w").write("set the owner and group\n")
        open(os.path.join(st, "c"), "wb").write(b"\0the owner's mark\0")
        ok(stage(st)[0] == [], "English about a file's owner in a package or a program")
        open(os.path.join(st, "b.pkg"), "wb").write(ex)
        ok(len(stage(st)[0]) == 1, "a label in a package")
        os.unlink(os.path.join(st, "b.pkg"))
        open(os.path.join(st, "a.sh"), "w").write("# as the owner said\n")
        ok(len(stage(st)[0]) == 1, "a word in the disc's own text")
        # a tree: tracked text, and the stops
        g = os.path.join(d, "g")
        os.makedirs(g)
        run = lambda *a: subprocess.run(["git", "-C", g] + list(a), capture_output=True, check=True)
        run("init", "-q", "-b", "master")
        open(os.path.join(g, "t.txt"), "w").write("clean\n")
        run("add", "t.txt")
        ok(tree([], g)[0] == [], "a clean tree")
        open(os.path.join(g, "t.txt"), "w").write("clean\nwave\nas in W9\n")
        ok(len(tree([], g)[0]) == 2, "two lines with words, tracked file, working copy")
        stops(lambda: tree(["nothing-here"], g), "a scope with no tracked file")
        os.unlink(os.path.join(g, "t.txt"))
        stops(lambda: tree([], g), "a tracked file missing")
        # a list with no words proves nothing
        nl = os.path.join(d, "nl")
        open(nl, "w").write("# nothing\n")
        stops(lambda: load(nl), "an empty list")
    print("public-text-check --selftest: %s" % ("FAIL" if bad else "PASS"))
    return 1 if bad else 0


def main(a):
    if a[:1] == ["--selftest"]:
        return selftest()
    try:
        if a[:1] == ["--tree"]:
            scopes = []
            r = a[1:]
            while r[:1] == ["--scope"] and len(r) > 1:
                scopes.append(r[1])
                r = r[2:]
            if r:
                raise CouldNotLook("usage")
            hits, said = tree(scopes)
        elif a[:1] == ["--stage"] and len(a) == 2:
            hits, said = stage(a[1])
        elif a[:1] == ["--disc"]:
            hits, said = disc(a[1:])
        else:
            raise CouldNotLook("usage: --tree [--scope PATH]... | --stage DIR | --disc FILE... | --selftest")
    except (CouldNotLook, OSError, subprocess.CalledProcessError) as e:
        print("public-text-check: STOP, could not look: %s" % e, file=sys.stderr)
        return 2
    for h in hits:
        print(h)
    print("public-text-check: %s: %s" % (said, ("%d HITS" % len(hits)) if hits else "clean"))
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
