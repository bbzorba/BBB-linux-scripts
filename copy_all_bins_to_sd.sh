#!/usr/bin/env bash
set -euo pipefail

#################################################DIRECTORIES#############################################
BUSYBOX_BUILD_DIR=/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/busybox-1.37.0
KERNEL_IMAGE_DIR=/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/images/bbb_cross_build/arch/arm/boot
KERNEL_MODULES_DIR=/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/images/static_rootfs/lib/modules/
UBOOT_BUILD_DIR=/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/images/u-boot/release
STATIC_ROOTFS_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/images/static_rootfs"
BOOT_DIR="/media/${USER}/BOOT"
ROOTFS_DIR="/media/${USER}/rootfs"
#########################################################################################################



###########################################CHECK BEFORE COPYING##########################################
# Check if SD card partitions are mounted
if [[ ! -d "${ROOTFS_DIR}" ]]; then
    echo "ERROR: SD card rootfs partition not mounted at: ${ROOTFS_DIR}" >&2
    exit 1
fi

# Check for required tools
if ! command -v "arm-linux-gnueabi-gcc" >/dev/null 2>&1; then
    echo "ERROR: Cross-compiler not found: arm-linux-gnueabi-gcc" >&2
    exit 1
fi
#########################################################################################################



###############################################COPY ROOTFS DIR###########################################
# Copy kernel modules
if [[ -d "${KERNEL_MODULES_DIR}" ]]; then
    sudo cp -a "${KERNEL_MODULES_DIR}/." "${ROOTFS_DIR}/lib/modules/"
else
    echo "ERROR: Kernel modules directory not found: ${KERNEL_MODULES_DIR}" >&2
    exit 1
fi

# Copy BusyBox binaries
if [[ -d "${BUSYBOX_BUILD_DIR}/_install" ]]; then
    sudo cp -a "${BUSYBOX_BUILD_DIR}/_install/." "${ROOTFS_DIR}/"
else
    echo "ERROR: BusyBox install directory not found: ${BUSYBOX_BUILD_DIR}/_install" >&2
    exit 1
fi
########################################################################################################



###############################################COPY BOOT DIR############################################
# Copy kernel image and device tree blobs to /payload/ (what extlinux/extlinux.conf references)
if [[ -f "${KERNEL_IMAGE_DIR}/zImage" ]]; then
    sudo mkdir -p "${BOOT_DIR}/payload"
    sudo cp -a "${KERNEL_IMAGE_DIR}/zImage" "${BOOT_DIR}/payload/zImage"
    sudo cp -a "${KERNEL_IMAGE_DIR}/dts/am335x-boneblack.dtb" "${BOOT_DIR}/payload/am335x-boneblack.dtb"
else
    echo "ERROR: zImage not found: ${KERNEL_IMAGE_DIR}/zImage" >&2
    echo "       Rebuild the kernel first (build_BBB_kernel.sh)." >&2
    exit 1
fi

# Create initramfs from static_rootfs and place it in /payload/
if [[ -d "${STATIC_ROOTFS_DIR}" ]]; then
    echo "Creating initramfs from static_rootfs (excluding kernel modules)..."
    # Exclude lib/modules - they are large and already present on the ext4 rootfs partition.
    # The BOOT FAT partition is only 36 MB so keeping the initramfs small is important.
    (cd "${STATIC_ROOTFS_DIR}" && find . -path './lib/modules' -prune -o -print | cpio -H newc -o | gzip -9) | sudo tee "${BOOT_DIR}/payload/initramfs" > /dev/null
else
    echo "WARNING: static_rootfs not found at ${STATIC_ROOTFS_DIR}. Skipping initramfs creation." >&2
fi

# Copy u-Boot binaries (if needed for SD card booting)
if [[ -d "${UBOOT_BUILD_DIR}" ]]; then
    sudo cp -a "${UBOOT_BUILD_DIR}/u-boot.img" "${UBOOT_BUILD_DIR}/MLO" "${UBOOT_BUILD_DIR}/spl/u-boot-spl.bin" "${BOOT_DIR}/"
else
    echo "WARNING: U-Boot build directory not found: ${UBOOT_BUILD_DIR}. Skipping U-Boot binaries copy."
fi
########################################################################################################

echo "All binaries and modules copied successfully to SD card."