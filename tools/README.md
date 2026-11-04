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
compiled Python (`*.pyc`, `__pycache__/`), oversized blobs and the system files listed in `system/MANIFEST.sha256`, and
AI attribution in our own commit messages. Contributors' commits are kept as
written, so the tool-file and attribution classes apply only to our
commits. It prints one line per hit and exits 0 when clean, 1 on hits and 2 on
any error. A commit is judged on what it adds: the address and secret classes
read only the lines it adds relative to its first parent (all of them for a
root commit or a project moved in by a subtree merge), so a change to a file
does not inherit what earlier contributors wrote there, and a push skips
commits that any remote-tracking ref already has (`--exclude-remotes` does the
same for `--range` and `--all`). A binary file is searched only for the local
patterns, in its bytes as they are and with its NUL bytes taken out (ASCII held
as UTF-16), and a string it already held at the first parent does not count.
Compressed content is not looked inside. Public exemptions live in `privacy-allow.txt`, each with its
reason. A maintainer can add local extras that never enter this repository
through the `PRIVACY_PATTERNS` and `PRIVACY_BLOCKED` environment variables.
`test-privacy-check` builds a throwaway repository with one planted hit per
class beside clean controls, runs every mode, and passes only when every plant
is caught and every control passes. Both need only Python 3 and git.

`ci-privacy-check` is CI's call of it: from a pull request's base, or from the
last tip of a push, or, when a push has none it can use, from the merge base
with `origin/master`. `test-privacy-check` tests it too.

## release-check

`release-check` is the content check every published file passes: an Amix
disk image (each ufs slice of its RDB file by file; any other slice raw, where
a swap slice must be all zero), an ISO 9660 medium, a directory such as a
package repository tree, where each package datastream is read member by
member, or any other file, such as a floppy image (read raw) or a single
package. It refuses a Kickstart or board ROM (by its header, or by
sha256 against a ROM register), a known-bad module (below), a private address or local name (the privacy
check's classes 1 and 3 over the text files), a local name in a binary file
(every binary file and package member, by the privacy check's search for the
private patterns; compressed content is not looked inside), a crypt-style password hash, a
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
when each is refused or passed as it should be; it needs xorriso. Its two
ufs disk image fixtures, a clean one and one with a planted password hash and
private address, are distfiles (`release-check-fixture-*.distfile`) that it
fetches into `out/cache`, since disk images never enter this repository.
`lib/rdb.py` and `lib/ufs.py` are the RDB and ufs readers it uses.

### Known-bad modules

`known-bad-modules.txt` lists the module builds no release may carry, each
with its name, sha256, size and the reason, for example a z3660scsi build
from before its fixed-window gate, which wrote into kernel RAM on an A1200
with a DKB card. release-check finds a listed module two ways:

- **as a file**: any file, or package datastream member, whose sha256 is
  listed is a hit, named by its path;
- **in the bytes**: the bytes of each PATH (of each file, for a directory)
  are searched for the module's 512-byte pieces, cut at its offsets 0, 512,
  1024 and on. A piece of one repeated byte is left out. Each piece is
  searched for at any offset. A ufs fragment or an FFS block starts at
  a multiple of 512 in the file it holds, so every piece lies whole inside
  one block, wherever the disk put the blocks. Nine in ten of a module's
  pieces found is a hit. A later build of the same driver shares few
  pieces (the current z3660scsi shares 1 of the old build's 27) and
  passes. So a module is found inside a disk image, an ISO, a floppy image
  or an uncompressed package without reading any filesystem.

The list keeps no module bytes. Each piece is a line with an anchor (the
piece's most varied 16 bytes and where they lie in it) and the piece's
sha256: the search finds the anchor and confirms the piece by its hash.
`release-check --known-bad-entry NAME MODULE WHY` prints the lines for a
module file; add them to the list with the reason. Deflated content, such as
a compressed boot store, is not searched: what it was made from is checked
file by file where it is built. On a 3.7 GB image the search adds about 8 s.
