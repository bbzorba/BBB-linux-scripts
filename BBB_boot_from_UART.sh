#!/bin/bash
# BBB_boot_from_UART.sh
#
# Sends uImage, DTB, and initramfs to a BeagleBone Black over UART using
# U-Boot's "loady" (YMODEM).
#
# Setup: SD card has MLO + u-boot.img + uEnv.txt on FAT partition.
#        uEnv.txt does NOT auto-boot, so the board drops to U-Boot "=>" prompt.
#        This script then transfers the 3 boot images over serial via YMODEM.
#
# Requires: lrzsz  (sudo apt install lrzsz)

set -e

# --- Configuration ---
PORT="/dev/ttyUSB0"
BAUD=115200
FILES_DIR="/home/bbzorba/Desktop/Embedded_Systems/BeagleBone_Black/images/EmbeddedLinuxBBB/pre-built-images/serial-boot"

KERNEL_FILE="${FILES_DIR}/uImage"
KERNEL_ADDR="0x82000000"

DTB_FILE="${FILES_DIR}/am335x-boneblack.dtb"
DTB_ADDR="0x88000000"

INITRD_FILE="${FILES_DIR}/initramfs"
INITRD_ADDR="0x88080000"

# --- Preflight checks ---
for f in "$KERNEL_FILE" "$DTB_FILE" "$INITRD_FILE"; do
    [[ -f "$f" ]] || { echo "ERROR: not found: $f"; exit 1; }
done
command -v sb &>/dev/null || { echo "ERROR: 'sb' not found. sudo apt install lrzsz"; exit 1; }
[[ -c "$PORT" ]]          || { echo "ERROR: $PORT not found. Is the board connected?"; exit 1; }

# --- Serial port setup ---
# raw            – no kernel-side line processing
# -echo          – don't echo back characters
# -hupcl         – don't drop DTR when the last fd closes
# -crtscts       – disable HW flow control (BBB debug UART has no RTS/CTS)
# -ixon -ixoff   – disable SW flow control (XON/XOFF bytes would corrupt YMODEM)
stty -F "$PORT" "$BAUD" cs8 -cstopb -parenb raw -echo -hupcl -crtscts -ixon -ixoff

# --- Helpers ---

# Drain any stale data sitting in the port's read buffer (U-Boot banners etc.)
# Runs "cat" for 0.5 s then kills it.  Without this, sb reads the banner as
# garbage and the YMODEM handshake fails.
drain() {
    timeout 0.5 cat "$PORT" >/dev/null 2>&1 || true
}

# Send a command string to U-Boot over the serial port.
send_cmd() {
    echo "[>>>] $1"
    printf '%s\r' "$1" > "$PORT"
    sleep "${2:-1}"
}

# loady + YMODEM transfer of one file.
#   $1 = local file path
#   $2 = U-Boot RAM address
ymodem_send() {
    local file="$1" addr="$2"
    echo ""
    echo "[*] Sending $(basename "$file") -> ${addr} ..."

    # 1) Tell U-Boot to enter YMODEM receive mode
    send_cmd "loady ${addr}" 1

    # 2) Wait for U-Boot to print its banner and start sending 'C' (CRC handshake).
    #    U-Boot sends 'C' every ~1 s, so 3 s guarantees at least 2 cycles.
    sleep 3

    # 3) Drain the banner text so sb only sees fresh 'C' bytes.
    drain

    # 4) Run sb.  <> opens the port once (O_RDWR), 1>&0 points stdout to
    #    the same fd.  sb reads 'C' from U-Boot and begins the transfer.
    sb --ymodem "$file" <> "$PORT" 1>&0
    echo "[+] $(basename "$file") done."

    # 5) Small pause to let U-Boot finish processing before next command.
    sleep 2
}

# --- Main ---
echo "============================================"
echo "  BBB UART Boot — ${PORT} @ ${BAUD}"
echo "============================================"
echo "Make sure the board is at the U-Boot '=>' prompt."
echo ""

# Wake the U-Boot prompt (send empty CR)
send_cmd "" 1

# Transfer order: kernel -> DTB -> initramfs  (user-verified working order)
ymodem_send "$KERNEL_FILE" "$KERNEL_ADDR"
ymodem_send "$DTB_FILE"    "$DTB_ADDR"
ymodem_send "$INITRD_FILE" "$INITRD_ADDR"

# Boot
echo ""
echo "[*] All files loaded. Booting..."
send_cmd "setenv bootargs console=ttyS0,115200n8 root=/dev/ram0 rw"
send_cmd "bootm ${KERNEL_ADDR} ${INITRD_ADDR} ${DTB_ADDR}"

echo "[!] Done. Open a serial terminal on ${PORT} to see kernel output."
