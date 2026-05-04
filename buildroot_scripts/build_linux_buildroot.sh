#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDROOT_DIR="${SCRIPT_DIR}/../../buildroot-2026.02"
FRAGMENT="${SCRIPT_DIR}/buildroot_custom.config"
SD_CARD="/dev/sdb"

if [[ ! -d "${BUILDROOT_DIR}" ]]; then
    echo "ERROR: Buildroot directory not found: ${BUILDROOT_DIR}" >&2
    exit 1
fi

if [[ ! -f "${FRAGMENT}" ]]; then
    echo "ERROR: Config fragment not found: ${FRAGMENT}" >&2
    exit 1
fi

cd "${BUILDROOT_DIR}"

# 1. Start from the official BeagleBone defconfig
make beaglebone_defconfig

# 2. Merge custom settings (toolchain path, hostname, packages, etc.)
support/kconfig/merge_config.sh -m .config "${FRAGMENT}"

# 3. Resolve Kconfig dependencies silently
make olddefconfig

# 4. Validate external toolchain before starting a long build.
TOOLCHAIN_PATH="$(sed -n 's/^BR2_TOOLCHAIN_EXTERNAL_PATH="\(.*\)"$/\1/p' .config)"
TOOLCHAIN_PREFIX="$(sed -n 's/^BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX="\(.*\)"$/\1/p' .config)"
CC_PATH="${TOOLCHAIN_PATH}/bin/${TOOLCHAIN_PREFIX}-gcc"

if [[ ! -x "${CC_PATH}" ]]; then
    echo "ERROR: External toolchain compiler not found or not executable:" >&2
    echo "       ${CC_PATH}" >&2
    exit 1
fi

if ! file "${CC_PATH}" | grep -q 'x86-64'; then
    echo "ERROR: External toolchain host architecture mismatch." >&2
    echo "       Host is x86_64 Linux, but compiler binary is:" >&2
    file "${CC_PATH}" >&2
    echo "       Install the x86_64-hosted toolchain variant and update BR2_TOOLCHAIN_EXTERNAL_PATH." >&2
    exit 1
fi

make -j"$(nproc)"

# Write SD card image if the block device is present
if [[ -b "${SD_CARD}" ]]; then
    echo "Writing SD card image to ${SD_CARD}..."
    sudo dd if=output/images/sdcard.img of="${SD_CARD}" bs=4M conv=fsync
    sync
    echo "SD card written successfully."
else
    echo "WARNING: ${SD_CARD} not detected. Skipping SD card write."
    echo "         Run manually: sudo dd if=${BUILDROOT_DIR}/output/images/sdcard.img of=${SD_CARD} bs=4M conv=fsync"
fi
