#!/usr/bin/env bash

set -euo pipefail

BBB_ETH_IP="192.168.7.2"
HOST_ETH_IP="192.168.7.1"
bbb_eth="eno1"

sudo ip addr add "$HOST_ETH_IP/24" dev "$bbb_eth" 
sudo ip link set "$bbb_eth" up
echo "Set $HOST_ETH_IP/24 on $bbb_eth"

echo "Pinging BBB at $BBB_ETH_IP ..."
ping -c 4 "$BBB_ETH_IP" \
    && echo "BBB reachable!" \
    || echo "No reply from BBB (may not be booted yet)"
