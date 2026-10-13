amigaux 1.0 -- Amiga UNIX 2.1 classic 68030 install kit
=======================================================

What this is
  The install kit for Amiga UNIX (Amix) 2.1 on a 68030 Amiga with an MMU
  and a 68882: an A3000 with an A4091 or A4092, or an A4000 with a full
  68030 (MMU) card and an A4091. Other disk controllers: A2091, A3091.
  Ethernet: A2065.

  Tested in emulation only (Amiberry, the two configs below); it has not
  been run on real 68030 hardware for 1.0.

The files
    amix_21_boot-universal.adf   the boot floppy
    amix_21_root-ng.adf          the root floppy
    amix21-install-public-full-r6e-20261010.iso
        the install CD: set 1 standard (17 packages, with X11), set 2
        everything (30 packages)
    amix-1.0-a3000.uae           emulator config: A3000
    amix-1.0-a4000-030.uae       emulator config: A4000/030

  Not included: the Kickstart ROM and the A4091 ROM (v40.13). Use your own.

Where things go
  Machine     CD (SCSI id 3)             Target disk (SCSI id 6)
  A3000       on the A4091/A4092 (1,3)   the A3000's own SCSI
  A4000/030   on the A4091 (0,3)         on the A4091

  Everything on the target disk is erased.

Emulator
  Amiberry 8.3.0 or newer; older versions corrupt data under paging. Put
  the config beside kickstart.rom, a4091.rom, the two ADFs, the CD image
  and target.hdf: an empty file of 200 MB or more (truncate -s 200M
  target.hdf), or one of the empty target images. The configs ship with
  64 MB of memory, which the install needs, and no network card.

Installing
  1. Boot the boot floppy. At "Insert floppy disk 2 (root file system)"
     put in the root floppy (same drive) and press RETURN.
  2. Wait for each question before you type; keys pressed while the
     system is still starting are lost. Answer:
       keyboard                      RETURN (American) or your map's number
       install or repair             RETURN
       It finds the CD: "Installing from the CD-ROM drive at 1,3"
       (0,3 on the A4000/030).
       disk size                     a blank disk only: its real size in MB
       root size, swap size          RETURN
       root file system type         RETURN (ufs)
       software                      RETURN (1, standard), or 2 for
                                     everything on a 512 MB+ target
       verbose, change any           RETURN, RETURN (check that the target
                                     is SCSI id 6 first)
  3. At "Press RETURN to halt the system", press RETURN, wait 10 seconds
     after the halt message, switch off.
  4. Boot the installed disk. The first boot asks for the machine's name,
     time zone, network and passwords; then log in as root.

Disk sizes
  The defaults fill the disk; a 10 MB boot partition sits at its end.
    200 MB disk:   root [158], swap [30]
    512 MB disk:   root [470], swap [30]
    1000 MB disk:  root [958], swap [30]
  Set 1 (standard) needs a 200 MB disk or larger; set 2 (everything)
  needs 512 to 1000 MB on ufs. Install with 64 MB of memory, as the
  configs have: at 16 MB set 2 fails and set 1 is not tested. The largest
  tested root is a 1000 MB disk. Stay below 1024 MB.

After installing
  - Shut down with  shutdown -i0 -g0 -y  and wait 10 seconds after the
    halt message before switching off.
  - Update packages with apkg (apkg update, apkg upgrade ...).

Checksums: listed on the release page beside the files.
