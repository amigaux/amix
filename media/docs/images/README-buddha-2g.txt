Amix 1.1.1 pre-installed disk images for a Buddha

amix-1.1.1-k30-buddha-2g.img  the 68030 image, for the first port's master of a Buddha
amix-1.1.1-k46-buddha-2g.img  the 68040/68060 image, for the first port's master of a Buddha
Each is 1800 MiB (1,887,436,800 bytes), so it fits any "2 GB" CF or SD card or larger disk.

The Buddha is Individual Computers' Zorro IDE controller. Each image finds its system on the
Buddha's first port, master drive, by the board's identity and the drive's unit, wherever
Kickstart placed the board and whatever other controllers the machine has (an A4000's own IDE
port, a SCSI card, a Z3660). The 68030 image needs a 68030 (an A2000, A3000 or A4000 with a
68030); the 68040/68060 image needs a 68040 or 68060 (an A4000 with a Z3660, for example). Kickstart
boots the disk through the Buddha's own ROM. Tested in emulation only (the 68030 image with the
Buddha alone, the 68040/68060 image with the Buddha beside a Z3660).

Write the image to the card or disk on a PC (for example `dd if=amix-1.1.1-k46-buddha-2g.img
of=/dev/<card> bs=1M`) and put it on the Buddha's first port as the master; space past 1800 MiB
stays unused. On another position (the first port's slave, the second port), the disk boots once
its boot generation names that unit: from a boot that mounts its root, run `kbootset cards`,
then `kbootset build` with the Buddha's key as the boot and root device and the new unit in the
root record, then `kbootset commit` (the release notes, "Moving the root disk to the Buddha").

  s1 root   1671 MiB ufs     the system, /opt/amix, X11
  s2 swap     64 MiB
  s3 store    64 MiB         the boot store (kbootset generations)

The boot slice (s3) is bootable at priority 2. Kickstart boots the bootable partition with the
highest priority on any disk: an AmigaOS disk at the usual priority 0 loses to Amix, and another
disk above 2 (an older Amix install, say) wins. To change which one boots, change the other
disk's priority (HDToolBox) or this one's.

The image has never been booted. Its first boot asks for the machine's name (RETURN: the name a
DHCP server gives, else amix- and the last four digits of its network card's address), the
network (DHCP, or one static address; an X-Surf is offered as xsf0), the time zone and the
passwords. The system carries the Buddha and X-Surf drivers, as every 1.1.1 system does.

The set is x11: the standard set and xtras, with the OPEN LOOK desktop.
