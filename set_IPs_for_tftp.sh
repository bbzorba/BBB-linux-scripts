#!/usr/bin/env bash
set -euo pipefail

read -p "Enter server/client: " server_or_client

if [[ "${server_or_client}" == "server" ]]; then
    sudo ip addr add 192.168.7.1/24 dev eno1
    sudo ip link set eno1 up
elif [[ "${server_or_client}" == "client" ]]; then
    sudo ip addr add 192.168.7.2/24 dev eth0
    sudo ip link set eth0 up
else
    echo "Invalid input. Please enter 'server' or 'client'."
    exit 1
fi