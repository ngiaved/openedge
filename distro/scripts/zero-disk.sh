#!/bin/bash -eux

# Zero out free space so the VirtualBox image compresses better.
# Only run for VirtualBox builds (the qcow2 format does not benefit from this).
dd if=/dev/zero of=/EMPTY bs=1M
rm -f /EMPTY

# Add `sync` so Packer doesn't quit too early, before the large file is deleted.
sync