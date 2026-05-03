#!/usr/bin/env bash
# build_dynamic_rootfs_busybox.sh
#
# Builds a DYNAMICALLY LINKED BusyBox rootfs for the BeagleBone Black.
# Unlike the static build, BusyBox and all test applications link against
# the ARM glibc at runtime.  This lets you develop and test any dynamically
# linked ARM application without Buildroot or a full distro.
#
# Cross-compile a test program (dynamic by default):
#   arm-linux-gnueabi-gcc -o hello hello.c
#   arm-linux-gnueabi-readelf -d hello | grep NEEDED   # shows required libs
#   cp hello images/dynamic_rootfs/usr/bin/            # add to rootfs, then redeploy
#
# On the BBB after boot:
#   /usr/bin/hello           # runs your app
#   ldd /usr/bin/hello       # not available in BusyBox; use:
#   readelf -d /usr/bin/hello | grep NEEDED

set -euo pipefail

CROSS="arm-linux-gnueabi-"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."
BUSYBOX_DIR="${ROOT_DIR}/busybox-1.37.0"
DYNAMIC_ROOTFS_DIR="${ROOT_DIR}/images/dynamic_rootfs"
KERNEL_DIR="${ROOT_DIR}/images/bbb_cross_build"
OVERLAY_DIR="${SCRIPT_DIR}/rootfs_overlay"

# ARM shared libraries come from the cross-compiler's sysroot.
# arm-linux-gnueabi-gcc --print-sysroot returns "/" (host root) for this toolchain;
# the actual ARM runtime libs are always under /usr/arm-linux-gnueabi/lib/.
SYSROOT_LIB="/usr/${CROSS%%-}/lib"

if [[ ! -d "${BUSYBOX_DIR}" ]]; then
    echo "ERROR: BusyBox source directory not found: ${BUSYBOX_DIR}" >&2
    exit 1
fi

if ! command -v "${CROSS}gcc" >/dev/null 2>&1; then
    echo "ERROR: Cross-compiler not found: ${CROSS}gcc" >&2
    exit 1
fi

if [[ ! -d "${SYSROOT_LIB}" ]]; then
    echo "ERROR: ARM sysroot lib not found at ${SYSROOT_LIB}" >&2
    echo "       Install with: sudo apt install gcc-arm-linux-gnueabi libc6-dev-armel-cross" >&2
    exit 1
fi

cd "${BUSYBOX_DIR}"

make ARCH=arm CROSS_COMPILE="${CROSS}" defconfig

# Disable features that don't cross-compile for ARM.
# Enable shadow password support so login/getty use /etc/shadow.
sed -i \
    -e 's/^CONFIG_SHA1_HWACCEL=.*/# CONFIG_SHA1_HWACCEL is not set/' \
    -e 's/^CONFIG_SHA256_HWACCEL=.*/# CONFIG_SHA256_HWACCEL is not set/' \
    -e 's/^CONFIG_TC=.*/# CONFIG_TC is not set/' \
    -e 's/^CONFIG_FEATURE_SUID=.*/# CONFIG_FEATURE_SUID is not set/' \
    -e 's/^# CONFIG_FEATURE_SHADOWPASSWDS is not set$/CONFIG_FEATURE_SHADOWPASSWDS=y/' \
    -e 's/^# CONFIG_USE_BB_SHADOW is not set$/CONFIG_USE_BB_SHADOW=y/' \
    "${BUSYBOX_DIR}/.config"
# Dynamic linking: ensure CONFIG_STATIC is explicitly OFF.
sed -i 's/^CONFIG_STATIC=.*$/# CONFIG_STATIC is not set/' "${BUSYBOX_DIR}/.config"

make ARCH=arm CROSS_COMPILE="${CROSS}" oldconfig < /dev/null

make ARCH=arm CROSS_COMPILE="${CROSS}" -j"$(nproc)"
make ARCH=arm CROSS_COMPILE="${CROSS}" CONFIG_PREFIX="${DYNAMIC_ROOTFS_DIR}" install

# ============================================================
# Rootfs overlay: copy skeleton files from rootfs_overlay/
# ============================================================
echo "--- Applying rootfs overlay ---"

mkdir -p \
    "${DYNAMIC_ROOTFS_DIR}/dev"  \
    "${DYNAMIC_ROOTFS_DIR}/proc" \
    "${DYNAMIC_ROOTFS_DIR}/sys"  \
    "${DYNAMIC_ROOTFS_DIR}/root"

cp -a "${OVERLAY_DIR}/." "${DYNAMIC_ROOTFS_DIR}/"

SHADOW_PASS=$(openssl passwd -6 -salt 'BBBrootSalt1' root)
printf 'root:%s:0:0:99999:7:::\n' "${SHADOW_PASS}" > "${DYNAMIC_ROOTFS_DIR}/etc/shadow"
chmod 600 "${DYNAMIC_ROOTFS_DIR}/etc/shadow"

echo "--- Rootfs overlay applied ---"

# ============================================================
# ARM shared libraries
#
# Copy all runtime .so files from the cross-compiler sysroot so
# the dynamic linker (ld-linux.so.3) can resolve dependencies of
# BusyBox and any other dynamically linked application at boot.
#
# To add a new app and check its dependencies:
#   arm-linux-gnueabi-gcc -o myapp myapp.c
#   arm-linux-gnueabi-readelf -d myapp | grep NEEDED
#   cp myapp "${DYNAMIC_ROOTFS_DIR}/usr/bin/"
#   # all listed libs must exist in ${DYNAMIC_ROOTFS_DIR}/lib/
# ============================================================
echo "--- Copying ARM shared libraries from ${SYSROOT_LIB} ---"
mkdir -p "${DYNAMIC_ROOTFS_DIR}/lib"
cp -a "${SYSROOT_LIB}"/*.so* "${DYNAMIC_ROOTFS_DIR}/lib/"
echo "--- Libraries copied: $(ls "${DYNAMIC_ROOTFS_DIR}/lib/"*.so* | wc -l) files ---"

# Install kernel modules
cd "${KERNEL_DIR}"
make ARCH=arm CROSS_COMPILE="${CROSS}" INSTALL_MOD_PATH="${DYNAMIC_ROOTFS_DIR}" modules_install