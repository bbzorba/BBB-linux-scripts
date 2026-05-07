#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDROOT_DIR="${SCRIPT_DIR}/../../buildroot-2025.02.13"
CUSTOM_CONFIG="${SCRIPT_DIR}/buildroot_custom.config"
SD_CARD="${SD_CARD:-/dev/sdb}"

if [[ ! -d "${BUILDROOT_DIR}" ]]; then
    echo "ERROR: Buildroot directory not found: ${BUILDROOT_DIR}" >&2
    exit 1
fi

if [[ ! -f "${CUSTOM_CONFIG}" ]]; then
    echo "ERROR: Custom config not found: ${CUSTOM_CONFIG}" >&2
    exit 1
fi

cd "${BUILDROOT_DIR}"

# 1. Use our custom config directly as .config (copy every time to pick up changes).
cp "${CUSTOM_CONFIG}" .config

# 2. Resolve any Kconfig dependencies / fill in hidden defaults silently.
make olddefconfig

# 3. Validate external toolchain before starting a long build.
TOOLCHAIN_PATH="$(sed -n 's/^BR2_TOOLCHAIN_EXTERNAL_PATH="\(.*\)"$/\1/p' .config)"
TOOLCHAIN_PREFIX="$(sed -n 's/^BR2_TOOLCHAIN_EXTERNAL_PREFIX="\(.*\)"$/\1/p' .config)"
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
