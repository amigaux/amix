# Reading the artifact, not the document that describes one

**A working-practice note, from four wrong claims made in a single session (2026-09-08/09).**
It is here rather than in a scratch dir because the same mistake is available to anyone
working in this tree, the cure is cheap, and the four instances below all happened to
someone who already knew the rule.

## The class

> **A strong, quotable sentence attached to ONE image or ONE rig, carried into a general
> context without re-checking it against the artifact in front of you.**

The tell is always the same: the claim sounds authoritative *because it is written down
somewhere authoritative*, and the artifact that would confirm or refute it is sitting on
the disk, costing under a minute to read. In all four cases below the artifact was
available and was not read.

## The four

| # | the claim | what it actually was | what refuted it |
|---|---|---|---|
| 1 | "`setuname -n` patches the nodename into the KERNEL FILE; re-run it after every kernel replacement, and it invalidates the kernel's sha256/`sum -r`" | a **per-image note** about `amix-uaebase-golden-2026-07-11` | `strings` on both shipped kernels: **0** occurrences of either hostname. `/stand/unix` contains neither. The box reports `z3660amix` while running a kernel byte-identical to ours |
| 2 | "the metal A4000 has no A2065, so there is no `aen0` on it" | `amix-images`' description of which identity each **lineage was given** (aen0 = Amiberry, zen0 = metal) — a convention, read as a hardware fact | the user's dev SD, on that same A4000, showing `aen0` with 3413 Ipkts |
| 3 | "never use `` ifconfig aen0 `uname -n` `` — it causes a 180 s boot stall" | a real hazard with a **missing scope**: the stall is a DEAD RESOLVER, not the idiom | the working box uses that exact idiom and does not stall, because `/etc/inet/hosts` resolves the name locally |
| 4 | "the box carries the staged `/install` tree, so `emit_zen_hook` can be invoked on it" | a raw-byte scan's **hit counts, read without locating them** — all 17 `S99zen` / 23 `FB_IP` hits were inside one file, `/var/adm/firstboot/firstboot.sh` | walking the image's filesystem: no `/install` tree, no `install.sh`, and `emit_zen_hook` present only inside a comment |

№4 is the sharpest, because the artifact was **my own measurement**: I had the counts and
reported what they meant without asking *where* they were. A grep hit is a location, not a
conclusion.

## Why this tree is unusually good at producing it

Two document classes here read alike and are not alike:

* **`amix-images/README.md`'s "Per-image notes"** are provenance for ONE image in ONE
  lineage — how *that* golden was configured, what quirks *it* has. They are written in
  the imperative ("re-run after any kernel replacement") because they are instructions to
  whoever next touches *that* image.
* **`docs/` and `profiles/README.md`** are platform documentation, meant to generalise.

Instances 1 and 2 both came from the first being read as the second. **The per-image notes
are not platform documentation**, and a claim taken from them has to be re-verified against
the artifact before it is applied to a different image.

## The cure, which is cheap

Before repeating a claim about an artifact you have:

1. **Read the artifact.** This repo already has host-side readers for every format that
   matters — `tools/lib/ufs.py` walks a UFS root, `tools/lib/rdb.py` reads the slice map,
   `tools/lib/s5.py` the s5 images, `strings`/`nm` the kernels. Reading `/etc/vfstab` out
   of a 512 MB image is about five lines of Python and two seconds.
2. **Locate every grep hit before drawing from it.** A count is not a location.
3. **Ask what the sentence was originally about.** A per-image note, a rig note and a
   platform rule look identical once they are quoted out of context.
4. **Say which you have.** "Proven on card 2 five weeks ago" and "proven on the card we are
   shipping" are both useful and are not the same claim; so are "I checked" and "I expect".

## The companion rule

The port arrived at the same discipline from the other direction, in its own §10.2:
**when a log exists, read the log.** Both reduce to one habit — *check the thing itself,
not the description of a thing like it.*
