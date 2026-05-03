#!/usr/bin/env bash
# set_IPs_for_tftp.sh
# Assigns 192.168.7.1/24 to the host Ethernet port connected directly to BBB
# and pings to verify the link.  Run this whenever you need TFTP/SSH access.
#
# USB internet sharing is a SEPARATE one-time setup -> see setup_usb_internet_sharing.sh
set -euo pipefail

BBB_ETH_IP="192.168.7.2"
HOST_ETH_IP="192.168.7.1"

# Returns the interface currently carrying the default route (internet-facing).
get_internet_iface() {
    ip route show default 2>/dev/null | awk 'NR==1{print $5}'
}

# Returns the first UP interface that:
#  - is not lo, not a virtual/loopback type, not the internet interface
#  - has no IPv4 assigned outside 192.168.7.* / 169.254.*
# Carrier is NOT required (BBB may not be booted yet when we run this).
bbb_eth_iface() {
    local internet="$1"
    for iface in $(ls /sys/class/net/); do
        [[ "$iface" == "lo" || "$iface" == "$internet" ]] && continue
        # skip down interfaces (operstate=down AND no flags)
        local flags
        flags=$(cat "/sys/class/net/$iface/flags" 2>/dev/null) || continue
        # flags & IFF_UP (0x1) must be set
        [[ $(( flags & 1 )) -eq 0 ]] && continue
        # skip USB adapters (they are g_ether or the Fritzbox dongle)
        local subsys
        subsys=$(readlink "/sys/class/net/$iface/device/subsystem" 2>/dev/null || true)
        [[ "$subsys" == *"usb"* ]] && continue
        # skip if it already has a foreign (non-BBB) IPv4
        local foreign
        foreign=$(ip -4 addr show "$iface" 2>/dev/null \
            | awk '/inet /&&!/192\.168\.7\./ && !/169\.254\./{print $2; exit}')
        [[ -n "$foreign" ]] && continue
        echo "$iface"; return 0
    done
}

internet_iface=$(get_internet_iface)
echo "Internet interface (skipped): ${internet_iface:-none}"

bbb_eth=$(bbb_eth_iface "$internet_iface" || true)
if [[ -z "$bbb_eth" ]]; then
    echo "ERROR: Cannot detect BBB ethernet interface." \
         "Ensure the cable is connected and BBB is powered." >&2
    exit 1
fi
echo "Detected BBB direct ethernet: $bbb_eth"

# Remove any stale 192.168.7.1 on other interfaces (avoid duplicate routes)
while IFS= read -r stale; do
    sudo ip addr del 192.168.7.1/24 dev "$stale" 2>/dev/null || true
done < <(ip -4 addr show | awk '/inet 192\.168\.7\.1\//{print $NF}')

sudo ip addr add "$HOST_ETH_IP/24" dev "$bbb_eth" 2>/dev/null \
    || echo "(address already set on $bbb_eth)"
sudo ip link set "$bbb_eth" up
echo "Set $HOST_ETH_IP/24 on $bbb_eth"

echo "Pinging BBB at $BBB_ETH_IP ..."
ping -c 4 "$BBB_ETH_IP" \
    && echo "BBB reachable!" \
    || echo "No reply from BBB (may not be booted yet)"
