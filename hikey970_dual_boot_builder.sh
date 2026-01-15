#!/bin/bash

set -ue

DISTRO=${DISTRO:-"bookworm"}
VERSION=${VERSION:-v1.0}
echo "Version:" $VERSION

REQUIRED="debootstrap img2simg mkfs.ext4 mkfs.vfat sgdisk parted losetup"
MIRRORS=${MIRRORS:-}
SOFTWARE="ssh \
,ntpdate \
,firmware-linux-nonfree \
,firmware-ti-connectivity \
,grep \
,vim-nox \
,net-tools \
,wpasupplicant \
,iw \
,systemd \
,dhcpcd5 \
,wireless-tools \
,dbus \
,iproute2 \
,rng-tools5 \
,haveged \
"

SYSTEM_SIZE=${SYSTEM_SIZE:-'2048'} # 2GB for rootfs
BOOT_SIZE=${BOOT_SIZE:-'256'} # 256MB for boot partition
SD_IMAGE_SIZE=${SD_IMAGE_SIZE:-'15000'} # 15GB total for SD card image

# Control flags
STAGE_1=${STAGE_1:-1}  # 1=run, 0=skip
STAGE_2=${STAGE_2:-1}  # 1=run, 0=skip
BUILD_EMMC=${BUILD_EMMC:-1}
BUILD_SDCARD=${BUILD_SDCARD:-1}

# Kernel files directory
KERNEL_DIR=${KERNEL_DIR:-"./rootfs/boot"}

# Rootfs cache directory
ROOTFS_CACHE=${ROOTFS_CACHE:-"build/rootfs"}

usage() {
	cat << EOF
Usage: $0 [OPTIONS]

Build HiKey970 Debian images (eMMC and/or SD card)

OPTIONS:
  --help, -h           Show this help message
  --debug, -d          Enable debug mode (set -x)
  
  Stage Control:
  --stage1-only        Run only stage 1 (debootstrap)
  --stage2-only        Run only stage 2 (skip debootstrap, use cached rootfs)
  --skip-stage1, -s1   Skip stage 1 (alias for --stage2-only)
  
  Build Target:
  --emmc-only          Build only eMMC sparse image
  --sdcard-only        Build only SD card image
  
  Configuration:
  --kernel-dir DIR     Specify kernel files directory (default: ./kernel)
  --distro NAME        Debian/Ubuntu distribution (default: bookworm)
  --version VER        Version tag (default: v1.0)
  --mirrors URL        APT mirror URL
  
  Size Options:
  --system-size MB     Root filesystem size in MB (default: 2048)
  --boot-size MB       Boot partition size in MB (default: 256)
  --sd-size MB         Total SD card image size in MB (default: 15000)

Alignment Options:
  --classic-align      Use classic MBR alignment (sector 63, like old tools)
                       Default: Modern 1MiB alignment (better performance)

EXAMPLES:
  # First time: Build everything (slow due to debootstrap)
  sudo ./build.sh
  
  # Stage 1 only: Create base rootfs (can be reused)
  sudo ./build.sh --stage1-only
  
  # Stage 2 only: Quick rebuild using cached rootfs
  sudo ./build.sh --stage2-only --kernel-dir /path/to/kernel
  
  # Build only SD card image using cached rootfs
  sudo ./build.sh --stage2-only --sdcard-only
  
  # Build for 16GB SD card with custom sizes
  sudo ./build.sh --sd-size 15000 --system-size 14500

EOF
	exit 0
}

while test $# -gt 0; do
case "$1" in
--help|-h)
	usage
	;;
--debug|-d)
	set -x
	shift
	;;
--stage1-only)
	STAGE_1=1
	STAGE_2=0
	BUILD_EMMC=0
	BUILD_SDCARD=0
	shift
	;;
--stage2-only|--skip-stage1|-s1)
	STAGE_1=0
	STAGE_2=1
	shift
	;;
--emmc-only)
	BUILD_EMMC=1
	BUILD_SDCARD=0
	shift
	;;
--sdcard-only)
	BUILD_EMMC=0
	BUILD_SDCARD=1
	shift
	;;
--kernel-dir)
	KERNEL_DIR="$2"
	shift 2
	;;
--distro)
	DISTRO="$2"
	shift 2
	;;
--version)
	VERSION="$2"
	shift 2
	;;
--mirrors)
	MIRRORS="$2"
	shift 2
	;;
--system-size)
	SYSTEM_SIZE="$2"
	shift 2
	;;
--boot-size)
	BOOT_SIZE="$2"
	shift 2
	;;
