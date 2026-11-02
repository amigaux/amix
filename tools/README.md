# tools

Host-side developer tools: programs that run on the development machine, not
on the Amiga. For example, talking to a running box (run a command, sync
files), the privacy check every push passes, and `dmamask`.

Tools that run on the box itself are ordinary packages under `userland/`.

## privacy-check

`privacy-check` is the gate before anything reaches the public repository: it
checks commits (`--range A..B`, `--all REF`, or `--pre-push` fed by git's
pre-push hook) or a single tree (`--tree REF`) and refuses five classes of
material: private network addresses, the maintainers' local tool files,
secrets such as private keys and access tokens, disk and ROM images,
oversized blobs and the system files listed in `system/MANIFEST.sha256`, and
AI attribution in our own commit messages. Contributors' commits are kept as
written, so the tool-file and attribution classes apply only to our
commits. It prints one line per hit and exits 0 when clean, 1 on hits and 2 on
any error. A commit is judged on what it adds: the address and secret classes
read only the lines it adds relative to its first parent (all of them for a
root commit or a project moved in by a subtree merge), so a change to a file
does not inherit what earlier contributors wrote there, and a push skips
commits that any remote-tracking ref already has (`--exclude-remotes` does the
same for `--range` and `--all`). Public exemptions live in `privacy-allow.txt`, each with its
reason. A maintainer can add local extras that never enter this repository
through the `PRIVACY_PATTERNS` and `PRIVACY_BLOCKED` environment variables.
`test-privacy-check` builds a throwaway repository with one planted hit per
class beside clean controls, runs every mode, and passes only when every plant
is caught and every control passes. Both need only Python 3 and git.

## release-check

`release-check` is the content check every published file passes: an Amix
disk image (each ufs slice of its RDB file by file; any other slice raw, where
a swap slice must be all zero), an ISO 9660 medium, or a directory such as a
package repository tree, where each package datastream is read member by
member. It refuses a Kickstart or board ROM (by its header, or by
sha256 against a ROM register), a private address or local name (the privacy
check's classes 1 and 3 over the text files), a crypt-style password hash, a
PEM private key, a host or user key or a random seed file by its name, and,
in an image, what the build box left: files in `/tmp` or `/var/tmp`, login
records that are not empty, shell histories. The ROM register
and the private patterns are never in this repository: they are given by
path (`--rom-register`, `--private-patterns`, or `ROM_MANIFEST` and
`PRIVACY_PATTERNS`), and without them it refuses to run. Exemptions for what
upstream software ships are in `release-allow.txt`, each with its reason.
It exits 0 clean, 1 on hits and 2 on any failure. The media build and the
package repository's assembly call it. `test-release-check` builds trees that
hold one thing each, as directories, datastreams and ISOs, and passes only
when each is refused or passed as it should be; it needs xorriso.
`lib/rdb.py` and `lib/ufs.py` are the RDB and ufs readers it uses.
