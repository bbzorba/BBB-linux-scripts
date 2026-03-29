#!/usr/bin/env bash

set -euo pipefail

BOOT_MNT="/media/${USER}/BOOT"
KDIR="/home/${USER}/Desktop/Embedded_Systems/BeagleBone_Black/images/bbb_cross_build/linux"

if [[ ! -d "${BOOT_MNT}" ]]; then
	echo "[error] BOOT partition not mounted at: ${BOOT_MNT}" >&2
	exit 1
fi

cp "${KDIR}/arch/arm/boot/uImage" "${BOOT_MNT}/uImage"
cp "${KDIR}/arch/arm/boot/dts/am335x-boneblack.dtb" "${BOOT_MNT}/dtbs/am335x-boneblack.dtb" 2>/dev/null || \
	cp "${KDIR}/arch/arm/boot/dts/am335x-boneblack.dtb" "${BOOT_MNT}/am335x-boneblack.dtb"

# Device Tree Overlay(s)
mkdir -p "${BOOT_MNT}/overlays"
cp "${KDIR}/arch/arm/boot/dts/overlays/BB-DCAN1-00A0.dtbo" "${BOOT_MNT}/overlays/BB-DCAN1-00A0.dtbo"