#!/usr/bin/env bash

set -euo pipefail

CROSS="arm-linux-gnueabi-"
BUSYBOX_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/busybox-1.37.0"
STATIC_ROOTFS_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/images/static_rootfs"
KERNEL_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/images/bbb_cross_build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="${SCRIPT_DIR}/rootfs_overlay"

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
# Enable shadow password support so login/getty use /etc/shadow
sed -i \
    -e 's/^CONFIG_SHA1_HWACCEL=.*/# CONFIG_SHA1_HWACCEL is not set/' \
    -e 's/^CONFIG_SHA256_HWACCEL=.*/# CONFIG_SHA256_HWACCEL is not set/' \
    -e 's/^CONFIG_TC=.*/# CONFIG_TC is not set/' \
    -e 's/^CONFIG_FEATURE_SUID=.*/# CONFIG_FEATURE_SUID is not set/' \
    -e 's/^# CONFIG_FEATURE_SHADOWPASSWDS is not set$/CONFIG_FEATURE_SHADOWPASSWDS=y/' \
    -e 's/^# CONFIG_USE_BB_SHADOW is not set$/CONFIG_USE_BB_SHADOW=y/' \
    "${BUSYBOX_DIR}/.config"
# Static linking: replace in-place so kconfig doesn't see both lines
sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' "${BUSYBOX_DIR}/.config"
make ARCH=arm CROSS_COMPILE="${CROSS}" oldconfig < /dev/null

make ARCH=arm CROSS_COMPILE="${CROSS}" -j"$(nproc)"
make ARCH=arm CROSS_COMPILE="${CROSS}" CONFIG_PREFIX="${STATIC_ROOTFS_DIR}" install

# ============================================================
# Rootfs overlay: copy skeleton files from rootfs_overlay/
#
# All /etc config files (inittab, rcS, passwd, profile, group)
# live in rootfs_overlay/ as normal source files tracked in git.
# Only /etc/shadow is generated here because it contains a
# password hash - the plaintext password must not be in the repo.
# ============================================================

echo "--- Applying rootfs overlay ---"

mkdir -p \
    "${STATIC_ROOTFS_DIR}/dev" \
    "${STATIC_ROOTFS_DIR}/proc" \
    "${STATIC_ROOTFS_DIR}/sys" \
    "${STATIC_ROOTFS_DIR}/root"

cp -a "${OVERLAY_DIR}/." "${STATIC_ROOTFS_DIR}/"

# Generate /etc/shadow from the passwd file.
# Fixed salt keeps the hash identical across builds (reproducible).
# To change the root password, run: openssl passwd -6 -salt BBBrootSalt1 <newpass>
# and update the SHADOW_PASS variable below.
SHADOW_PASS=$(openssl passwd -6 -salt 'BBBrootSalt1' root)
printf 'root:%s:0:0:99999:7:::\n' "${SHADOW_PASS}" > "${STATIC_ROOTFS_DIR}/etc/shadow"
chmod 600 "${STATIC_ROOTFS_DIR}/etc/shadow"

echo "--- Rootfs overlay applied ---"

#install kernel modules to the static rootfs so we can test insmod/modprobe on the BBB without needing to copy them over separately
cd "${KERNEL_DIR}"
make ARCH=arm CROSS_COMPILE="${CROSS}" INSTALL_MOD_PATH="${STATIC_ROOTFS_DIR}" modules_install