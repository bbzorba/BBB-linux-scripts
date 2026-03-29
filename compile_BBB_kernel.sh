#!/usr/bin/env bash

set -euo pipefail

ARCH=arm
CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabi-}
JOBS="${JOBS:-$(nproc)}"

# If we build from a git tree whose tags are not annotated/signed (common),
# scripts/setlocalversion appends a "+" unless LOCALVERSION is explicitly set.
# For BeagleBoard TI kernel tags like "5.10.168-ti-r83", we want the kernel
# release to match that exact string (for module vermagic compatibility).
KERNEL_LOCALVERSION=${KERNEL_LOCALVERSION:-}

KDIR="/home/${USER}/Desktop/Embedded_Systems/BeagleBone_Black/images/bbb_cross_build/linux"
STAGING="/home/${USER}/Desktop/Embedded_Systems/BeagleBone_Black/images/bbb_cross_build/tmp_modules"

cd "${KDIR}"

if [[ -z "${KERNEL_LOCALVERSION}" ]]; then
	kernelver="$(make -s kernelversion)"
	if tag="$(git describe --tags --exact-match 2>/dev/null)"; then
		if [[ "${tag}" == "${kernelver}"* ]]; then
			KERNEL_LOCALVERSION="${tag#${kernelver}}"
		fi
	fi
fi

# Always set LOCALVERSION (even empty) to avoid the automatic "+" suffix.
LOCALVERSION="${KERNEL_LOCALVERSION}"
export LOCALVERSION

if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
	if command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
		echo "[warn] ${CROSS_COMPILE}gcc not found; falling back to arm-linux-gnueabihf-" >&2
		CROSS_COMPILE=arm-linux-gnueabihf-
	else
		echo "[error] compiler '${CROSS_COMPILE}gcc' not found" >&2
		echo "Install one of:" >&2
		echo "  sudo apt-get install gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi" >&2
		echo "  sudo apt-get install gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf" >&2
		exit 1
	fi
fi

make -j"${JOBS}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" bb.org_defconfig
#make -j"${JOBS}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" menuconfig

make -j"${JOBS}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" LOADADDR=0x80000000 uImage dtbs
make -j"${JOBS}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" modules

rm -rf "${STAGING}"
mkdir -p "${STAGING}"

make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" \
	INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="${STAGING}" \
	modules_install
