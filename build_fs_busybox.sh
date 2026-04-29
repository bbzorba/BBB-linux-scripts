#!/usr/bin/env bash

set -euo pipefail

BUSYBOX_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/busybox-1.37.0"
CROSS="arm-linux-gnueabi-"
BUILD_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/busybox-1.37.0/build"

if [[ ! -d "${BUSYBOX_DIR}" ]]; then
    echo "ERROR: BusyBox source directory not found: ${BUSYBOX_DIR}" >&2
    exit 1
fi

if ! command -v "${CROSS}gcc" >/dev/null 2>&1; then
    echo "ERROR: Cross-compiler not found: ${CROSS}gcc" >&2
    exit 1
fi

cd "${BUSYBOX_DIR}"

# Clean the source tree so out-of-tree builds work (O= requires a clean source)
make mrproper
# Remove and recreate the out-of-tree build directory (BusyBox requires it to exist)
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

make ARCH=arm CROSS_COMPILE="${CROSS}" O="${BUILD_DIR}" defconfig

# Disable features that don't cross-compile for ARM:
#  - SHA1/SHA256 HWACCEL uses x86-64 SHA-NI instructions
#  - TC (traffic control) uses CBQ kernel headers removed in newer kernels
sed -i \
    -e 's/^CONFIG_SHA1_HWACCEL=.*/# CONFIG_SHA1_HWACCEL is not set/' \
    -e 's/^CONFIG_SHA256_HWACCEL=.*/# CONFIG_SHA256_HWACCEL is not set/' \
    -e 's/^CONFIG_TC=.*/# CONFIG_TC is not set/' \
    "${BUILD_DIR}/.config"
make ARCH=arm CROSS_COMPILE="${CROSS}" O="${BUILD_DIR}" oldconfig < /dev/null

#make ARCH=arm CROSS_COMPILE="${CROSS}" O="${BUILD_DIR}" menuconfig
make ARCH=arm CROSS_COMPILE="${CROSS}" O="${BUILD_DIR}" -j"$(nproc)"
make ARCH=arm CROSS_COMPILE="${CROSS}" O="${BUILD_DIR}" install CONFIG_PREFIX="${BUILD_DIR}/_install"