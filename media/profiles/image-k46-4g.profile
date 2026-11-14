# ============================================================================
# image-k46-4g -- the pre-installed 68060 (k46) 1.1.x image, 3600 MiB
# ============================================================================
# Built by tools/build-preinstalled.sh: a fresh install of the image set in emulation (an emulated A4000
# with a Z3660, the target its SCSI unit 6), halted unbooted with the first-boot dialog armed; the user's choices are
# made at its first boot. The layout (after the ufs measurement, 2026-10-31):
#   s1 root 2047 MiB (the ufs ceiling: 4194303 blocks), s2 swap 64 MiB, s3 store 64 MiB,
#   s4 /home 1424 MiB (the rest to the whole MiB; 0.94 MiB stays unallocated). Swap is 64 MiB:
#   the kernel's swap -a needs one contiguous block of kernel space for its page table, and 256 MiB
#   could not get one on the 68030 line; 64 MiB is twice a 32 MB machine's memory.
# 3600 MiB = 3,774,873,600 bytes fits every "4 GB" card found: 3.3% under the smallest
# published one (3,904,897,024 B, LinuxQuestions "Mounting micro SD card"; 3,963,617,280 B,
# Raspberry Pi forums t=19468; SanDisk CF 200x 4 GB 4,011,614,208 B, its datasheet).
# The set: INSTALL_SET below names it (x11 = standard + xtras). Motif and CDE are not packaged
# yet; they join by changing that one line to the set that carries them.
# Network: public: no address, so the installer writes `* dhcp` and `hostname dhcp`;
# no name: the first boot asks, and an empty answer is DHCP's name, else amix-xxxx.
# ============================================================================
PROFILE_NAME=image-k46-4g
PROFILE_DESC="the pre-installed 68060 (k46) 1.1.x image, 3600 MiB: root 2047, swap 64, store 64, /home 1424"
INSTALL_LAYOUT=1.1
# the finished disk IS the product: its layout and set are pinned
IMAGE_KIT=y
KERNEL_KPKG=kernel-k46-m
# the installed generation carries every hardware driver of the line; each loads only when its
# match rule finds the card, so the cards a box lacks cost nothing and change no card order;
# buddha drives a Buddha or Catweasel Z-II fitted beside the root's controller, xsurf an X-Surf as xsf0
KERNEL_MODPKGS="z3660scsi-k46 a4091-k46 a4kt710-k46 gayle-k46 z3660eth-k46 paula-k46 z3660rtg-k46 zz9kbus-k46 zz9ksvc-k46 monsw-k46 cdfs-k46 random-k46 buddha-k46 xsurf-k46"
TARGET_FASTMEM_MB=32
TARGET_DISK_MB=3600
TARGET_ROOT_FSTYPE=ufs
SOURCE_KIND=cdfs
INSTALL_VERBOSE=n
DDSIZE_SAFE=n
ANSWERS_ECHO=n
INSTALL_ORDER=
# the image's package set, one line: x11 now; the set with Motif and CDE once they are packaged
INSTALL_SET=x11
INSTALL_ATTESTED=y
CD_SPEC=0,2
SD_BOARDS=z3660scsi
CD_HBA=z3660scsi
TARGET_HBA=z3660scsi
TARGET_SCSI_ID=6
TARGET_ROOT_SLICE=1
TARGET_SWAP_SLICE=2
TARGET_BOOT_SLICE=3
TARGET_ROOT_MB=2047
TARGET_SWAP_MB=64
TARGET_DATA_MB=1424
# the 64 MiB swap slice is added whole (install.sh's default, stepping down when the kernel refuses; the boot
# swap step adds it by its own rules)
ROOTDEV=0x00480016
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
FIRSTBOOT_DIALOG=y
FB_ROOT_TELNET=y
FB_SYSLOG=y
FB_REPO_HOST=pkg.amigaux.org
FB_REPO_IP=
FB_REPO_URL=http://pkg.amigaux.org/1.1
# a published medium: no root password hash; the first boot locks root until the dialog sets one
FB_ROOT_SHADOW=none
INSTALL_CPU=040
MINIROOT_FP_PATCH=yes
X11KIT=rtg
# the image medium carries only the profiles it was mastered with (no LAN profile)
MEDIUM_PROFILES=requested
# stage install.sh, setup.sh and l11.sh without their comments, as the universal profiles do
STRIP_INSTALLER_COMMENTS=y
