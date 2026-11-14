# ============================================================================
# image-k30-buddha -- the pre-installed 68030 (k30) 1.1.x image for a disk on a Buddha, 1800 MiB
# ============================================================================
# Built by tools/build-preinstalled.sh --kind buddha: a fresh install of the image set in emulation
# (an A2000, A3000 or A4000 with a 68030: the Buddha alone, its port-0 master c6d0; the disc on the Buddha's port-1 master), halted unbooted with the first-boot dialog armed;
# the user's choices are made at its first boot. The disk goes on the Buddha's port-0 master: the
# root record names the board by its id and the unit, `sd id=12120000 base=00000000 unit=6 slice=1`
# (amix-dlm C4-2 8.2), wherever Kickstart configured the board and whatever card number the kernel
# gives it; bootdev and rootdev are zorro:1212:00, and Kickstart boots it through the Buddha's ROM.
# A disk on another Buddha unit (port 0 slave 5, port 1 master 3, slave 2) needs its record rewritten
# once: the moved-disk step of amix-dlm C2-4 section 6 (kbootset cards; kbootset build with the
# new unit; kbootset commit), from a boot that mounts the root. The layout is the IDE image's: s1 root
# 1671 MiB, s2 swap 64 MiB, s3 store 64 MiB, no /home slice; 1800 MiB fits every "2 GB" card or disk.
# Network: public: no address, so the installer writes `* dhcp` and `hostname dhcp`.
# ============================================================================
PROFILE_NAME=image-k30-buddha
PROFILE_DESC="the pre-installed 68030 (k30) 1.1.x image for a disk on a Buddha, 1800 MiB: root 1671, swap 64, store 64"
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
CD_SPEC=0,3
SD_BOARDS=buddha
CD_HBA=buddha
TARGET_HBA=buddha
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
