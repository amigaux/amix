# ============================================================================
# image-k30-ide-2g -- the pre-installed 68030 (k30) 1.1.x image for an IDE master, 1800 MiB
# ============================================================================
# Built by tools/build-preinstalled.sh --kind ide-2g: a fresh install of the image set in emulation (an emulated
# A4000/030, the target the IDE master, the disc on the slave), halted unbooted with the first-boot dialog armed; the user's choices are made at its
# first boot. One image for both IDE ports: the root record names a motherboard controller by identity
# (`sd id=00000000 base=00000000 unit=6 slice=1 mobo`, media/src/installer/l11.sh), with no board base,
# so the A1200's gayle (0xDA0000) and the A4000's (0xDD2020) take the same disk; bootdev and rootdev are
# mobo:gayle and the RDB's DMA mask is gayle's on both. The first-boot cells prove it on each machine.
# The layout: s1 root 1671 MiB, s2 swap 64 MiB, s3 store 64 MiB, no /home slice (TARGET_DATA_MB=0; the
# rest to the whole MiB, 0.94 MiB, stays unallocated, as on the 3600 MiB images). Swap 64 MiB as there.
# 1800 MiB = 1,887,436,800 bytes fits every "2 GB" card found: 4.0% under the smallest (a dd onto a "2GB"
# SD card stopped at 1,967,128,576 B; a SanDisk 2 GB SD is 1,977,614,336 B: the TS-7000 list, 2012-01,
# msg00038-42; a Transcend CF220I 2 GB CF is 2,038,063,104 B, its datasheet). 1900 MiB would not fit them.
# The set: INSTALL_SET below names it (x11 = standard + xtras), as the 3600 MiB images.
# Network: public: no address, so the installer writes `* dhcp` and `hostname dhcp`;
# no name: the first boot asks, and an empty answer is DHCP's name, else amix-xxxx.
# ============================================================================
PROFILE_NAME=image-k30-ide-2g
PROFILE_DESC="the pre-installed 68030 (k30) 1.1.x image for an IDE master, 1800 MiB: root 1671, swap 64, store 64"
INSTALL_LAYOUT=1.1
# the finished disk IS the product: its layout and set are pinned
IMAGE_KIT=y
KERNEL_KPKG=kernel-k30-m
# the installed generation carries every hardware driver of the line; each loads only when its
# match rule finds the card, so the cards a box lacks cost nothing and change no card order;
# buddha drives a Buddha or Catweasel Z-II fitted beside the root's controller, xsurf an X-Surf as xsf0
KERNEL_MODPKGS="z3660scsi-k30 a4091-k30 a4kt710-k30 gayle-k30 z3660eth-k30 paula-k30 z3660rtg-k30 zz9kbus-k30 zz9ksvc-k30 monsw-k30 cdfs-k30 random-k30 buddha-k30 xsurf-k30"
TARGET_FASTMEM_MB=64
TARGET_DISK_MB=1800
TARGET_ROOT_FSTYPE=ufs
SOURCE_KIND=cdfs
INSTALL_VERBOSE=n
DDSIZE_SAFE=n
ANSWERS_ECHO=n
INSTALL_ORDER=
# the image's package set, one line: x11 now; the set with Motif and CDE once they are packaged
INSTALL_SET=x11
INSTALL_ATTESTED=y
CD_SPEC=0,5
SD_BOARDS=gayle
CD_HBA=gayle
TARGET_HBA=gayle
TARGET_SCSI_ID=6
TARGET_ROOT_SLICE=1
TARGET_SWAP_SLICE=2
TARGET_BOOT_SLICE=3
TARGET_ROOT_MB=1671
TARGET_SWAP_MB=64
TARGET_DATA_MB=0
# the 64 MiB swap slice is added whole, as on every 1.1 install (install.sh's default, stepping down when the
# kernel refuses; the boot swap step adds it by its own rules). The 4.25 MB map that once hung an install with
# the whole slice (pkgadd asleep on an oversize kmem request) is gone with the 8 MiB arena of the final kernel.
ROOTDEV=0x00480016
KERNEL_SDDEVSIZE=fixed
MINIROOT_KERNEL=fd0unix
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
FIRSTBOOT_DIALOG=y
FB_ROOT_TELNET=y
FB_SYSLOG=y
FB_REPO_HOST=pkg.amigaux.org
FB_REPO_IP=
FB_REPO_URL=http://pkg.amigaux.org/1.1
# a published medium: no root password hash; the first boot locks root until the dialog sets one
FB_ROOT_SHADOW=none
# the image medium carries only the profiles it was mastered with (no LAN profile)
MEDIUM_PROFILES=requested
# stage install.sh, setup.sh and l11.sh without their comments, as the universal profiles do
STRIP_INSTALLER_COMMENTS=y
