#!/bin/bash
# Runs very early in boot (before network-online.target) when a static network
# was baked into /etc/netplan/50-openedge.yaml at build time. Regenerates and
# applies the netplan config so the appliance comes up with its static IP.
set -eu

netplan generate 2>/dev/null || true
netplan apply
echo "openedge: static network applied"