#!/usr/bin/env bash
set -euo pipefail

#################################################DIRECTORIES#############################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
BUSYBOX_BUILD_DIR="${ROOT_DIR}/busybox-1.37.0"
KERNEL_IMAGE_DIR="${ROOT_DIR}/images/bbb_cross_build/arch/arm/boot"
KERNEL_MODULES_DIR="${ROOT_DIR}/images/static_rootfs/lib/modules/"
UBOOT_BUILD_DIR="${ROOT_DIR}/images/u-boot/release"
STATIC_ROOTFS_DIR="${ROOT_DIR}/images/static_rootfs"
DYNAMIC_ROOTFS_DIR="${ROOT_DIR}/images/dynamic_rootfs"
SD_BOOT_DIR="/media/${USER}/BOOT"
SD_ROOTFS_DIR="/media/${USER}/rootfs"
#########################################################################################################



###########################################CHECK BEFORE COPYING##########################################
# Check if SD card partitions are mounted
if [[ ! -d "${SD_ROOTFS_DIR}" ]]; then
    echo "ERROR: SD card rootfs partition not mounted at: ${SD_ROOTFS_DIR}" >&2
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
    sudo mkdir -p "${SD_ROOTFS_DIR}/lib/modules/"
    sudo cp -a "${KERNEL_MODULES_DIR}/." "${SD_ROOTFS_DIR}/lib/modules/"
else
    echo "ERROR: Kernel modules directory not found: ${KERNEL_MODULES_DIR}" >&2
    exit 1
fi

# Copy BusyBox binaries
if [[ -d "${BUSYBOX_BUILD_DIR}/_install" ]]; then
    sudo cp -a "${BUSYBOX_BUILD_DIR}/_install/." "${SD_ROOTFS_DIR}/"
else
    echo "ERROR: BusyBox install directory not found: ${BUSYBOX_BUILD_DIR}/_install" >&2
    exit 1
fi
########################################################################################################



###############################################COPY BOOT DIR############################################
# Copy kernel image and device tree blobs to /payload/ (what extlinux/extlinux.conf references)
if [[ -f "${KERNEL_IMAGE_DIR}/zImage" ]]; then
    sudo mkdir -p "${SD_BOOT_DIR}/payload"
    sudo cp -a "${KERNEL_IMAGE_DIR}/zImage" "${SD_BOOT_DIR}/payload/zImage"
    sudo cp -a "${KERNEL_IMAGE_DIR}/dts/am335x-boneblack.dtb" "${SD_BOOT_DIR}/payload/am335x-boneblack.dtb"
else
    echo "ERROR: zImage not found: ${KERNEL_IMAGE_DIR}/zImage" >&2
    echo "       Rebuild the kernel first (build_BBB_kernel.sh)." >&2
    exit 1
fi

# Create initramfs from either static_rootfs or dynamic_rootfs.
# ROOTFS_MODE can be set to static|dynamic (or s|d) for non-interactive usage.
rootfs_choice="${ROOTFS_MODE:-}"
if [[ -z "${rootfs_choice}" ]]; then
    read -p "Select rootfs type (static/dynamic) [s/d]: " rootfs_choice
fi

case "${rootfs_choice}" in
    s|S)
        ROOTFS_DIR="${STATIC_ROOTFS_DIR}"
        ROOTFS_NAME="static_rootfs"
        ;;
    static|STATIC)
        ROOTFS_DIR="${STATIC_ROOTFS_DIR}"
        ROOTFS_NAME="static_rootfs"
        ;;
    d|D)
        ROOTFS_DIR="${DYNAMIC_ROOTFS_DIR}"
        ROOTFS_NAME="dynamic_rootfs"
        ;;
    dynamic|DYNAMIC)
        ROOTFS_DIR="${DYNAMIC_ROOTFS_DIR}"
        ROOTFS_NAME="dynamic_rootfs"
        ;;
    *)
        echo "ERROR: Invalid rootfs selection: ${rootfs_choice}" >&2
        echo "       Use s|d or static|dynamic." >&2
        exit 1
        ;;
esac
# Check if selected rootfs exists
if [[ ! -d "${ROOTFS_DIR}" ]]; then
    echo "ERROR: Selected rootfs directory (${ROOTFS_DIR}) does not exist." >&2
    exit 1
fi
echo "Creating initramfs from ${ROOTFS_NAME} (excluding kernel modules)..."

# Create initramfs
(
    cd "${ROOTFS_DIR}" && \
    find . -path './lib/modules' -prune -o -print | \
    cpio -H newc -o
) | gzip -9 | sudo tee "${SD_BOOT_DIR}/payload/initramfs" > /dev/null
echo "Initramfs created at ${SD_BOOT_DIR}/payload/initramfs"



# Copy u-Boot binaries (if needed for SD card booting)
if [[ -d "${UBOOT_BUILD_DIR}" ]]; then
    sudo cp -a "${UBOOT_BUILD_DIR}/u-boot.img" "${UBOOT_BUILD_DIR}/MLO" "${UBOOT_BUILD_DIR}/spl/u-boot-spl.bin" "${SD_BOOT_DIR}/"
else
    echo "WARNING: U-Boot build directory not found: ${UBOOT_BUILD_DIR}. Skipping U-Boot binaries copy."
fi
########################################################################################################

echo "All binaries and modules copied successfully to SD card."