--sd-size)
	SD_IMAGE_SIZE="$2"
	shift 2
	;;
--classic-align)
	MBR_CLASSIC_ALIGN=1
	shift
	;;
*)
	echo "Unrecognized option: $1"
	echo "Use --help for usage information"
	exit 1
	;;
esac
done

echo "============================================"
echo "HiKey970 Debian Image Builder"
echo "============================================"
echo "Distribution: $DISTRO"
echo "Version: $VERSION"
echo "Fetch from: ${MIRRORS:-default mirrors}"
echo "Install: $SOFTWARE"
echo ""

# Check if running as root for image creation
if [ "$EUID" -ne 0 ]; then 
	echo "Error: This script must be run as root (use sudo)"
	exit 1
fi

echo "Dependency check"
for i in $REQUIRED; do
	command -v $i >/dev/null 2>&1 || { 
		echo >&2 "Error: require $i but it's not installed. Aborting."
		exit 1
	}
	echo "[$i ... OK]"
done

# Stage 1: Debootstrap (slow, but can be cached)
bootstrap_stage_1() {
	echo ""
	echo "============================================"
	echo "STAGE 1: Bootstrap (debootstrap)"
	echo "============================================"
	echo "This stage is SLOW but only needs to run once"
	echo "The result will be cached in ${ROOTFS_CACHE}"
	echo ""
	
	if [ -d "${ROOTFS_CACHE}" ]; then
		echo "Warning: ${ROOTFS_CACHE} already exists!"
		read -p "Remove and rebuild? (y/n) " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			echo "Removing existing rootfs..."
			rm -rf ${ROOTFS_CACHE}
		else
			echo "Keeping existing rootfs, skipping stage 1"
			return 0
		fi
	fi
	
	echo "Creating fresh rootfs via debootstrap..."
	mkdir -p build
	
	debootstrap --arch arm64 --include=${SOFTWARE// /} \
		--components=main,contrib,non-free,non-free-firmware \
		$DISTRO ${ROOTFS_CACHE} $MIRRORS
	
	echo ""
	echo "Stage 1 complete! Rootfs cached at: ${ROOTFS_CACHE}"
	echo "You can now run stage 2 multiple times without repeating this step"
}

# Stage 2: Customize rootfs (fast, can run repeatedly)
bootstrap_stage_2() {
	echo ""
	echo "============================================"
	echo "STAGE 2: Customize rootfs"
	echo "============================================"
	echo "Using cached rootfs from: ${ROOTFS_CACHE}"
	echo ""
	
	if [ ! -d "${ROOTFS_CACHE}" ]; then
		echo "Error: Cached rootfs not found at ${ROOTFS_CACHE}"
		echo "Please run stage 1 first (without --stage2-only)"
		exit 1
	fi
	
	# Create working copy for this build
	WORK_ROOTFS="build/rootfs_work"
	echo "Creating working copy of rootfs..."
	
	if [ -d "${WORK_ROOTFS}" ]; then
		rm -rf ${WORK_ROOTFS}
	fi
	
	mkdir -p ${WORK_ROOTFS}
	
	# Use rsync for efficient copy (or cp if rsync not available)
	if command -v rsync &> /dev/null; then
		echo "Using rsync for fast copy..."
		rsync -a ${ROOTFS_CACHE}/ ${WORK_ROOTFS}/
	else
		echo "Using cp (install rsync for faster copying)..."
		cp -a ${ROOTFS_CACHE}/. ${WORK_ROOTFS}/
	fi
	
	echo "Applying customizations..."
	
	# Create necessary directories if they don't exist
	mkdir -p ${WORK_ROOTFS}/etc/wpa_supplicant
	mkdir -p ${WORK_ROOTFS}/etc/systemd/system
	mkdir -p ${WORK_ROOTFS}/etc/netplan
	mkdir -p ${WORK_ROOTFS}/etc/default
	mkdir -p ${WORK_ROOTFS}/root
	
	# Copy custom configurations if they exist
	[ -d "rootfs/boot" ] && cp -r rootfs/boot/* ${WORK_ROOTFS}/boot/ 2>/dev/null || true
	[ -d "rootfs/etc/netplan" ] && cp -r rootfs/etc/netplan ${WORK_ROOTFS}/etc/ 2>/dev/null || true
	[ -f "rootfs/etc/rc.local" ] && cp rootfs/etc/rc.local ${WORK_ROOTFS}/etc/ 2>/dev/null || true
	[ -d "rootfs/etc/update-motd.d" ] && cp -r rootfs/etc/update-motd.d ${WORK_ROOTFS}/etc/ 2>/dev/null || true
	[ -d "rootfs/etc/wpa_supplicant" ] && cp -r rootfs/etc/wpa_supplicant ${WORK_ROOTFS}/etc/ 2>/dev/null || true
	[ -d "rootfs/etc/systemd/system" ] && cp -r rootfs/etc/systemd/system ${WORK_ROOTFS}/etc/systemd/ 2>/dev/null || true
	[ -f "rootfs/etc/default/rng-tools" ] && cp rootfs/etc/default/rng-tools ${WORK_ROOTFS}/etc/default/ 2>/dev/null || true
	[ -d "rootfs/lib" ] && cp -r rootfs/lib/* ${WORK_ROOTFS}/lib/ 2>/dev/null || true
	[ -d "rootfs/root" ] && cp -r rootfs/root/* ${WORK_ROOTFS}/root/ 2>/dev/null || true
	
	# Run initialization script if exists
	if [ -f "${WORK_ROOTFS}/root/init.sh" ]; then
		echo "Running chroot initialization script..."
		chroot ${WORK_ROOTFS} /root/init.sh || echo "Warning: init.sh failed or not found"
	fi
	
	echo "Stage 2 complete!"
}

# Build eMMC sparse image for fastboot
build_emmc_image() {
	echo ""
	echo "============================================"
	echo "Building eMMC Sparse Image"
	echo "============================================"
	
	WORK_ROOTFS="build/rootfs_work"
	
	if [ ! -d "${WORK_ROOTFS}" ]; then
		echo "Error: Working rootfs not found. Run stage 2 first."
		exit 1
	fi
	
	echo "Creating ${SYSTEM_SIZE}MB ext4 filesystem image..."
	dd if=/dev/zero of=build/rootfs_emmc.img bs=1M count=$SYSTEM_SIZE conv=sparse
	mkfs.ext4 -L rootfs -F build/rootfs_emmc.img
	
	# Mount and populate
	LOOP_MNT=$(mktemp -d)
	mount -o loop build/rootfs_emmc.img ${LOOP_MNT}
	
	echo "Copying rootfs to image (this may take a while)..."
	(cd ${WORK_ROOTFS}; tar -cf - *) | tar -xf - -C ${LOOP_MNT}
	
	sync
	umount ${LOOP_MNT}
	rmdir ${LOOP_MNT}
	
	# Convert to sparse image
	SPARSE_IMG="debian_${DISTRO}_emmc.hikey970.${VERSION}.sparse.img"
	echo "Converting to sparse format for fastboot..."
	img2simg build/rootfs_emmc.img build/${SPARSE_IMG}
	
	# Compress
	echo "Compressing eMMC image..."
	tar -C build -czf build/${SPARSE_IMG}.tar.gz ${SPARSE_IMG}
	
	# Cleanup intermediate file
	rm -f build/rootfs_emmc.img
	
	echo ""
	echo "eMMC image complete:"
	ls -lh build/${SPARSE_IMG}
	sha1sum build/${SPARSE_IMG}
	echo ""
	echo "Flash with: fastboot flash system build/${SPARSE_IMG}"
}

# Build SD card bootable image
build_sdcard_image() {
	echo ""
	echo "============================================"
	echo "Building SD Card Bootable Image"
	echo "============================================"
	
	WORK_ROOTFS="build/rootfs_work"
	
	if [ ! -d "${WORK_ROOTFS}" ]; then
		echo "Error: Working rootfs not found. Run stage 2 first."
		exit 1
	fi
	
	SD_IMG_NAME="debian_${DISTRO}_sdcard.hikey970.${VERSION}.img"
	
	echo "Creating ${SD_IMAGE_SIZE}MB SD card image..."
	dd if=/dev/zero of=build/${SD_IMG_NAME} bs=1M count=0 seek=${SD_IMAGE_SIZE} status=progress
	
	# Create MBR partition table (NOT GPT!)
	# HiKey970 UEFI expects MBR for SD card boot
	echo "Creating MBR partition table..."
	parted -s build/${SD_IMG_NAME} mklabel msdos
	
	# Partitions: boot (FAT32) + rootfs (EXT4)
	# Note: l-loader.bin and fip.bin stay in eMMC, not on SD card
	echo "Creating partitions..."
	
	# Choose alignment strategy
	if [ "${MBR_CLASSIC_ALIGN:-0}" = "1" ]; then
		# Classic MBR alignment (start at sector 63, like old tools)
		echo "Using classic MBR alignment (sector 63)..."
		parted -s build/${SD_IMG_NAME} mkpart primary fat32 63s $((BOOT_SIZE * 2048 - 1))s
	else
		# Modern alignment (start at 1MiB, better for performance)
		echo "Using modern alignment (1MiB)..."
		parted -s build/${SD_IMG_NAME} mkpart primary fat32 1MiB ${BOOT_SIZE}MiB
	fi
	
	# Partition 1: Boot (FAT32, bootable flag)
	parted -s build/${SD_IMG_NAME} set 1 boot on
	
	# Partition 2: Root (EXT4)
	parted -s build/${SD_IMG_NAME} mkpart primary ext4 ${BOOT_SIZE}MiB 100%
	
	parted -s build/${SD_IMG_NAME} print
	
	# Setup loop device
	echo "Setting up loop device..."
	LOOP_DEV=$(losetup -f --show -P build/${SD_IMG_NAME})
	echo "Loop device: ${LOOP_DEV}"
	
	sleep 2
	partprobe ${LOOP_DEV} 2>/dev/null || true
	sleep 1
	
	# Format partitions
	echo "Formatting boot partition (FAT32)..."
	mkfs.vfat -F 32 -n "BOOT" ${LOOP_DEV}p1
	
	echo "Formatting root partition (EXT4)..."
	mkfs.ext4 -L "rootfs" ${LOOP_DEV}p2
	
	# Populate boot partition
	echo "Populating boot partition..."
	BOOT_MNT=$(mktemp -d)
	mount ${LOOP_DEV}p1 ${BOOT_MNT}
	
	# Copy boot files to boot partition
	cp -v -r ${KERNEL_DIR}/* ${BOOT_MNT}
	
	sync
	umount ${BOOT_MNT}
	rmdir ${BOOT_MNT}
	
	# Populate root partition
	echo "Populating root partition (this may take a while)..."
	ROOT_MNT=$(mktemp -d)
	mount ${LOOP_DEV}p2 ${ROOT_MNT}
	
	(cd ${WORK_ROOTFS}; tar -cf - *) | tar -xf - -C ${ROOT_MNT}
	rm -rf ${ROOT_MNT}/boot
	
	sync
	umount ${ROOT_MNT}
	rmdir ${ROOT_MNT}
	
	# Cleanup loop device
	losetup -d ${LOOP_DEV}
	
	# Compress
	echo "Compressing SD card image..."
	gzip -9 build/${SD_IMG_NAME}
	
	echo ""
	echo "SD card image complete:"
	ls -lh build/${SD_IMG_NAME}.gz
	sha1sum build/${SD_IMG_NAME}.gz
	echo ""
	echo "Write to SD card with:"
	echo "  gunzip build/${SD_IMG_NAME}.gz"
	echo "  sudo dd if=build/${SD_IMG_NAME} of=/dev/sdX bs=4M status=progress conv=fsync"
	echo "  (Replace /dev/sdX with your SD card device)"
}

# Main execution flow
main() {
	# Stage 1: Bootstrap (slow, cacheable)
	if [ $STAGE_1 -eq 1 ]; then
		bootstrap_stage_1
	fi
	
	# Stage 2: Customize (fast, repeatable)
	if [ $STAGE_2 -eq 1 ]; then
		bootstrap_stage_2
	fi
	
	# Build images
	if [ $BUILD_EMMC -eq 1 ]; then
		build_emmc_image
	fi
	
	if [ $BUILD_SDCARD -eq 1 ]; then
		build_sdcard_image
	fi
	
	# Summary
	echo ""
	echo "============================================"
	echo "BUILD COMPLETE"
	echo "============================================"
	
	if [ $STAGE_1 -eq 1 ] && [ $STAGE_2 -eq 0 ]; then
		echo "Stage 1 complete. Rootfs cached at: ${ROOTFS_CACHE}"
		echo "Run with --stage2-only to quickly build images from this cached rootfs"
	fi
	
	if [ $BUILD_EMMC -eq 1 ]; then
		echo ""
		echo "eMMC image:"
		echo "  build/debian_${DISTRO}_emmc.hikey970.${VERSION}.sparse.img.tar.gz"
		echo "  Flash: fastboot flash system <image>"
	fi
	
	if [ $BUILD_SDCARD -eq 1 ]; then
		echo ""
		echo "SD card image:"
		echo "  build/debian_${DISTRO}_sdcard.hikey970.${VERSION}.img.gz"
		echo "  Write: dd if=<image> of=/dev/sdX bs=4M status=progress"
		echo ""
		echo "Note: SD boot requires bootloader in eMMC (l-loader.bin, fip.bin)"
	fi
	
	echo ""
}

# Run main
main

exit 0
