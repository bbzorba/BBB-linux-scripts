#!/usr/bin/env bash
# setup_usb_internet_sharing.sh
#
# ONE-TIME setup on the host PC.  Run this once and forget it.
# After this, every time BBB connects via USB cable, NetworkManager will:
#   1. Assign 10.42.0.1/24 to the g_ether interface (enxbe528e1c67f4)
#   2. Run a DHCP server (dnsmasq) so BBB's usb0 gets an IP in 10.42.0.x
#   3. Set up iptables MASQUERADE so BBB can reach the internet
#
# The BBB side is already configured: S02module loads g_ether with fixed
# MAC addresses, and S45usb_internet runs udhcpc on usb0 at boot.
#
# Requirements: NetworkManager must be running (nmcli available).

set -euo pipefail

# The host-side g_ether interface name is derived from the fixed
# host_addr MAC set in S02module: host_addr=be:52:8e:1c:67:f4
# Linux names it enx + MAC-without-colons = enxbe528e1c67f4
USB_IFACE="enxbe528e1c67f4"
NM_CONN_NAME="BBB-USB-Share"

if ! command -v nmcli >/dev/null 2>&1; then
    echo "ERROR: nmcli not found. NetworkManager is required." >&2
    exit 1
fi

echo "Setting up persistent USB internet sharing for BBB..."
echo "  Host interface : $USB_IFACE (g_ether, fixed MAC be:52:8e:1c:67:f4)"
echo "  Connection name: $NM_CONN_NAME"
echo ""

# Remove stale connection if it exists
if nmcli con show "$NM_CONN_NAME" &>/dev/null; then
    echo "Removing existing '$NM_CONN_NAME' connection..."
    nmcli con delete "$NM_CONN_NAME"
fi

# Create the connection:
#   ipv4.method shared  -> NM assigns IP, runs dnsmasq (DHCP), adds iptables NAT rule
#   ipv4.addresses      -> the host end gets this address; dnsmasq serves .2-.254
#   ipv6.method ignore  -> keep it simple, IPv4 only
#   connection.autoconnect yes -> activates automatically when enxbe528e1c67f4 appears
nmcli con add \
    type ethernet \
    ifname "$USB_IFACE" \
    con-name "$NM_CONN_NAME" \
    ipv4.method shared \
    ipv4.addresses "10.42.0.1/24" \
    ipv6.method ignore \
    connection.autoconnect yes \
    connection.autoconnect-priority 10

echo ""
echo "Connection '$NM_CONN_NAME' created successfully."
echo ""

# Try to activate it immediately (works if BBB USB is already connected)
if ip link show "$USB_IFACE" &>/dev/null; then
    echo "Interface $USB_IFACE is present – activating now..."
    nmcli con up "$NM_CONN_NAME" && echo "Activated!" || echo "(Activation failed – try reconnecting the USB cable)"
else
    echo "Interface $USB_IFACE not present yet (BBB not connected or g_ether not loaded)."
    echo "The connection will activate automatically when BBB USB cable is plugged in."
fi

echo ""
echo "Summary:"
echo "  - Host  : $USB_IFACE -> 10.42.0.1/24  (internet sharing + DHCP)"
echo "  - BBB   : usb0       -> 10.42.0.x/24  (DHCP from NM's dnsmasq)"
echo "  - BBB default route  -> 10.42.0.1 (your PC) -> internet via NAT"
echo ""
echo "No further action needed. This setup survives reboots."
