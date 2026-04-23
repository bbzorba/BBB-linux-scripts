#!/bin/bash
# BBB_multiboot.sh — Boot the BeagleBone Black via microSD, TFTP, or UART.
#
# Usage:  ./BBB_multiboot.sh <sd|tftp|uart>
#
# Setup: SD card FAT partition (partition 1) contains:
#        /MLO              — U-Boot SPL (loaded by ROM)
#        /u-boot.img       — U-Boot (loaded by SPL)
#        /uEnv.txt         — sets vars, does NOT auto-boot → drops to "=>" prompt
#        /payload/uImage   — kernel
#        /payload/am335x-boneblack.dtb
#        /payload/initramfs
#
# This script sends U-Boot commands over serial to load the 3 boot images
# using the chosen protocol, then issues "bootm" to boot the kernel.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
PORT="${BBB_PORT:-/dev/ttyUSB0}"
BAUD="${BBB_BAUD:-115200}"

KERNEL_ADDR="0x82000000"
DTB_ADDR="0x88000000"
INITRD_ADDR="0x88080000"

BASE="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/images/EmbeddedLinuxBBB/pre-built-images"
SERIAL_DIR="${BASE}/serial-boot"
TFTP_DIR="${BASE}/tftp-boot"
SD_DIR="${BASE}/SD-boot"

TFTP_ROOT="/var/lib/tftpboot"
SERVER_IP="${BBB_SERVER_IP:-192.168.7.1}"
BOARD_IP="${BBB_BOARD_IP:-192.168.7.2}"

KERNEL="uImage"
DTB="am335x-boneblack.dtb"
INITRD="initramfs"

# ── Helpers ───────────────────────────────────────────────────────────────────
die()      { echo "[ERROR] $*" >&2; exit 1; }
info()     { echo "[*] $*"; }
ok()       { echo "[+] $*"; }

require_files() { for f in "$@"; do [[ -f "$f" ]] || die "Missing: $f"; done; }

setup_port() {
    [[ -c "$PORT" ]] || die "$PORT not found."
    stty -F "$PORT" "$BAUD" cs8 -cstopb -parenb raw -echo -hupcl -crtscts -ixon -ixoff
}

# Send a U-Boot command.  Uses simple ">" redirect (write-only), no fd tricks.
send_cmd() {
    info "U-Boot << $1"
    printf '%s\r' "$1" > "$PORT"
    sleep "${2:-1}"
}

# Drain stale data from the port's read buffer (banners etc.)
drain() { timeout 0.5 cat "$PORT" >/dev/null 2>&1 || true; }

# YMODEM transfer: loady + sb
ymodem_send() {
    local file="$1" addr="$2"
    info "Sending $(basename "$file") -> ${addr} ..."
    send_cmd "loady ${addr}" 1
    sleep 3          # let U-Boot enter receive mode and start sending 'C'
    drain            # flush banner so sb sees only the 'C' handshake
    sb --ymodem "$file" <> "$PORT" 1>&0
    ok "$(basename "$file") done."
    sleep 2
}

usage() {
    echo "Usage: $(basename "$0") <sd|tftp|uart>"
    echo "  sd    — boot from microSD  (fastest)"
    echo "  tftp  — boot via TFTP      (fast, good for development)"
    echo "  uart  — boot via YMODEM    (slow, no SD/network needed)"
    exit 0
}

# ── microSD (fastest) ────────────────────────────────────────────────────────
boot_sd() {
    info "=== BOOT: microSD ==="
    require_files "${SD_DIR}/payload/${KERNEL}" "${SD_DIR}/payload/${DTB}" "${SD_DIR}/payload/${INITRD}"
    setup_port

    send_cmd "" 1
    send_cmd "mmc dev 0"
    send_cmd "mmc rescan"
    send_cmd "load mmc 0:1 ${KERNEL_ADDR} payload/${KERNEL}" 2
    send_cmd "load mmc 0:1 ${DTB_ADDR} payload/${DTB}" 2
    send_cmd "load mmc 0:1 ${INITRD_ADDR} payload/${INITRD}" 2
    send_cmd "setenv bootargs console=ttyS0,115200n8 root=/dev/ram0 rw"
    send_cmd "bootm ${KERNEL_ADDR} ${INITRD_ADDR} ${DTB_ADDR}" 2
    ok "Boot command sent."
}

# ── TFTP (fast) ──────────────────────────────────────────────────────────────
boot_tftp() {
    info "=== BOOT: TFTP ==="
    require_files "${TFTP_DIR}/${KERNEL}" "${TFTP_DIR}/${DTB}" "${TFTP_DIR}/${INITRD}"

    # Stage files in TFTP root
    info "Copying to ${TFTP_ROOT} ..."
    if [[ -w "$TFTP_ROOT" ]]; then
        cp "${TFTP_DIR}/${KERNEL}" "${TFTP_DIR}/${DTB}" "${TFTP_DIR}/${INITRD}" "${TFTP_ROOT}/"
    else
        sudo cp "${TFTP_DIR}/${KERNEL}" "${TFTP_DIR}/${DTB}" "${TFTP_DIR}/${INITRD}" "${TFTP_ROOT}/"
    fi

    setup_port
    send_cmd "" 1
    send_cmd "setenv autoload no"
    send_cmd "setenv serverip ${SERVER_IP}"
    send_cmd "setenv ipaddr ${BOARD_IP}"
    send_cmd "tftpboot ${KERNEL_ADDR} ${KERNEL}" 5
    send_cmd "tftpboot ${DTB_ADDR} ${DTB}" 3
    send_cmd "tftpboot ${INITRD_ADDR} ${INITRD}" 5
    send_cmd "setenv bootargs console=ttyS0,115200n8 root=/dev/ram0 rw"
    send_cmd "bootm ${KERNEL_ADDR} ${INITRD_ADDR} ${DTB_ADDR}" 2
    ok "Boot command sent."
}

# ── UART / YMODEM (slowest) ─────────────────────────────────────────────────
boot_uart() {
    info "=== BOOT: UART (YMODEM) ==="
    require_files "${SERIAL_DIR}/${KERNEL}" "${SERIAL_DIR}/${DTB}" "${SERIAL_DIR}/${INITRD}"
    command -v sb &>/dev/null || die "'sb' not found. sudo apt install lrzsz"

    setup_port
    send_cmd "" 1

    # Order: kernel -> DTB -> initramfs  (verified working)
    ymodem_send "${SERIAL_DIR}/${KERNEL}" "$KERNEL_ADDR"
    ymodem_send "${SERIAL_DIR}/${DTB}"    "$DTB_ADDR"
    ymodem_send "${SERIAL_DIR}/${INITRD}" "$INITRD_ADDR"

    send_cmd "bootm ${KERNEL_ADDR} ${INITRD_ADDR} ${DTB_ADDR}" 2
    ok "Boot command sent."
}

# ── Main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
    sd)        boot_sd   ;;
    tftp)      boot_tftp ;;
    uart)      boot_uart ;;
    -h|--help) usage     ;;
    *)         usage     ;;
esac
