#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."
KERNEL_DIR="${ROOT_DIR}/images/bbb_cross_build"
CROSS="arm-linux-gnueabi-"
INSTALL_MOD_PATH="/media/${USER}/rootfs"

if [[ ! -d "${KERNEL_DIR}" ]]; then
	echo "ERROR: Kernel source directory not found: ${KERNEL_DIR}" >&2
	exit 1
fi

if ! command -v "${CROSS}gcc" >/dev/null 2>&1; then
	echo "ERROR: Cross-compiler not found: ${CROSS}gcc" >&2
	exit 1
fi

cd "${KERNEL_DIR}"

make ARCH=arm CROSS_COMPILE="${CROSS}" distclean
make ARCH=arm CROSS_COMPILE="${CROSS}" bb.org_defconfig
#make ARCH=arm CROSS_COMPILE="${CROSS}" menuconfig
make ARCH=arm CROSS_COMPILE="${CROSS}" zImage uImage dtbs LOADADDR=0x80008000 -j4
make ARCH=arm CROSS_COMPILE="${CROSS}" modules -j4

## Modules must be installed to the SD card rootfs so they can be loaded by the kernel on boot.
# if mountpoint -q "${INSTALL_MOD_PATH}" 2>/dev/null; then
# 	sudo make ARCH=arm CROSS_COMPILE="${CROSS}" INSTALL_MOD_PATH="${INSTALL_MOD_PATH}" modules_install
# else
# 	echo "WARNING: ${INSTALL_MOD_PATH} is not mounted. Skipping modules_install."
# 	echo "         Mount the SD card and run manually:"
# 	echo "         sudo make ARCH=arm CROSS_COMPILE=${CROSS} INSTALL_MOD_PATH=${INSTALL_MOD_PATH} modules_install"
# fi

echo "Build complete. Output is in: ${KERNEL_DIR}"
