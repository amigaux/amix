# ============================================================================
# universal-k46 -- the published 1.1 install CD's 68060 (and 68040) line (amix-1.1-install.iso)
# ============================================================================
# One medium for every 1.1 target: the Z3660 SCSI, an A4091 or A4092, the A3000's SCSI, the
# A4000T's SCSI, the A4000's or A1200's IDE port, and a Buddha's or Catweasel Z-II's IDE ports. Nothing here names the machine: the miniroot finds
# the CD on the cards the kernel registered (kbootset cards; with kbootset -36 only the units
# that answer as CD drives) and records it, and the interview shows every disk of every card
# with its controller and what it holds -- a single blank disk is taken, any other choice is
# typed, and the erase question names the partitions it destroys. The chosen disk's card gives
# the controller, the root device and the boot and root keys. No address, domain or host name:
# the first boot asks. The installed generation carries every driver of the line.
# ============================================================================
PROFILE_NAME=universal-k46
PROFILE_DESC="amigaux 1.1 install (68060 (and 68040)): any Z3660, A4091/A4092, A3000, A4000T, IDE, Buddha or Catweasel Z-II target, found at run time"
INSTALL_LAYOUT=1.1
KERNEL_KPKG=kernel-k46-m
# the installed generation carries every hardware driver of the line; each loads only when its
# match rule finds the card, so the cards a box lacks cost nothing and change no card order
# (buddha's stand-in key mobo:buddha links it on every box: without a board its _load finds none
# and returns ENXIO silently, amix-dlm C4-2 8.2 item 7); xsurf drives an X-Surf or X-Surf-100 as xsf0
KERNEL_MODPKGS="z3660scsi-k46 a4091-k46 a4kt710-k46 gayle-k46 z3660eth-k46 paula-k46 z3660rtg-k46 zz9kbus-k46 zz9ksvc-k46 monsw-k46 cdfs-k46 random-k46 buddha-k46 xsurf-k46"
# the box's fast memory for bootset's mem= (a nominal figure: kbootset's gate reads kinfo's on the box)
TARGET_FASTMEM_MB=32
TARGET_DISK_MB=
TARGET_ROOT_FSTYPE=ufs
SOURCE_KIND=cdfs
INSTALL_VERBOSE=n
DDSIZE_SAFE=n
ANSWERS_ECHO=n
INSTALL_ORDER=
INSTALL_SET=
INSTALL_ATTESTED=y
# the controller and the target come from the machine (setup.sh: TARGET_HBA=auto)
TARGET_HBA=auto
TARGET_ROOT_SLICE=1
TARGET_SWAP_SLICE=2
TARGET_BOOT_SLICE=3
TARGET_ROOT_MB=
TARGET_SWAP_MB=
KERNEL_SDDEVSIZE=fixed
MINIROOT_KERNEL=KD060-FD-fd0
FB_NODENAME=
FB_DOMAIN=
FB_TZNUM=47
FB_TZ=US/Eastern
FB_IP=
FB_NETMASK=
FB_ETHER_IF=aen0
FB_GATEWAY=
FB_ZEN_IP=
FB_ZEN_NETMASK=
FB_DNS1=
FB_DNS2=
FB_KMAP=
FIRSTBOOT_DIALOG=n
FB_ROOT_TELNET=y
FB_SYSLOG=y
FB_REPO_HOST=pkg.amigaux.org
FB_REPO_IP=
FB_REPO_URL=http://pkg.amigaux.org/1.1
# a published medium: no root password hash; the first boot locks root until the dialog sets one
FB_ROOT_SHADOW=none
INSTALL_CPU=040
MINIROOT_FP_PATCH=yes
# a published medium: it carries only the profiles it was mastered with
MEDIUM_PROFILES=requested
# install.sh, setup.sh and l11.sh staged without their comments (tools/strip-sh-comments.py):
# the netinstall RAM disk's room; the sources stay commented, firstboot.sh is staged as written
STRIP_INSTALLER_COMMENTS=y
