#!/usr/bin/env bash
# Repackage the VirtualBox Vagrant box produced by the build into an OVA.
# An OVA is a tar archive containing the OVF descriptor plus its disks.
# Usage: make-ova.sh [artifact-prefix]  (default: virtualbox-ubuntu1804)
set -euo pipefail

prefix="${1:-virtualbox-ubuntu1804}"
here="$(cd "$(dirname "$0")" && pwd)"
box="$here/../builds/${prefix}.box"
ova="$here/../builds/${prefix}.ova"

if [ ! -f "$box" ]; then
  echo "no $box; skipping OVA export"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tar -xf "$box" -C "$tmp"

cd "$tmp"
shopt -s nullglob
files=(*.ovf *.vmdk)
if [ "${#files[@]}" -eq 0 ]; then
  echo "box contains no OVF/VMDK files; skipping OVA export" >&2
  exit 1
fi

# The OVF descriptor and disks must sit at the archive root.
tar -cf "$ova" "${files[@]}"
echo "OVA written to $ova"
