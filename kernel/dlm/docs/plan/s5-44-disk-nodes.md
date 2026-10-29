# S5-44 — the disk nodes of cards 2 and 3: the recipe for amix-installng

- **Status:** recipe, 2026-10-27 (amix-dlm), for the orchestrator to
  dispatch to amix-installng.
- **Implements:** contract C4-1 version 5 §2.4 (the node set), C2-4
  version 12 §14 (`kbootset nodes`); plan row S5-44.

## 1. The finding

Bench J4 ran row M-G3 on the A4000D: Z3660, A4092 and Gayle, k46
build 68060-261027-82. kinfo ranked three sd cards, with Gayle as card 2
(motherboard flag set). The installed root's `/dev/rdsk` held `c0`–`cf`
with both d0 and d1 names, which is core's stock set, and nothing named
`c10`–`c1f`. Opening `c16d0s0` (IDE-D) and `c15d0s0` (the CD) by name
failed with ENOENT. Nodes made by hand in `/tmp` (character 40, minors
134 and 133) read both disks, so the kernel side is right.

The root still held core's d1 names, so firstboot's step 4d never ran
on it. That step swaps the d1 names for `c10`–`c1f` when the installer
read `sdcards=4` from the kernel's sidecar. Most likely the root was
installed before step 4d existed, or with a kernel whose sidecar did not
carry `sdcards=4`, and apkg later brought its kernel to -82. Nothing on
that path makes nodes. §3 R0 asks installng to confirm which it was.

## 2. What is decided (C4-1 v5 §2.4, C2-4 v12 §14)

- **The set.** When an installed kernel's sidecar says `sdcards=4`,
  the root holds `/dev/dsk/c<N>d0s<S>` (block device 18) and
  `/dev/rdsk/c<N>d0s<S>` (character device 40) for N `0`–`1f` and S 0–7,
  minor as in C4-1 §2.1: 512 nodes, all four cards, whatever the board
  set. It holds no `c<N>d1s<S>` node. The card-2 and card-3 nodes have
  mode 0600, owner root, group root, and are registered to core; core no
  longer names the d1 nodes.
- **The maximum** is four cards (C4-1 §2; a fifth is refused). Card
  numbers move with the board set, but the set does not, so no package
  carries a node list per board.
- **The owner is `kbootset nodes`**, one implementation, following the
  `/dev/kinfo` pattern:
  - `kbootset commit` runs it on the running box, so a root that already
    exists gets the set from apkg's trigger, both when a four-card kernel
    arrives and when `kbootset` -22 itself is installed;
  - `kbootset check` counts an incomplete set as one problem;
  - the installer calls it from firstboot.

## 3. The recipe

**R0. Now (needs nothing new): find out how J4's root came to be.**
Report how the A4000D root of J4 was laid and upgraded:
- the installer version and medium;
- whether `L11_SDCARDS` / `FB_SDCARDS=4` were set;
- the kernel package it was installed with;
- whether firstboot ran step 4d.

If a current medium installs a four-card kernel without step 4d running,
that is an installer bug, and it gets fixed now, before R2.

**R1. Now: check the target after firstboot.** In the installer's
post-install check (`l11-target-check.py`, or the matrix's evidence
step), add: when the target's `/stand/k46/kabi` or `/stand/k30/kabi`
says `sdcards=4`, then:
- `/dev/rdsk/c1fd0s7` is character 40, 255;
- `/dev/dsk/c10d0s0` is block 18, 128;
- no `/dev/*dsk/c?d1s?` exists;
- `/var/sadm/install/contents` names `/dev/rdsk/c1fd0s7` and no d1 node.

Run the check on one install of record per line.

**R2. Once `kbootset` -22 is in the catalog: firstboot calls it.**
Replace the body of firstboot's step 4d (the removef/mknod/installf
loop) with:

```sh
if [ -x /sbin/kbootset ]; then
	_nl=`/sbin/kbootset nodes 2>&1`; _nrc=$?
	echo "firstboot: $_nl"
	[ $_nrc -eq 0 ] || echo "firstboot: WARNING: kbootset nodes failed ($_nrc)"
fi
```

- Drop the `FB_SDCARDS = 4` gate around it: kbootset reads the sidecar
  itself and says `core's nodes stand` on a two-card kernel. Keep
  `FB_SDCARDS` for the root-name rewrite at line 1118.
- Run it as 4d runs today, after the package steps (4b, 4c) and before
  the network steps.
- Keep the log lines' verdicts: success is exit 0 with
  `the four-card set is complete` or `registered to core`.

An upgrade install (`FB_UPGRADED`) goes through firstboot too, so it is
covered by the same call.

**R3. The install miniroot: unchanged.** `ensure_disk_nodes` makes the
target's own nodes (s0–s5, cards 2–3 by minor bit 7) on demand. The
miniroot is not an installed root.

**R4. Media built ahead (S5-31 disk and SD images, S5-32 pre-installed
images, the netinstall roots).** These roots pass through firstboot on
their first boot, and R2 gives them the set there. A root image that
ships already booted, with no firstboot left to run, must pass R1's check
at build time. The media builder then runs `kbootset -R <root> nodes`
(nodes made, registration left) and the first boot's commit or firstboot
completes the registration.

**R5. Not installng's.** Roots that already exist need no installng
step. Installing `kbootset` -22 through apkg runs `commit`, which makes
the set (C2-4 §14).

## 4. Acceptance (the S5-44 ledger row)

1. J4's root on the A4000D, after apkg installs `kbootset` -22:
   - the trigger's commit prints `nodes: made 256, removed 256 d1
     nodes; registered to core`;
   - `c16d0s0` and `c15d0s0` read by name;
   - `kbootset check` reports 0 problems;
   - `pkgchk core` is quiet on `/dev`.
2. A fresh install on Z3660 + A4092 + Gayle (k46) names IDE-D `c16` and
   the CD `c15` with no hand-made node, and passes R1's check.
3. The same on a k30 board set with a card 2.
4. Host: `tests/host/knode.sh` and kbox.sh's check case (amix-dlm,
   `make test`).
