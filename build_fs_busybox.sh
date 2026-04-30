#!/usr/bin/env bash

set -euo pipefail

CROSS="arm-linux-gnueabi-"
BUSYBOX_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/busybox-1.37.0"
STATIC_ROOTFS_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/static_rootfs"
KERNEL_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/images/bbb_cross_build"

if [[ ! -d "${BUSYBOX_DIR}" ]]; then
    echo "ERROR: BusyBox source directory not found: ${BUSYBOX_DIR}" >&2
    exit 1
fi

if ! command -v "${CROSS}gcc" >/dev/null 2>&1; then
    echo "ERROR: Cross-compiler not found: ${CROSS}gcc" >&2
    exit 1
fi

cd "${BUSYBOX_DIR}"

make ARCH=arm CROSS_COMPILE="${CROSS}" defconfig

# Disable features that don't cross-compile for ARM
sed -i \
    -e 's/^CONFIG_SHA1_HWACCEL=.*/# CONFIG_SHA1_HWACCEL is not set/' \
    -e 's/^CONFIG_SHA256_HWACCEL=.*/# CONFIG_SHA256_HWACCEL is not set/' \
    -e 's/^CONFIG_TC=.*/# CONFIG_TC is not set/' \
    -e 's/^CONFIG_FEATURE_SUID=.*/# CONFIG_FEATURE_SUID is not set/' \
    "${BUSYBOX_DIR}/.config"
# Static linking: replace in-place so kconfig doesn't see both lines
sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' "${BUSYBOX_DIR}/.config"
make ARCH=arm CROSS_COMPILE="${CROSS}" oldconfig < /dev/null

make ARCH=arm CROSS_COMPILE="${CROSS}" -j"$(nproc)"
make ARCH=arm CROSS_COMPILE="${CROSS}" CONFIG_PREFIX="${STATIC_ROOTFS_DIR}" install

#install kernel modules to the static rootfs so we can test insmod/modprobe on the BBB without needing to copy them over separately
cd "${KERNEL_DIR}"
make ARCH=arm CROSS_COMPILE="${CROSS}" INSTALL_MOD_PATH="${STATIC_ROOTFS_DIR}" modules_install