#!/usr/bin/env python3
# sets.py -- read and resolve tools/repo/sets.conf, the named install sets.
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# The reference implementation of the sets.conf grammar (the grammar itself
# is documented at the top of sets.conf).  Host-side, python3 stdlib only.
# The miniroot's own sh filter loop is a second implementation by necessity
# -- there is no python on a 1991 box -- so this file is what that loop is
# checked against, and tools/repo/tests/run-tests.sh asserts the resolved
# memberships so the two cannot drift silently.
#
# Library:
#     read_sets(path)            -> {set: [member, ...]}  (raw, unexpanded)
#     resolve(sets, name)        -> sorted, de-duplicated package names
#     resolve_all(sets)          -> {set: [package, ...]}
#
# CLI:
#     sets.py                    list the set names and their sizes
#     sets.py <set>              print the resolved membership, one per line
#     sets.py --all              print every set as "<set> <package>" pairs
#     sets.py -f FILE ...        read FILE instead of the sets.conf beside
#                                this script
#
# Exit 0 on success, 1 on a bad set name or a malformed file.  It resolves
# names only: no dependency closure (that is deps.conf + apkg's resolver)
# and no ordering (that is the core-first gate).

import os
import sys

SET_RE_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789-"
PKG_RE_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789+.-_"

DEFAULT_CONF = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "sets.conf")


class SetsError(Exception):
    """sets.conf is malformed, or names a set that does not exist."""


def _valid(token, allowed):
    return bool(token) and token[0].isalnum() and \
        all(c in allowed for c in token)


def read_sets(path):
    """Parse sets.conf; return {set-name: [member, ...]} in file order.

    Members are kept exactly as written, '+' includes included: expansion
    is resolve()'s job, so a caller can inspect the authored structure.
    """
    sets = {}
    with open(path, encoding="utf-8") as fp:
        for lineno, raw in enumerate(fp, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if ":" not in line:
                raise SetsError("%s:%d: expected '<set>: <members>', got %r"
                                % (path, lineno, line))
            name, rest = line.split(":", 1)
            name = name.strip()
            if not _valid(name, SET_RE_CHARS):
                raise SetsError("%s:%d: bad set name %r" % (path, lineno,
                                                            name))
            members = sets.setdefault(name, [])
            for member in rest.split(","):
                member = member.strip()
                if not member:
                    continue
                token = member[1:] if member.startswith("+") else member
                allowed = SET_RE_CHARS if member.startswith("+") \
                    else PKG_RE_CHARS
                if not _valid(token, allowed):
                    raise SetsError("%s:%d: bad member %r in set %r"
                                    % (path, lineno, member, name))
                if member not in members:
                    members.append(member)
    return sets


def resolve(sets, name, _stack=None):
    """Expand '+<set>' includes transitively; return sorted unique names."""
    if name not in sets:
        raise SetsError("no such set: %s (have: %s)"
                        % (name, ", ".join(sorted(sets)) or "none"))
    stack = list(_stack or ())
    if name in stack:
        raise SetsError("include cycle: %s -> %s"
                        % (" -> ".join(stack), name))
    stack.append(name)
    out = set()
    for member in sets[name]:
        if member.startswith("+"):
            out.update(resolve(sets, member[1:], stack))
        else:
            out.add(member)
    return sorted(out)


def resolve_all(sets):
    return dict((name, resolve(sets, name)) for name in sets)


def main(argv):
    path = DEFAULT_CONF
    args = []
    i = 0
    while i < len(argv):
        if argv[i] in ("-f", "--file"):
            i += 1
            if i >= len(argv):
                sys.stderr.write("sets: -f needs a path\n")
                return 1
            path = argv[i]
        elif argv[i] in ("-h", "--help"):
            sys.stdout.write(__doc__ or "")
            return 0
        else:
            args.append(argv[i])
        i += 1

    try:
        sets = read_sets(path)
        if not args:
            for name in sorted(sets):
                members = resolve(sets, name)
                print("%-10s %2d  %s" % (name, len(members),
                                         " ".join(members)))
        elif args == ["--all"]:
            for name in sorted(sets):
                for pkg in resolve(sets, name):
                    print("%s %s" % (name, pkg))
        else:
            for name in args:
                for pkg in resolve(sets, name):
                    print(pkg)
    except (SetsError, OSError) as exc:
        sys.stderr.write("sets: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
