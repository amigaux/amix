amigaux 1.0 -- Amiga UNIX 2.1 install CD for the Z3660 (68060)
================================================================

What this is
  An install CD for Amiga UNIX (Amix) 2.1 on an Amiga 3000, 4000 or 4000T
  with a Z3660 accelerator (real 68060 or 68LC060), for machines that also
  have an A4091 or A4092 SCSI controller. It offers two package sets:
    1  standard: the base system with X11 (17 packages); the target must
       be 200 MB or larger
    2  everything on the disc (30 packages); the target must be 512 to
       1000 MB, so not the K1 card's 200 MB cd-target.hdf
  Stay below 1024 MB.

  There are two CD images. Pick the one for where your new system will live:

    amix21-install-public060-sd-full-r6e-20261010.iso
        the system goes onto a disk image on the Z3660's SD card at
        Z3660 unit 0 (once installed, the disk boots from any unit 0-5)

    amix21-install-public060-a4092root-full-r6e-20261010.iso
        the system goes onto a disk behind the A4092 (SCSI id 1 on the
        A4092; Amix calls it SCSI id 9)

  You also need two small disk images on the Z3660 SD card. Both are on
  the K1 card (k1/amigaux-1.0-k1-card.zip, in exfat/hdf/):

    r6e-cd1-boot-KD060-ZA-CD-c0-u6.hdf  the installer; map it as Z3660 unit 6
    boot-a4092.hdf                      only for an A4092 root: the boot
                                        disk, Z3660 unit 5 (see below)

Serving the CD
  - A real SCSI CD-ROM drive on the A4091/A4092 at SCSI id 3, or a
    ZuluSCSI on the A4092 serving the image as a CD at id 3.
  - ZuluSCSI: name the image CD3.iso (2048-byte blocks). Leave unit
    attention OFF (do not add that setting to zuluscsi.ini): the CD driver
    cannot recover from a unit attention.
  - The CD is never booted: the Amiga boots the installer disk on the SD.

Installing
  1. Map the installer as Z3660 unit 6 and a blank disk as the target
     (a blank image at a Z3660 unit, or a blank disk at A4092 id 1).
     For an A4092 root, also map boot-a4092.hdf as Z3660 unit 5.
  2. Power on. The installer starts by itself. Answer:
       keyboard                      RETURN (American) or your map's number
       install or repair             RETURN
       It finds the CD: "Installing from the CD-ROM drive at 1,3".
       target disk                   the unit you mapped (asked only when
                                     there is more than one disk to choose)
       root size, swap size          RETURN (swap is 30 MB; it cannot be smaller)
       software                      RETURN (1, standard), or 2 for
                                     everything on a 512 MB+ target
       verbose, change any           RETURN, RETURN
  3. Set 1 takes about 35 minutes, set 2 just under 2 hours (measured on
     an A4000D with the 68060 at 100 MHz). At "Press RETURN to halt the
     system", press RETURN, wait 10 seconds after the halt message,
     switch off.
  4. Map the new system alone (plus boot-a4092.hdf for an A4092 root) and
     power on. The first boot asks for the machine's name, time zone,
     network, package repository and passwords; it reaches the network
     about 10 minutes after power-on.

  The install is interactive only; there is no unattended CD install in
  this release.

A system behind the A4092
  The A4092's ROM does not offer Amix partitions to the Amiga's boot menu,
  so a system on an A4092 disk is started from a small boot disk on the
  Z3660 SD card. That is boot-a4092.hdf:
  - it ships EMPTY and is never bootable on its own (boot priority -128);
  - during the install the installer writes the boot chain onto it, plus a
    record naming the A4092 disk, and then arms it at boot priority 5;
  - keep it mapped as Z3660 unit 5 from then on: it is how that system
    starts. The installed system itself stays on the A4092 disk.

Rules for the CD unit
  Only the CD filesystem may talk to the CD unit. Never run dd, fsck or
  any raw disk tool on the CD's device: a 512-byte read of a 2048-byte CD
  wedges the A4092 bus until power-off. The installer keeps away from it
  by itself.

After installing
  - Shut down with  shutdown -i0 -g0 -y  and wait 10 seconds after the
    halt message before switching off.
  - Do not use reboot or shutdown -i6 on a real 68060: the Z3660 cannot
    reset the CPU.
  - Update packages with apkg (apkg update, apkg upgrade ...).

Checksums: listed on the release page beside the images.
