#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UBOOT_DIR="${SCRIPT_DIR}/../images/u-boot"
BUILD_DIR="release"
CROSS="arm-linux-gnueabi-"

if [[ ! -d "${UBOOT_DIR}" ]]; then
	echo "ERROR: U-Boot source directory not found: ${UBOOT_DIR}" >&2
	exit 1
fi

if ! command -v "${CROSS}gcc" >/dev/null 2>&1; then
	echo "ERROR: Cross-compiler not found: ${CROSS}gcc" >&2
	exit 1
fi

cd "${UBOOT_DIR}"

make ARCH=arm CROSS_COMPILE="${CROSS}" O="${BUILD_DIR}" distclean
make ARCH=arm CROSS_COMPILE="${CROSS}" O="${BUILD_DIR}" am335x_evm_defconfig
# make ARCH=arm CROSS_COMPILE="${CROSS}" O="${BUILD_DIR}" menuconfig
make ARCH=arm CROSS_COMPILE="${CROSS}" O="${BUILD_DIR}" -j"$(nproc)"

echo "Build complete. Output is in: ${UBOOT_DIR}/${BUILD_DIR}"
